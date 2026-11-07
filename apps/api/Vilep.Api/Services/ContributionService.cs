using System.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Vilep.Api.Data;
using Vilep.Api.Domain;
using Vilep.Api.Infrastructure;

namespace Vilep.Api.Services;

public record CreateContributionRequest(long Amount, long TipAmount, bool Anonymous, string? Message, string? Sticker);

public record ContributionCreated(
    Guid ContributionId,
    long Amount,
    long TipAmount,
    long FeeAmount,
    long Total,
    string CheckoutUrl,
    string QrPayload,
    string Provider,
    string ProviderRef);

public record WebhookOutcome(Guid ContributionId, Guid CaseId, long Credited, bool BecameFunded, Guid? OverpayRefundId, bool Duplicate);

public class ContributionService
{
    private readonly VilepDbContext _db;
    private readonly LedgerService _ledger;
    private readonly NotificationService _notify;
    private readonly CaseWorkflow _workflow;
    private readonly ConfigService _config;
    private readonly IPaymentGateway _gateway;
    private readonly PaymentOptions _paymentOptions;
    private readonly VilepOptions _options;
    private readonly ILogger<ContributionService> _logger;

    public ContributionService(VilepDbContext db, LedgerService ledger, NotificationService notify, CaseWorkflow workflow,
        ConfigService config, IPaymentGateway gateway, IOptions<PaymentOptions> paymentOptions, IOptions<VilepOptions> options,
        ILogger<ContributionService> logger)
    {
        _db = db;
        _ledger = ledger;
        _notify = notify;
        _workflow = workflow;
        _config = config;
        _gateway = gateway;
        _paymentOptions = paymentOptions.Value;
        _options = options.Value;
        _logger = logger;
    }

    public async Task<ContributionCreated> CreateAsync(Guid userId, Guid caseId, CreateContributionRequest req,
        string? idempotencyKey, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(idempotencyKey))
            throw ApiException.BadRequest("missing_idempotency_key", "Thiếu header Idempotency-Key");

        var existing = await _db.Contributions.AsNoTracking()
            .FirstOrDefaultAsync(x => x.IdempotencyKey == idempotencyKey, ct);
        if (existing is not null) return await BuildCreatedAsync(existing.Id, ct);

        var user = await _db.Users.FirstOrDefaultAsync(x => x.Id == userId, ct) ?? throw ApiException.Unauthorized();
        if (user.IsBlocked) throw ApiException.Forbidden("Tài khoản đang bị khoá");
        if (!user.AgeVerified) throw ApiException.Forbidden("Bạn cần xác nhận đủ 18 tuổi trước khi thanh toán");

        var c = await _db.Cases.Include(x => x.Creditor)
            .FirstOrDefaultAsync(x => x.Id == caseId, ct) ?? throw ApiException.NotFound("Không tìm thấy case");
        if (c.DebtorId == userId)
            throw ApiException.Forbidden("Bạn không thể tự đóng góp vào case của mình");
        if (c.State != CaseStates.Funding)
            throw ApiException.Conflict("case_not_funding", "Case chưa mở gây quỹ hoặc đã kết thúc");
        if (c.Deadline is not null && c.Deadline < DateTimeOffset.UtcNow)
            throw ApiException.Conflict("case_expired", "Case đã hết hạn gây quỹ");
        if (req.Amount <= 0)
            throw ApiException.BadRequest("invalid_amount", "Số tiền không hợp lệ");

        var min = await _config.MinContributionAsync(ct);
        if (req.Amount < min)
            throw ApiException.BadRequest("below_minimum", $"Số tiền tối thiểu là {min:N0}đ");
        if (req.TipAmount < 0)
            throw ApiException.BadRequest("invalid_tip", "Tip không hợp lệ");
        if (req.TipAmount > Math.Max(50_000, req.Amount / 2))
            throw ApiException.BadRequest("tip_too_high", "Tip quá lớn so với số tiền góp");

        var remaining = c.PayoutMode == PayoutModes.Creditor
            ? Math.Max(0, c.TargetAmount - c.RaisedAmount)
            : Math.Max(0, await _config.GetLongAsync("fun_mode_b_max", _options.FunModeBMax, ct) - c.RaisedAmount);

        if (remaining <= 0)
            throw ApiException.Conflict("case_full", "Case đã góp đủ, không thể góp thêm");
        if (req.Amount > remaining)
            throw ApiException.BadRequest("exceeds_remaining", $"Chỉ còn thiếu {remaining:N0}đ, bạn góp tối đa {remaining:N0}đ");

        var fee = req.Amount * _paymentOptions.ProcessingFeeBps / 10_000;
        var total = req.Amount + req.TipAmount + fee;

        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        var contribution = new Contribution
        {
            CaseId = c.Id,
            ContributorId = userId,
            Amount = req.Amount,
            TipAmount = req.TipAmount,
            FeeAmount = fee,
            State = ContributionStates.Pending,
            Anonymous = req.Anonymous,
            Message = string.IsNullOrWhiteSpace(req.Message) ? null : req.Message.Trim(),
            Sticker = req.Sticker,
            IdempotencyKey = idempotencyKey
        };
        _db.Contributions.Add(contribution);

