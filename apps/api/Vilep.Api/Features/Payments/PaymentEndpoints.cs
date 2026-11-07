using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Vilep.Api.Data;
using Vilep.Api.Domain;
using Vilep.Api.Features.Cases;
using Vilep.Api.Infrastructure;
using Vilep.Api.Services;

namespace Vilep.Api.Features.Payments;

public static class PaymentEndpoints
{
    public static void MapPaymentEndpoints(this IEndpointRouteBuilder app)
    {
        var v1 = app.MapGroup("/api/v1");

        v1.MapPost("/cases/{id:guid}/contributions", ContributeAsync).RequireAuthorization();
        v1.MapGet("/me/contributions", MyContributionsAsync).RequireAuthorization();
        v1.MapGet("/contributions/{id:guid}/receipt", ReceiptAsync).RequireAuthorization();
        v1.MapPost("/webhooks/payment/{provider}", WebhookAsync).AllowAnonymous();
        v1.MapGet("/dev/pay/mock/{providerRef}", MockPayPageAsync).AllowAnonymous();
        v1.MapPost("/dev/pay/mock/{providerRef}", MockPayConfirmAsync).AllowAnonymous();
        v1.MapPost("/dev/pay/{contributionId:guid}", DevSimulateAsync).RequireAuthorization();
        v1.MapGet("/dev/pay/return", () => Results.Content(
            "<html><body style='font-family:sans-serif;padding:40px'><h2>Đã quay lại Ví Lép</h2><p>Bạn có thể đóng tab này và xem lại app.</p></body></html>",
            "text/html; charset=utf-8")).AllowAnonymous();
    }

    private static async Task<IResult> ContributeAsync(Guid id, CreateContributionRequest req, HttpContext http,
        VilepDbContext db, CurrentUser current, ContributionService service, IPaymentGateway gateway,
        IOptions<VilepOptions> options, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var key = http.Request.Headers["Idempotency-Key"].FirstOrDefault();
        var created = await service.CreateAsync(userId, id, req, key, ct);
        var simulateUrl = gateway.Name == "mock"
            ? $"{options.Value.BaseUrl}/api/v1/dev/pay/{created.ContributionId}"
            : null;
        return ApiResult.Ok(new { created, simulateUrl });
    }

    private static async Task<IResult> WebhookAsync(string provider, HttpContext http, ContributionService service,
        PayoutService payouts, RefundService refunds, VilepDbContext db, ILogger<ContributionService> logger, CancellationToken ct)
    {
        http.Request.EnableBuffering();
        using var reader = new StreamReader(http.Request.Body, Encoding.UTF8);
        var body = await reader.ReadToEndAsync(ct);

        var signature = http.Request.Headers["X-Vilep-Signature"].FirstOrDefault()
                        ?? http.Request.Headers["x-payos-signature"].FirstOrDefault();

        var outcome = await service.HandleWebhookAsync(provider, body, signature, ct);
        logger.LogInformation("Webhook {Provider} ref processed: contributed={Credited} duplicate={Duplicate}",
            provider, outcome.Credited, outcome.Duplicate);

        if (outcome.OverpayRefundId is not null)
            await TryRefundOverpayAsync(db, refunds, outcome.OverpayRefundId.Value, ct);

        if (outcome.BecameFunded)
            await TryCreateAndProcessPayoutAsync(db, payouts, outcome.CaseId, ct);

        return ApiResult.Ok(new { received = true, duplicate = outcome.Duplicate, credited = outcome.Credited });
    }

    private static async Task TryRefundOverpayAsync(VilepDbContext db, RefundService refunds, Guid refundId, CancellationToken ct)
    {
        var refund = await db.Refunds.FirstOrDefaultAsync(r => r.Id == refundId, ct);
        if (refund is null) return;
        var contribution = await db.Contributions.FirstAsync(x => x.Id == refund.ContributionId, ct);
        var c = await db.Cases.FirstAsync(x => x.Id == refund.CaseId, ct);
        await refunds.RefundContributionAsync(contribution, c, refund.Reason, LedgerAccounts.GatewayClearing, ct);
    }

    private static async Task TryCreateAndProcessPayoutAsync(VilepDbContext db, PayoutService payouts, Guid caseId, CancellationToken ct)
    {
        var c = await db.Cases.FirstAsync(x => x.Id == caseId, ct);
        var payout = await payouts.EnsureOrderAsync(c, ct);
        await db.SaveChangesAsync(ct);
        await payouts.AutoProcessIfAllowedAsync(payout, c, ct);
    }

