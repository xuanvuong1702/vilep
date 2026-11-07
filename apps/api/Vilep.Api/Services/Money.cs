using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Vilep.Api.Data;
using Vilep.Api.Domain;
using Vilep.Api.Infrastructure;

namespace Vilep.Api.Services;

public class PayoutService
{
    private readonly VilepDbContext _db;
    private readonly LedgerService _ledger;
    private readonly NotificationService _notify;
    private readonly CaseWorkflow _workflow;
    private readonly Encryptor _encryptor;
    private readonly IPaymentGateway _gateway;
    private readonly PaymentOptions _paymentOptions;
    private readonly ILogger<PayoutService> _logger;

    public PayoutService(VilepDbContext db, LedgerService ledger, NotificationService notify, CaseWorkflow workflow,
        Encryptor encryptor, IPaymentGateway gateway, IOptions<PaymentOptions> paymentOptions, ILogger<PayoutService> logger)
    {
        _db = db;
        _ledger = ledger;
        _notify = notify;
        _workflow = workflow;
        _encryptor = encryptor;
        _gateway = gateway;
        _paymentOptions = paymentOptions.Value;
        _logger = logger;
    }

    /// <summary>Creates the single payout order for a funded case (idempotent).</summary>
    public async Task<Payout> EnsureOrderAsync(Case c, CancellationToken ct)
    {
        if (c.PayoutMode != PayoutModes.Creditor)
            throw ApiException.BadRequest("wrong_mode", "Chỉ case chế độ A mới payout cho chủ nợ");
        if (c.CreditorId is null)
            throw ApiException.BadRequest("missing_creditor", "Case chưa có chủ nợ xác nhận");

        var existing = await _db.Payouts
            .FirstOrDefaultAsync(p => p.CaseId == c.Id && p.State != PayoutStates.Failed && p.State != PayoutStates.Cancelled, ct);
        if (existing is not null) return existing;

        var payout = new Payout
        {
            CaseId = c.Id,
            CreditorId = c.CreditorId.Value,
            Amount = c.RaisedAmount,
            State = PayoutStates.Pending
        };
        _db.Payouts.Add(payout);

        if (c.State == CaseStates.Funded)
        {
            _workflow.Transition(c, CaseStates.PayoutPending, null, "system", "Case đủ tiền, lập lệnh payout");
            Audit.Write(_db, null, "system", "payout.created", "payout", payout.Id,
                after: new { payout.Amount, caseId = c.Id, provider = _gateway.Name });
        }
        return payout;
    }

    public async Task ExecuteAsync(Payout payout, Case c, Guid? actorId, CancellationToken ct)
    {
        if (payout.State == PayoutStates.Paid) return;

        var creditor = await _db.Creditors.FirstOrDefaultAsync(x => x.Id == payout.CreditorId, ct)
                       ?? throw ApiException.NotFound("Không tìm thấy chủ nợ");
        var account = creditor.BankAccountId is null
            ? null
            : await _db.BankAccounts.FirstOrDefaultAsync(x => x.Id == creditor.BankAccountId, ct);
        if (account is null)
            throw ApiException.BadRequest("missing_bank_account", "Chủ nợ chưa khai tài khoản nhận tiền");

        payout.State = PayoutStates.Processing;
        await _db.SaveChangesAsync(ct);

        var request = new DisbursementRequest(payout.Id, account.BankCode,
            _encryptor.Decrypt(account.AccountNoEnc), account.AccountName, payout.Amount,
            $"Ví Lép trả nợ case {c.Code}");

        DisbursementResult result;
        try
        {
            result = await _gateway.DisburseAsync(request, ct);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Disbursement threw for payout {PayoutId}", payout.Id);
            result = new DisbursementResult(false, null, "provider_error", null);
        }

        if (!result.Success)
        {
            payout.State = PayoutStates.Failed;
            payout.FailureReason = result.FailureReason;
            if (c.State == CaseStates.PayoutPending)
                _workflow.Transition(c, CaseStates.PayoutFailed, actorId, "system", result.FailureReason ?? "Chuyển tiền thất bại");
            _notify.Push(c.DebtorId, "payout_failed", "Chuyển tiền cho chủ nợ chưa thành công",
                $"Case \"{c.Title}\" đang được xử lý lại. Bạn không cần làm gì.");
            Audit.Write(_db, actorId, "system", "payout.failed", "payout", payout.Id, after: new { result.FailureReason });
            await _db.SaveChangesAsync(ct);
            return;
        }

        payout.State = PayoutStates.Paid;
        payout.ProviderRef = result.ProviderRef;
        payout.ReceiptKey = result.ReceiptKey ?? $"payout/{payout.Id:N}";
        payout.PaidAt = DateTimeOffset.UtcNow;
        if (actorId is not null) payout.CheckerId = actorId;

        _ledger.Post(c.Id, "payout", payout.Id, LedgerAccounts.CaseEscrow, LedgerAccounts.CreditorPayoutClearing,
            payout.Amount, $"payout:{payout.Id}:transfer");

        if (c.State == CaseStates.PayoutPending)
            _workflow.Transition(c, CaseStates.Paid, actorId, actorId is null ? "system" : "admin",
                $"Đã chuyển {payout.Amount:N0}đ cho chủ nợ");

        _notify.Push(c.DebtorId, "payout_paid", "Đã trả nợ cho chủ nợ 🎉",
            $"{payout.Amount:N0}đ đã được chuyển cho chủ nợ của case \"{c.Title}\".");
        Audit.Write(_db, actorId, "system", "payout.paid", "payout", payout.Id,
            after: new { payout.ProviderRef, payout.Amount, account = account.AccountNoLast4 });
        await _db.SaveChangesAsync(ct);
    }