        var payment = new PaymentTransaction
        {
            Provider = _gateway.Name,
            ProviderRef = "TMP-" + contribution.Id.ToString("N"),
            Direction = "in",
            Amount = total,
            Status = "pending",
            IdempotencyKey = "pay:" + idempotencyKey,
            ContributionId = contribution.Id
        };
        _db.PaymentTransactions.Add(payment);
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        var session = new CheckoutSession(contribution.Id, c.Id, c.Code, total,
            $"Ví Lép {c.Code}", $"{_options.BaseUrl}/api/v1/dev/pay/return", $"{_options.BaseUrl}/");

        CheckoutResult checkout;
        try
        {
            checkout = await _gateway.CreateCheckoutAsync(session, ct);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Checkout creation failed for contribution {Id}", contribution.Id);
            payment = await _db.PaymentTransactions.FirstAsync(x => x.Id == payment.Id, ct);
            payment.Status = "failed";
            contribution = await _db.Contributions.FirstAsync(x => x.Id == contribution.Id, ct);
            contribution.State = ContributionStates.Failed;
            await _db.SaveChangesAsync(ct);
            throw;
        }

        payment = await _db.PaymentTransactions.FirstAsync(x => x.Id == payment.Id, ct);
        payment.ProviderRef = checkout.ProviderRef;
        payment.CheckoutUrl = checkout.CheckoutUrl;
        payment.QrPayload = checkout.QrPayload;
        await _db.SaveChangesAsync(ct);