    private static async Task<IResult> MyContributionsAsync(VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var rows = await db.Contributions.AsNoTracking()
            .Include(x => x.Case)!.ThenInclude(c => c!.Debtor)
            .Where(x => x.ContributorId == userId && x.State != ContributionStates.Pending)
            .OrderByDescending(x => x.CreatedAt)
            .Take(100)
            .ToListAsync(ct);

        return ApiResult.Ok(new
        {
            items = rows.Select(x => new
            {
                id = x.Id,
                amount = x.Amount,
                tipAmount = x.TipAmount,
                state = x.State,
                anonymous = x.Anonymous,
                message = x.Message,
                createdAt = x.CreatedAt,
                paidAt = x.PaidAt,
                caseId = x.CaseId,
                caseCode = x.Case?.Code,
                caseTitle = x.Case?.Title,
                caseCategory = x.Case?.Category,
                caseState = x.Case?.State,
                debtorName = x.Case?.Debtor?.Nickname
            })
        });
    }

    private static async Task<IResult> ReceiptAsync(Guid id, VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var contribution = await db.Contributions.AsNoTracking()
            .Include(x => x.Case)!.ThenInclude(c => c!.Debtor)
            .FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy khoản góp");
        if (contribution.ContributorId != userId && contribution.Case?.DebtorId != userId && !current.IsAdmin)
            throw ApiException.NotFound("Không tìm thấy khoản góp");

        var entries = await db.LedgerEntries.AsNoTracking()
            .Where(e => e.RefType == "contribution" && e.RefId == id)
            .OrderBy(e => e.CreatedAt).ToListAsync(ct);
        var refunds = await db.Refunds.AsNoTracking().Where(r => r.ContributionId == id).ToListAsync(ct);

        return ApiResult.Ok(new
        {
            receiptCode = "RCP-" + id.ToString("N")[..10].ToUpperInvariant(),
            contribution = new
            {
                contribution.Id,
                contribution.Amount,
                contribution.TipAmount,
                contribution.FeeAmount,
                contribution.State,
                contribution.Anonymous,
                contribution.Message,
                contribution.PaidAt,
                contribution.CreatedAt
            },
            caseInfo = new
            {
                contribution.CaseId,
                contribution.Case?.Code,
                contribution.Case?.Title,
                contribution.Case?.PayoutMode,
                contribution.Case?.State,
                debtor = contribution.Case?.Debtor?.Nickname
            },
            ledger = entries.Select(e => new { e.DebitAccount, e.CreditAccount, e.Amount, e.CreatedAt }),
            refunds = refunds.Select(r => new { r.Amount, r.State, r.Reason, r.DoneAt })
        });
    }

    private static async Task<IResult> MockPayPageAsync(string providerRef, VilepDbContext db, IOptions<PaymentOptions> pay,
        CancellationToken ct)
    {
        var payment = await db.PaymentTransactions.AsNoTracking().FirstOrDefaultAsync(x => x.ProviderRef == providerRef, ct);
        if (payment is null) return Results.Content("<h1>Không tìm thấy giao dịch</h1>", "text/html; charset=utf-8", statusCode: 404);
        var contribution = await db.Contributions.AsNoTracking().FirstOrDefaultAsync(c => c.Id == payment.ContributionId, ct);
        var c = contribution is null ? null : await db.Cases.AsNoTracking().FirstOrDefaultAsync(x => x.Id == contribution.CaseId, ct);

        var html = $$"""
        <!doctype html>
        <html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Ví Lép — Thanh toán</title>
        <style>
        body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F7F7F5;margin:0;padding:24px;color:#111}
        .card{max-width:420px;margin:32px auto;background:#fff;border-radius:20px;padding:28px;box-shadow:0 8px 30px rgba(0,0,0,.08)}
        .brand{font-weight:800;font-size:20px;color:#05CE78;margin-bottom:4px}
        h1{font-size:22px;margin:8px 0 16px}
        .amount{font-size:40px;font-weight:800;margin:12px 0}
        .row{display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px dashed #eee;font-size:14px}
        button{width:100%;padding:16px;border:0;border-radius:999px;background:#05CE78;color:#04170E;font-size:16px;font-weight:800;margin-top:20px;cursor:pointer}
        .muted{color:#777;font-size:12px;margin-top:14px;line-height:1.5}
        </style></head><body>
        <div class="card">
          <div class="brand">VÍ LÉP</div>
          <h1>{{(c is null ? "Thanh toán" : c.Title)}}</h1>
          <div class="amount">{{payment.Amount:N0}}đ</div>
          <div class="row"><span>Tiền xoá nợ</span><span>{{(contribution?.Amount ?? 0):N0}}đ</span></div>
          <div class="row"><span>Tip tự nguyện</span><span>{{(contribution?.TipAmount ?? 0):N0}}đ</span></div>
          <div class="row"><span>Phí xử lý</span><span>{{(contribution?.FeeAmount ?? 0):N0}}đ</span></div>
          <div class="row"><span>Mã giao dịch</span><span>{{providerRef}}</span></div>
          <form method="post" action="/api/v1/dev/pay/mock/{{providerRef}}?secret={{DevSecret(pay.Value, providerRef)}}">
            <button type="submit">Thanh toán ngay (sandbox)</button>
          </form>
          <div class="muted">Đây là cổng thanh toán giả lập cho môi trường phát triển. Không có tiền thật nào được chuyển.
          Webhook gửi về server được ký HMAC-SHA256 giống cổng thật.</div>
        </div></body></html>
        """;
        return Results.Content(html, "text/html; charset=utf-8");
    }

