using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace Vilep.Api.Infrastructure;

public record CheckoutSession(Guid ContributionId, Guid CaseId, string CaseCode, long Amount, string Description, string ReturnUrl, string CancelUrl);

public record CheckoutResult(string ProviderRef, string CheckoutUrl, string QrPayload);

public record WebhookPayload(string ProviderRef, long Amount, bool Success, string RawJson, string? FailureReason = null);

public record DisbursementRequest(Guid PayoutId, string BankCode, string AccountNumber, string AccountName, long Amount, string Description);

public record DisbursementResult(bool Success, string? ProviderRef, string? FailureReason, string? ReceiptKey);

public record RefundRequest(Guid RefundId, string ProviderRef, long Amount, string Reason);

public record RefundResult(bool Success, string? ProviderRef, string? FailureReason);

public interface IPaymentGateway
{
    string Name { get; }
    Task<CheckoutResult> CreateCheckoutAsync(CheckoutSession session, CancellationToken ct);
    WebhookPayload? ParseWebhook(string rawBody, string? signature);
    Task<DisbursementResult> DisburseAsync(DisbursementRequest request, CancellationToken ct);
    Task<RefundResult> RefundAsync(RefundRequest request, CancellationToken ct);
    string Sign(string rawBody);
}

/// <summary>
/// Local development gateway: creates a hosted "fake bank" page, signs webhooks with HMAC-SHA256
/// exactly like a real provider would, so idempotency/reconciliation code is exercised for real.
/// </summary>
public class MockPaymentGateway : IPaymentGateway
{
    private readonly PaymentOptions _opt;

    public MockPaymentGateway(IOptions<PaymentOptions> opt) => _opt = opt.Value;

    public string Name => "mock";

    public Task<CheckoutResult> CreateCheckoutAsync(CheckoutSession session, CancellationToken ct)
    {
        var providerRef = "MOCK-" + Guid.NewGuid().ToString("N")[..14].ToUpperInvariant();
        var url = $"{_opt.BaseUrl}/pay/mock/{providerRef}";
        var qr = $"VILEP|{session.CaseCode}|{session.Amount}|{providerRef}";
        return Task.FromResult(new CheckoutResult(providerRef, url, qr));
    }