        return await BuildCreatedAsync(contribution.Id, ct);
    }

    private async Task<ContributionCreated> BuildCreatedAsync(Guid contributionId, CancellationToken ct)
    {
        var contribution = await _db.Contributions.AsNoTracking().FirstAsync(x => x.Id == contributionId, ct);
        var payment = await _db.PaymentTransactions.AsNoTracking()
            .FirstOrDefaultAsync(x => x.ContributionId == contributionId && x.Direction == "in", ct)
            ?? throw ApiException.NotFound("Không tìm thấy giao dịch thanh toán");
        return new ContributionCreated(contribution.Id, contribution.Amount, contribution.TipAmount, contribution.FeeAmount,
            payment.Amount, payment.CheckoutUrl ?? "", payment.QrPayload ?? "", payment.Provider, payment.ProviderRef);
    }

    public async Task<WebhookOutcome> HandleWebhookAsync(string provider, string rawBody, string? signature, CancellationToken ct)
    {
        if (!string.Equals(provider, _gateway.Name, StringComparison.OrdinalIgnoreCase))
        {
            // A different gateway may be configured at runtime; reject unknown sources.
            throw ApiException.BadRequest("unknown_provider", "Cổng thanh toán không khớp cấu hình");
        }

        var payload = _gateway.ParseWebhook(rawBody, signature)
                      ?? throw ApiException.BadRequest("invalid_signature", "Chữ ký webhook không hợp lệ");

        for (var attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                return await ProcessWebhookAsync(provider, payload, ct);
            }
            catch (DbUpdateConcurrencyException)
            {
                _db.ChangeTracker.Clear();
                await Task.Delay(15 * (attempt + 1), ct);
            }
            catch (DbUpdateException) when (attempt < 4)
            {
                _db.ChangeTracker.Clear();
                await Task.Delay(15 * (attempt + 1), ct);
            }
        }
        throw ApiException.Conflict("webhook_conflict", "Không xử lý được webhook do xung đột dữ liệu");
    }

    private async Task<WebhookOutcome> ProcessWebhookAsync(string provider, WebhookPayload payload, CancellationToken ct)
    {
        await using var tx = await _db.Database.BeginTransactionAsync(ct);

        var payment = await _db.PaymentTransactions
            .FirstOrDefaultAsync(x => x.Provider == provider && x.ProviderRef == payload.ProviderRef, ct)
            ?? throw ApiException.NotFound("Không tìm thấy giao dịch thanh toán");

        var contribution = await _db.Contributions.FirstOrDefaultAsync(x => x.Id == payment.ContributionId, ct)
                           ?? throw ApiException.NotFound("Không tìm thấy khoản đóng góp");
        var c = await _db.Cases.FirstAsync(x => x.Id == contribution.CaseId, ct);

        if (payment.Status == "succeeded")
        {
            await tx.CommitAsync(ct);
            return new WebhookOutcome(contribution.Id, c.Id, 0, false, null, Duplicate: true);
        }

        if (contribution.State != ContributionStates.Pending)
        {
            payment.Status = "succeeded";
            payment.CompletedAt = DateTimeOffset.UtcNow;
            await _db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return new WebhookOutcome(contribution.Id, c.Id, 0, false, null, Duplicate: true);
        }

        if (!payload.Success)
        {
            payment.Status = "failed";
            payment.RawPayload = payload.RawJson;
            contribution.State = ContributionStates.Failed;
            _notify.Push(contribution.ContributorId, "payment_failed", "Thanh toán chưa thành công",
                "Khoản góp chưa được ghi nhận. Bạn có thể thử lại.");
            await _db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return new WebhookOutcome(contribution.Id, c.Id, 0, false, null, Duplicate: false);
        }

        // Invariant: never credit more than the case still needs (mode A) or the branch cap (mode B).
        long capacity;
        if (c.PayoutMode == PayoutModes.Creditor)
        {
            capacity = Math.Max(0, c.TargetAmount - c.RaisedAmount);
        }
        else
        {
            var cap = await _config.GetLongAsync("fun_mode_b_max", _options.FunModeBMax, ct);
            capacity = Math.Max(0, cap - c.RaisedAmount);
        }

        var credited = Math.Min(contribution.Amount, capacity);
        Guid? overpayRefundId = null;

        if (credited <= 0)
        {
            var refund = new Refund
            {
                ContributionId = contribution.Id,
                CaseId = c.Id,
                Amount = contribution.Amount,
                State = RefundStates.Pending,
                Reason = "case_already_full"
            };
            _db.Refunds.Add(refund);
            contribution.State = ContributionStates.Failed;
            payment.Status = "succeeded";
            payment.CompletedAt = DateTimeOffset.UtcNow;
            payment.RawPayload = payload.RawJson;
            overpayRefundId = refund.Id;
            await _db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return new WebhookOutcome(contribution.Id, c.Id, 0, false, overpayRefundId, Duplicate: false);
        }

        var escrowAccount = c.PayoutMode == PayoutModes.Creditor ? LedgerAccounts.CaseEscrow : LedgerAccounts.CaseHold;
        _ledger.Post(c.Id, "contribution", contribution.Id, LedgerAccounts.GatewayClearing, escrowAccount,
            credited, $"contrib:{contribution.Id}:escrow");
        if (contribution.TipAmount > 0)
            _ledger.Post(c.Id, "contribution", contribution.Id, LedgerAccounts.GatewayClearing, LedgerAccounts.PlatformTip,
                contribution.TipAmount, $"contrib:{contribution.Id}:tip");
        if (contribution.FeeAmount > 0)
            _ledger.Post(c.Id, "contribution", contribution.Id, LedgerAccounts.GatewayClearing, LedgerAccounts.ProcessingFee,
                contribution.FeeAmount, $"contrib:{contribution.Id}:fee");

        if (credited < contribution.Amount)
        {
            var diff = contribution.Amount - credited;
            var refund = new Refund
            {
                ContributionId = contribution.Id,
                CaseId = c.Id,
                Amount = diff,
                State = RefundStates.Pending,
                Reason = "overpay_cap"
            };
            _db.Refunds.Add(refund);
            overpayRefundId = refund.Id;
            Audit.Write(_db, null, "system", "contribution.capped", "contribution", contribution.Id,
                before: new { amount = contribution.Amount }, after: new { amount = credited, refund = diff });
        }

        contribution.Amount = credited;
        contribution.PaidAt = DateTimeOffset.UtcNow;
        contribution.State = c.PayoutMode == PayoutModes.Creditor ? ContributionStates.Succeeded : ContributionStates.Held;
        if (c.PayoutMode == PayoutModes.Debtor)
            contribution.AvailableAt = DateTimeOffset.UtcNow.AddDays(await _config.HoldDaysAsync(ct));

        c.RaisedAmount += credited;
        c.Version++;

        payment.Status = "succeeded";
        payment.CompletedAt = DateTimeOffset.UtcNow;
        payment.RawPayload = payload.RawJson;

        var becameFunded = false;
        if (c.PayoutMode == PayoutModes.Creditor && c.RaisedAmount >= c.TargetAmount && c.State == CaseStates.Funding)
        {
            _workflow.Transition(c, CaseStates.Funded, null, "system", "Đã góp đủ mục tiêu");
            becameFunded = true;
        }

        // Money-critical rows first; notifications are a non-critical side effect saved in a second
        // round-trip so a notification problem can never roll back a settled contribution.
        await _db.SaveChangesAsync(ct);

        _notify.Push(c.DebtorId, "contribution_new", "Có người vừa cứu nợ 💚",
            $"{(contribution.Anonymous ? "Một người bạn" : "Ai đó")} vừa góp {credited:N0}đ cho case \"{c.Title}\".");
        if (becameFunded)
        {
            _notify.Push(c.DebtorId, "case_funded", "Ví đã phồng! 🎉",
                $"Case \"{c.Title}\" đã đủ {c.TargetAmount:N0}đ. Ví Lép sẽ chuyển tiền cho chủ nợ.");
        }
        await _db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return new WebhookOutcome(contribution.Id, c.Id, credited, becameFunded, overpayRefundId, Duplicate: false);
    }
}