    private static async Task<IResult> MockPayConfirmAsync(string providerRef, string? secret, VilepDbContext db,
        ContributionService service, PayoutService payouts, RefundService refunds, IOptions<PaymentOptions> pay,
        IOptions<VilepOptions> options, IPaymentGateway gateway, CancellationToken ct)
    {
        if (!options.Value.EnableDevPayments)
            return Results.Content("<h1>Tính năng giả lập thanh toán đang tắt</h1>", "text/html; charset=utf-8", statusCode: 404);
        if (!Hash.FixedTimeEquals(DevSecret(pay.Value, providerRef), secret ?? ""))
            return Results.Content("<h1>Liên kết không hợp lệ</h1>", "text/html; charset=utf-8", statusCode: 403);

        var payment = await db.PaymentTransactions.FirstOrDefaultAsync(x => x.ProviderRef == providerRef, ct);
        if (payment is null) return Results.Content("<h1>Không tìm thấy giao dịch</h1>", "text/html; charset=utf-8", statusCode: 404);

        var payload = JsonSerializer.Serialize(new { providerRef, amount = payment.Amount, status = "paid" });
        var signature = gateway.Sign(payload);
        var outcome = await service.HandleWebhookAsync(payment.Provider, payload, signature, ct);
        if (outcome.OverpayRefundId is not null) await TryRefundOverpayAsync(db, refunds, outcome.OverpayRefundId.Value, ct);
        if (outcome.BecameFunded) await TryCreateAndProcessPayoutAsync(db, payouts, outcome.CaseId, ct);

        var c = await db.Cases.AsNoTracking().FirstOrDefaultAsync(x => x.Id == outcome.CaseId, ct);
        var html = $$"""
        <!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Đã thanh toán</title><style>body{font-family:-apple-system,Segoe UI,sans-serif;background:#F7F7F5;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
        .card{background:#fff;border-radius:24px;padding:36px;text-align:center;max-width:380px;box-shadow:0 10px 40px rgba(0,0,0,.08)}
        .ok{font-size:56px}h1{font-size:24px}</style></head><body><div class="card">
        <div class="ok">💚</div><h1>Đã ghi nhận {{outcome.Credited:N0}}đ</h1>
        <p>{{c?.Title}}</p><p style="color:#777">Quay lại app để xem tiến độ. Case đã tăng thêm {{outcome.Credited:N0}}đ.</p>
        </div></body></html>
        """;
        return Results.Content(html, "text/html; charset=utf-8");
    }

    private static async Task<IResult> DevSimulateAsync(Guid contributionId, VilepDbContext db, CurrentUser current,
        ContributionService service, PayoutService payouts, IOptions<VilepOptions> options, IPaymentGateway gateway,
        IOptions<PaymentOptions> pay, CancellationToken ct)
    {
        if (!options.Value.EnableDevPayments) throw ApiException.NotFound();
        if (gateway.Name != "mock") throw ApiException.BadRequest("not_mock", "Chỉ dùng được với cổng giả lập");
        var userId = current.RequireUser();

        var contribution = await db.Contributions.FirstOrDefaultAsync(x => x.Id == contributionId, ct)
                           ?? throw ApiException.NotFound("Không tìm thấy khoản góp");
        if (contribution.ContributorId != userId) throw ApiException.Forbidden("Không phải khoản góp của bạn");

        var payment = await db.PaymentTransactions.FirstOrDefaultAsync(x => x.ContributionId == contributionId && x.Direction == "in", ct)
                      ?? throw ApiException.NotFound("Không tìm thấy giao dịch");

        var payload = JsonSerializer.Serialize(new { providerRef = payment.ProviderRef, amount = payment.Amount, status = "paid" });
        var signature = gateway.Sign(payload);

        var outcome = await service.HandleWebhookAsync(gateway.Name, payload, signature, ct);
        if (outcome.BecameFunded) await TryCreateAndProcessPayoutAsync(db, payouts, outcome.CaseId, ct);

        var c = await db.Cases.AsNoTracking().FirstAsync(x => x.Id == outcome.CaseId, ct);
        return ApiResult.Ok(new { credited = outcome.Credited, duplicate = outcome.Duplicate, caseState = c.State, raised = c.RaisedAmount, target = c.TargetAmount });
    }

    private static string DevSecret(PaymentOptions pay, string providerRef) =>
        Hash.Hmac(pay.WebhookSecret, "devpay:" + providerRef)[..16];
}