    public WebhookPayload? ParseWebhook(string rawBody, string? signature)
    {
        if (string.IsNullOrWhiteSpace(signature)) return null;
        if (!Hash.FixedTimeEquals(Sign(rawBody), signature.Trim())) return null;
        try
        {
            using var doc = JsonDocument.Parse(rawBody);
            var root = doc.RootElement;
            var providerRef = root.GetProperty("providerRef").GetString() ?? "";
            var amount = root.GetProperty("amount").GetInt64();
            var success = root.TryGetProperty("status", out var st) && st.GetString() == "paid";
            var reason = root.TryGetProperty("failureReason", out var fr) ? fr.GetString() : null;
            return new WebhookPayload(providerRef, amount, success, rawBody, reason);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public string Sign(string rawBody) => Hash.Hmac(_opt.WebhookSecret, rawBody);

    public Task<DisbursementResult> DisburseAsync(DisbursementRequest request, CancellationToken ct)
    {
        var reference = "PAYOUT-" + Guid.NewGuid().ToString("N")[..12].ToUpperInvariant();
        return Task.FromResult(new DisbursementResult(true, reference, null, null));
    }

    public Task<RefundResult> RefundAsync(RefundRequest request, CancellationToken ct)
    {
        var reference = "REFUND-" + Guid.NewGuid().ToString("N")[..12].ToUpperInvariant();
        return Task.FromResult(new RefundResult(true, reference, null));
    }
}

/// <summary>
/// PayOS adapter. Keys are read from configuration/env (Payments__ChecksumKey ...).
/// Create-payment + webhook signature follow PayOS' documented HMAC-SHA256 checksum scheme.
/// Disbursement to a third party is not offered by PayOS, so payout falls back to manual
/// finance entry (the case stays in payout_pending until an admin records the transfer).
/// </summary>
public class PayOsPaymentGateway : IPaymentGateway
{
    private readonly PaymentOptions _opt;
    private readonly HttpClient _http;
    private readonly ILogger<PayOsPaymentGateway> _logger;

    public PayOsPaymentGateway(IOptions<PaymentOptions> opt, HttpClient http, ILogger<PayOsPaymentGateway> logger)
    {
        _opt = opt.Value;
        _http = http;
        _logger = logger;
    }

    public string Name => "payos";

    public async Task<CheckoutResult> CreateCheckoutAsync(CheckoutSession session, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_opt.ChecksumKey))
            throw ApiException.BadRequest("payment_not_configured", "Chưa cấu hình khoá PayOS (Payments__ChecksumKey)");

        var orderCode = long.Parse(DateTimeOffset.UtcNow.ToUnixTimeMilliseconds().ToString()[^10..]);
        var body = new
        {
            orderCode,
            amount = session.Amount,
            description = session.Description.Length > 25 ? session.Description[..25] : session.Description,
            items = new[] { new { name = session.Description, quantity = 1, price = session.Amount } },
            cancelUrl = session.CancelUrl,
            returnUrl = session.ReturnUrl,
            signature = SignPayOs($"amount={session.Amount}&cancelUrl={session.CancelUrl}&description={session.Description}&orderCode={orderCode}&returnUrl={session.ReturnUrl}")
        };

        using var req = new HttpRequestMessage(HttpMethod.Post, $"{_opt.BaseUrl}/v2/payment-requests")
        {
            Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
        };
        req.Headers.Add("x-client-id", _opt.ClientId);
        req.Headers.Add("x-api-key", _opt.ApiKey);

        var res = await _http.SendAsync(req, ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        if (!res.IsSuccessStatusCode)
            throw ApiException.BadRequest("payment_provider_error", $"PayOS lỗi: {(int)res.StatusCode}");

        using var doc = JsonDocument.Parse(raw);
        if (!doc.RootElement.TryGetProperty("data", out var data))
            throw ApiException.BadRequest("payment_provider_error", "PayOS trả về dữ liệu không hợp lệ");

        var checkoutUrl = data.TryGetProperty("checkoutUrl", out var cu) ? cu.GetString() ?? "" : "";
        var qr = data.TryGetProperty("qrCode", out var q) ? q.GetString() ?? "" : "";
        var paymentLinkId = data.TryGetProperty("paymentLinkId", out var pl) ? pl.GetString() ?? "" : "";
        return new CheckoutResult(paymentLinkId, checkoutUrl, qr);
    }

    public WebhookPayload? ParseWebhook(string rawBody, string? signature)
    {
        if (string.IsNullOrWhiteSpace(signature)) return null;
        using var doc = JsonDocument.Parse(rawBody);
        if (!doc.RootElement.TryGetProperty("data", out var data)) return null;
        var canonical = string.Join("&", data.EnumerateObject()
            .OrderBy(p => p.Name, StringComparer.Ordinal)
            .Select(p => $"{p.Name}={p.Value}")
            .ToArray());
        var expected = SignPayOs(canonical);
        if (!Hash.FixedTimeEquals(expected, signature)) return null;
        var providerRef = data.TryGetProperty("paymentLinkId", out var pl) ? pl.GetString() ?? "" : "";
        var amount = data.TryGetProperty("amount", out var a) ? a.GetInt64() : 0;
        // PayOS only pushes successful payments to the webhook URL.
        return new WebhookPayload(providerRef, amount, true, rawBody);
    }

    public string Sign(string rawBody) => SignPayOs(rawBody);

    private string SignPayOs(string canonical)
    {
        var hash = HMACSHA256.HashData(Encoding.UTF8.GetBytes(_opt.ChecksumKey), Encoding.UTF8.GetBytes(canonical));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public Task<DisbursementResult> DisburseAsync(DisbursementRequest request, CancellationToken ct)
    {
        _logger.LogWarning("PayOS payout requested for {Payout}; adapter has no third-party disbursement, requires manual finance entry", request.PayoutId);
        return Task.FromResult(new DisbursementResult(false, null, "payos_manual_payout_required", null));
    }

    public Task<RefundResult> RefundAsync(RefundRequest request, CancellationToken ct)
    {
        return Task.FromResult(new RefundResult(false, null, "payos_refund_requires_manual_action"));
    }
}