    public async Task AutoProcessIfAllowedAsync(Payout payout, Case c, CancellationToken ct)
    {
        if (payout.Amount > _paymentOptions.AutoApprovePayoutLimit) return;
        payout.State = PayoutStates.Approved;
        await _db.SaveChangesAsync(ct);
        await ExecuteAsync(payout, c, null, ct);
    }
}

public class RefundService
{
    private readonly VilepDbContext _db;
    private readonly LedgerService _ledger;
    private readonly NotificationService _notify;
    private readonly IPaymentGateway _gateway;
    private readonly ILogger<RefundService> _logger;

    public RefundService(VilepDbContext db, LedgerService ledger, NotificationService notify,
        IPaymentGateway gateway, ILogger<RefundService> logger)
    {
        _db = db;
        _ledger = ledger;
        _notify = notify;
        _gateway = gateway;
        _logger = logger;
    }

    /// <summary>Refunds one contribution. Funds may sit in escrow (mode A) or hold/available (mode B).</summary>
    public async Task<bool> RefundContributionAsync(Contribution contribution, Case c, string reason,
        string sourceAccount, CancellationToken ct)
    {
        if (contribution.State is ContributionStates.Refunded or ContributionStates.Failed or ContributionStates.Pending)
            return false;

        var existing = await _db.Refunds.FirstOrDefaultAsync(r => r.ContributionId == contribution.Id && r.State != RefundStates.Failed, ct);
        if (existing is not null && existing.State == RefundStates.Done) return false;

        var refund = existing ?? new Refund
        {
            ContributionId = contribution.Id,
            CaseId = c.Id,
            Amount = contribution.Amount,
            State = RefundStates.Pending,
            Reason = reason
        };
        if (existing is null) _db.Refunds.Add(refund);

        var payment = await _db.PaymentTransactions.AsNoTracking()
            .FirstOrDefaultAsync(t => t.ContributionId == contribution.Id && t.Direction == "in", ct);

        RefundResult result;
        try
        {
            result = await _gateway.RefundAsync(new RefundRequest(refund.Id, payment?.ProviderRef ?? "", refund.Amount, reason), ct);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Refund threw for contribution {ContributionId}", contribution.Id);
            result = new RefundResult(false, null, "provider_error");
        }

        if (!result.Success)
        {
            refund.State = RefundStates.Failed;
            Audit.Write(_db, null, "system", "refund.failed", "refund", refund.Id, after: new { result.FailureReason });
            await _db.SaveChangesAsync(ct);
            return false;
        }

        refund.State = RefundStates.Done;
        refund.ProviderRef = result.ProviderRef;
        refund.DoneAt = DateTimeOffset.UtcNow;

        _ledger.Post(c.Id, "refund", refund.Id, sourceAccount, LedgerAccounts.RefundClearing, refund.Amount,
            $"refund:{refund.Id}:transfer");

        contribution.State = ContributionStates.Refunded;
        _notify.Push(contribution.ContributorId, "refund_done", "Đã hoàn tiền",
            $"{refund.Amount:N0}đ cho case \"{c.Title}\" đã được hoàn về tài khoản/ví ban đầu.");
        Audit.Write(_db, null, "system", "refund.done", "refund", refund.Id,
            after: new { refund.Amount, refund.ProviderRef, contributionId = contribution.Id });
        await _db.SaveChangesAsync(ct);
        return true;
    }

    /// <summary>Refunds every settled contribution of a case and moves the case to `refunded`.</summary>
    public async Task<int> RefundCaseAsync(Case c, string reason, Guid? actorId, CancellationToken ct)
    {
        var contributions = await _db.Contributions
            .Where(x => x.CaseId == c.Id && (x.State == ContributionStates.Succeeded || x.State == ContributionStates.Held || x.State == ContributionStates.Available))
            .ToListAsync(ct);

        var source = c.PayoutMode == PayoutModes.Creditor ? LedgerAccounts.CaseEscrow
            : contributions.Any(x => x.State == ContributionStates.Held) ? LedgerAccounts.CaseHold : LedgerAccounts.CaseAvailable;

        var refunded = 0;
        foreach (var contribution in contributions)
        {
            if (await RefundContributionAsync(contribution, c, reason, source, ct)) refunded++;
        }

        if (c.State == CaseStates.Refunding)
        {
            c.State = CaseStates.Refunded;
            c.Version++;
            c.ClosedAt = DateTimeOffset.UtcNow;
            Audit.Write(_db, actorId, actorId is null ? "system" : "admin", "case.refunded", "case", c.Id,
                after: new { refunded, reason });
            _notify.Push(c.DebtorId, "case_refunded", "Đã hoàn tiền cho người góp",
                $"Case \"{c.Title}\" đã hoàn tất hoàn tiền cho {refunded} người góp.");
        }

        await _db.SaveChangesAsync(ct);
        return refunded;
    }
}
