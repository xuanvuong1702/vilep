using Microsoft.EntityFrameworkCore;
using Vilep.Api.Data;
using Vilep.Api.Domain;
using Vilep.Api.Services;

namespace Vilep.Api.Jobs;

public record JobReport(int ExpiredCases, int CancelledInvites, int PayoutsRetried, int PayoutsCreated, int InvariantProblems, DateTimeOffset RanAt);

/// <summary>
/// Background reconciliation. Mirrors the spec's JOB-01..JOB-08 using a single scheduled runner
/// instead of Hangfire so the MVP needs no extra hosted service.
/// </summary>
public class JobsRunner
{
    private readonly VilepDbContext _db;
    private readonly CaseWorkflow _workflow;
    private readonly RefundService _refunds;
    private readonly PayoutService _payouts;
    private readonly LedgerService _ledger;
    private readonly NotificationService _notify;
    private readonly ILogger<JobsRunner> _logger;

    public JobsRunner(VilepDbContext db, CaseWorkflow workflow, RefundService refunds, PayoutService payouts,
        LedgerService ledger, NotificationService notify, ILogger<JobsRunner> logger)
    {
        _db = db;
        _workflow = workflow;
        _refunds = refunds;
        _payouts = payouts;
        _ledger = ledger;
        _notify = notify;
        _logger = logger;
    }

    public async Task<JobReport> RunAllAsync(CancellationToken ct)
    {
        var expired = await ExpireFundingCasesAsync(ct);
        var cancelled = await CancelStaleInvitesAsync(ct);
        var created = await EnsureFundedPayoutsAsync(ct);
        var retried = await RetryFailedPayoutsAsync(ct);
        var problems = await CheckInvariantsAsync(ct);
        return new JobReport(expired, cancelled, retried, created, problems, DateTimeOffset.UtcNow);
    }

    private async Task<int> ExpireFundingCasesAsync(CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        var due = await _db.Cases
            .Where(c => c.State == CaseStates.Funding && c.Deadline != null && c.Deadline < now)
            .ToListAsync(ct);

        var count = 0;
        foreach (var c in due)
        {
            try
            {
                if (c.PayoutMode == PayoutModes.Debtor)
                {
                    _workflow.Transition(c, CaseStates.Ended, null, "system", "Hết hạn gây quỹ (chế độ B)");
                    await _db.SaveChangesAsync(ct);
                    continue;
                }

                _workflow.Transition(c, CaseStates.Expired, null, "system", "Hết hạn gây quỹ, hoàn tiền");
                _notify.Push(c.DebtorId, "case_expired", "Case đã hết hạn",
                    $"Case \"{c.Title}\" chưa đủ mục tiêu. Mọi khoản góp sẽ được hoàn lại đầy đủ.");
                await _db.SaveChangesAsync(ct);

                _workflow.Transition(c, CaseStates.Refunding, null, "system", "Bắt đầu hoàn tiền");
                await _db.SaveChangesAsync(ct);
                await _refunds.RefundCaseAsync(c, "case_expired", null, ct);
                count++;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Expire job failed for case {CaseId}", c.Id);
                _db.ChangeTracker.Clear();
            }
        }
        return count;
    }

    private async Task<int> CancelStaleInvitesAsync(CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        var stale = await _db.Cases.Include(c => c.Creditor)
            .Where(c => c.State == CaseStates.PendingCreditor && c.Creditor != null
                        && c.Creditor.ConfirmedAt == null && c.Creditor.InviteExpiresAt < now)
            .ToListAsync(ct);

        var count = 0;
        foreach (var c in stale)
        {
            try
            {
                _workflow.Transition(c, CaseStates.Cancelled, null, "system", "Chủ nợ không phản hồi trong thời hạn");
                _notify.Push(c.DebtorId, "case_cancelled", "Case tự huỷ",
                    $"Chủ nợ không phản hồi trong thời hạn nên case \"{c.Title}\" đã tự huỷ. Chưa có tiền nào bị giữ.");
                await _db.SaveChangesAsync(ct);
                count++;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Invite timeout job failed for case {CaseId}", c.Id);
                _db.ChangeTracker.Clear();
            }
        }
        return count;
    }

    private async Task<int> EnsureFundedPayoutsAsync(CancellationToken ct)
    {
        var funded = await _db.Cases.Where(c => c.State == CaseStates.Funded).ToListAsync(ct);
        var count = 0;
        foreach (var c in funded)
        {
            try
            {
                var payout = await _payouts.EnsureOrderAsync(c, ct);
                await _db.SaveChangesAsync(ct);
                await _payouts.AutoProcessIfAllowedAsync(payout, c, ct);
                count++;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Payout creation failed for case {CaseId}", c.Id);
                _db.ChangeTracker.Clear();
            }
        }
        return count;
    }

    private async Task<int> RetryFailedPayoutsAsync(CancellationToken ct)
    {
        var failed = await _db.Payouts.Where(p => p.State == PayoutStates.Failed)
            .OrderByDescending(p => p.CreatedAt).Take(10).ToListAsync(ct);
        var count = 0;
        foreach (var payout in failed)
        {
            try
            {
                var c = await _db.Cases.FirstOrDefaultAsync(x => x.Id == payout.CaseId, ct);
                if (c is null) continue;
                if (c.State == CaseStates.PayoutFailed) _workflow.Transition(c, CaseStates.PayoutPending, null, "system", "Thử lại payout");
                await _db.SaveChangesAsync(ct);
                await _payouts.ExecuteAsync(payout, c, null, ct);
                count++;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Payout retry failed for {PayoutId}", payout.Id);
                _db.ChangeTracker.Clear();
            }
        }
        return count;
    }

    private async Task<int> CheckInvariantsAsync(CancellationToken ct)
    {
        var cases = await _db.Cases.AsNoTracking()
            .Where(c => c.State != CaseStates.Draft && c.State != CaseStates.Cancelled)
            .ToListAsync(ct);
        var problems = 0;
        foreach (var c in cases)
        {
            var escrow = await _ledger.CaseEscrowAsync(c.Id, ct);
            var hold = await _ledger.BalanceAsync(LedgerAccounts.CaseHold, c.Id, ct);
            var available = await _ledger.BalanceAsync(LedgerAccounts.CaseAvailable, c.Id, ct);
            var credited = await _db.Contributions.AsNoTracking().Where(x => x.CaseId == c.Id
                    && x.State != ContributionStates.Pending && x.State != ContributionStates.Failed)
                .SumAsync(x => (long?)x.Amount, ct) ?? 0;
            var paid = await _db.Payouts.AsNoTracking().Where(p => p.CaseId == c.Id && p.State == PayoutStates.Paid)
                .SumAsync(p => (long?)p.Amount, ct) ?? 0;
            var refunded = await _db.Refunds.AsNoTracking().Where(r => r.CaseId == c.Id && r.State == RefundStates.Done)
                .SumAsync(r => (long?)r.Amount, ct) ?? 0;

            var expected = credited - paid - refunded;
            var actual = escrow + hold + available;
            if (actual != expected)
            {
                problems++;
                _logger.LogError("Invariant mismatch case {Code}: actual={Actual} expected={Expected} credited={Credited} paid={Paid} refunded={Refunded}",
                    c.Code, actual, expected, credited, paid, refunded);
            }
        }
        return problems;
    }
}

public class JobsHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<JobsHostedService> _logger;
    private readonly TimeSpan _interval;

    public JobsHostedService(IServiceScopeFactory scopeFactory, IConfiguration config, ILogger<JobsHostedService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
        var seconds = config.GetValue("Jobs:IntervalSeconds", 60);
        _interval = TimeSpan.FromSeconds(Math.Max(10, seconds));
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var runner = scope.ServiceProvider.GetRequiredService<JobsRunner>();
                var report = await runner.RunAllAsync(stoppingToken);
                if (report.ExpiredCases + report.CancelledInvites + report.PayoutsRetried + report.PayoutsCreated + report.InvariantProblems > 0)
                    _logger.LogInformation("Jobs: {@Report}", report);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Background job run failed");
            }

            try { await Task.Delay(_interval, stoppingToken); }
            catch (TaskCanceledException) { break; }
        }
    }
}
