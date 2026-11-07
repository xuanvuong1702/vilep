using Microsoft.EntityFrameworkCore;
using Vilep.Api.Data;
using Vilep.Api.Domain;
using Vilep.Api.Features.Cases;
using Vilep.Api.Infrastructure;
using Vilep.Api.Jobs;
using Vilep.Api.Services;

namespace Vilep.Api.Features.Admin;

public record SuspendRequest(string Reason);
public record RefundCaseRequest(string Reason);
public record ResolveReportRequest(string Resolution, bool FreezeCase);
public record RejectPayoutRequest(string Reason);
public record MarkPaidRequest(string ProviderRef, string? ReceiptKey);
public record BlacklistRequest(string Type, string Value, string Reason);
public record ConfigUpdateRequest(Dictionary<string, string> Values);

public static class AdminEndpoints
{
    public static void MapAdminEndpoints(this IEndpointRouteBuilder app)
    {
        var admin = app.MapGroup("/api/v1/admin").RequireAuthorization("admin");

        admin.MapGet("/stats", StatsAsync);
        admin.MapGet("/cases", CasesAsync);
        admin.MapPost("/cases/{id:guid}/suspend", SuspendAsync);
        admin.MapPost("/cases/{id:guid}/resume", ResumeAsync);
        admin.MapPost("/cases/{id:guid}/refund", RefundAsync);
        admin.MapGet("/cases/{id:guid}/ledger", CaseLedgerAsync);
        admin.MapGet("/cases/{id:guid}/audit", CaseAuditAsync);

        admin.MapGet("/reports", ReportsAsync);
        admin.MapPost("/reports/{id:guid}/resolve", ResolveReportAsync);

        admin.MapGet("/payouts", PayoutsAsync);
        admin.MapPost("/payouts/{id:guid}/approve", ApprovePayoutAsync);
        admin.MapPost("/payouts/{id:guid}/reject", RejectPayoutAsync);
        admin.MapPost("/payouts/{id:guid}/mark-paid", MarkPaidAsync);

        admin.MapGet("/refunds", RefundsAsync);
        admin.MapGet("/invariants", InvariantsAsync);
        admin.MapGet("/config", ConfigAsync);
        admin.MapPut("/config", UpdateConfigAsync);
        admin.MapPost("/jobs/run", RunJobsAsync);
        admin.MapGet("/users", UsersAsync);
        admin.MapPost("/users/{id:guid}/block", BlockUserAsync);
        admin.MapPost("/users/{id:guid}/unblock", UnblockUserAsync);
        admin.MapPost("/blacklist", AddBlacklistAsync);
        admin.MapGet("/audit", AuditAsync);
    }

    private static async Task<IResult> StatsAsync(VilepDbContext db, LedgerService ledger, CancellationToken ct)
    {
        var byState = await db.Cases.GroupBy(c => new { c.State, c.PayoutMode })
            .Select(g => new { g.Key.State, g.Key.PayoutMode, Count = g.Count(), Raised = g.Sum(x => x.RaisedAmount) })
            .ToListAsync(ct);

        var escrow = await ledger.BalanceAsync(LedgerAccounts.CaseEscrow, null, ct);
        var tip = await ledger.BalanceAsync(LedgerAccounts.PlatformTip, null, ct);
        var fee = await ledger.BalanceAsync(LedgerAccounts.ProcessingFee, null, ct);
        var gateway = await ledger.BalanceAsync(LedgerAccounts.GatewayClearing, null, ct);

        var pendingPayouts = await db.Payouts.CountAsync(p => p.State == PayoutStates.Pending || p.State == PayoutStates.Approved, ct);
        var openReports = await db.Reports.CountAsync(r => r.State == "open", ct);
        var users = await db.Users.CountAsync(u => u.DeletedAt == null, ct);
        var contributions = await db.Contributions.CountAsync(x => x.State != ContributionStates.Pending && x.State != ContributionStates.Failed, ct);
        var refunded = await db.Refunds.Where(r => r.State == RefundStates.Done).SumAsync(r => (long?)r.Amount, ct) ?? 0;

        return ApiResult.Ok(new
        {
            byState,
            escrowBalance = escrow,
            tipBalance = tip,
            feeBalance = fee,
            gatewayClearing = gateway,
            pendingPayouts,
            openReports,
            users,
            contributions,
            refunded,
            successRate = await SuccessRateAsync(db, ct)
        });
    }

    private static async Task<double> SuccessRateAsync(VilepDbContext db, CancellationToken ct)
    {
        var finished = await db.Cases.CountAsync(c => c.State == CaseStates.Closed || c.State == CaseStates.Refunded || c.State == CaseStates.Cancelled, ct);
        var closed = await db.Cases.CountAsync(c => c.State == CaseStates.Closed, ct);
        return finished == 0 ? 0 : Math.Round(closed * 100.0 / finished, 1);
    }

    private static async Task<IResult> CasesAsync(VilepDbContext db, string? state, string? mode, string? q, int? limit, CancellationToken ct)
    {
        var query = db.Cases.AsNoTracking().Include(c => c.Debtor).Include(c => c.Creditor).AsQueryable();
        if (!string.IsNullOrWhiteSpace(state) && state != "all") query = query.Where(c => c.State == state);
        if (!string.IsNullOrWhiteSpace(mode) && mode != "all") query = query.Where(c => c.PayoutMode == mode);
        if (!string.IsNullOrWhiteSpace(q)) query = query.Where(c => EF.Functions.Like(c.Title, $"%{q}%") || EF.Functions.Like(c.Code, $"%{q}%"));

        var rows = await query.OrderByDescending(c => c.CreatedAt).Take(Math.Clamp(limit ?? 50, 1, 200)).ToListAsync(ct);
        return ApiResult.Ok(new
        {
            items = rows.Select(c => new
            {
                c.Id, c.Code, c.Title, c.State, c.PayoutMode, c.RaisedAmount, c.TargetAmount, c.DebtAmount,
                c.CreatedAt, c.Deadline,
                debtor = c.Debtor?.Nickname,
                creditor = c.Creditor?.Name,
                creditorConfirmed = c.Creditor?.ConfirmedAt,
                percent = CaseMapper.PercentOf(c)
            })
        });
    }

    private static async Task<IResult> SuspendAsync(Guid id, SuspendRequest req, VilepDbContext db, CurrentUser current,
        CaseWorkflow workflow, NotificationService notify, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        var c = await db.Cases.FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy case");
        if (string.IsNullOrWhiteSpace(req.Reason)) throw ApiException.BadRequest("reason_required", "Cần lý do khoá case");

        var target = c.State == CaseStates.Funding ? CaseStates.Suspended : throw ApiException.Conflict("invalid_state", "Chỉ khoá được case đang gây quỹ");
        workflow.Transition(c, target, adminId, "admin", req.Reason, "case.suspended");
        notify.Push(c.DebtorId, "case_suspended", "Case đang bị tạm khoá",
            $"Case \"{c.Title}\" bị tạm khoá để kiểm tra: {req.Reason}");
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = c.Id, state = c.State });
    }

    private static async Task<IResult> ResumeAsync(Guid id, VilepDbContext db, CurrentUser current,
        CaseWorkflow workflow, NotificationService notify, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        var c = await db.Cases.FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy case");
        workflow.Transition(c, CaseStates.Funding, adminId, "admin", "Mở khoá case", "case.resumed");
        notify.Push(c.DebtorId, "case_resumed", "Case đã mở khoá", $"Case \"{c.Title}\" tiếp tục nhận đóng góp.");
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = c.Id, state = c.State });
    }

    private static async Task<IResult> RefundAsync(Guid id, RefundCaseRequest req, VilepDbContext db, CurrentUser current,
        CaseWorkflow workflow, RefundService refunds, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        var c = await db.Cases.FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy case");
        if (c.State != CaseStates.Refunding)
        {
            workflow.Transition(c, CaseStates.Refunding, adminId, "admin", req.Reason ?? "Admin hoàn tiền", "case.refunding");
            await db.SaveChangesAsync(ct);
        }
        var count = await refunds.RefundCaseAsync(c, req.Reason ?? "admin_refund", adminId, ct);
        return ApiResult.Ok(new { id = c.Id, state = c.State, refundedCount = count });
    }

    private static async Task<IResult> CaseLedgerAsync(Guid id, VilepDbContext db, LedgerService ledger, CancellationToken ct)
    {
        var entries = await ledger.ForCaseAsync(id, ct);
        var escrow = await ledger.CaseEscrowAsync(id, ct);
        return ApiResult.Ok(new
        {
            escrowBalance = escrow,
            entries = entries.Select(e => new { e.Id, e.RefType, e.RefId, e.DebitAccount, e.CreditAccount, e.Amount, e.CreatedAt, e.IdempotencyKey })
        });
    }

    private static async Task<IResult> CaseAuditAsync(Guid id, VilepDbContext db, CancellationToken ct)
    {
        var rows = await db.AuditLogs.AsNoTracking()
            .Where(a => a.EntityType == "case" && a.EntityId == id)
            .OrderByDescending(a => a.At).Take(200).ToListAsync(ct);
        return ApiResult.Ok(new { items = rows.Select(a => new { a.Id, a.ActorId, a.ActorRole, a.Action, a.BeforeJson, a.AfterJson, a.Reason, a.At }) });
    }

    private static async Task<IResult> ReportsAsync(VilepDbContext db, string? state, CancellationToken ct)
    {
        var query = db.Reports.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(state) && state != "all") query = query.Where(r => r.State == state);
        var rows = await query.OrderByDescending(r => r.CreatedAt).Take(100).ToListAsync(ct);
        var caseIds = rows.Where(r => r.TargetType == "case").Select(r => r.TargetId).ToList();
        var cases = await db.Cases.Where(c => caseIds.Contains(c.Id)).ToDictionaryAsync(c => c.Id, c => c.Title, ct);
        return ApiResult.Ok(new
        {
            items = rows.Select(r => new
            {
                r.Id, r.TargetType, r.TargetId, r.Reason, r.Details, r.State, r.Resolution, r.CreatedAt, r.ResolvedAt,
                caseTitle = cases.GetValueOrDefault(r.TargetId)
            })
        });
    }

    private static async Task<IResult> ResolveReportAsync(Guid id, ResolveReportRequest req, VilepDbContext db, CurrentUser current,
        CaseWorkflow workflow, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        var report = await db.Reports.FirstOrDefaultAsync(r => r.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy báo cáo");
        if (report.State != "open") throw ApiException.Conflict("already_resolved", "Báo cáo đã xử lý");

        report.State = "resolved";
        report.Resolution = req.Resolution;
        report.ResolvedBy = adminId;
        report.ResolvedAt = DateTimeOffset.UtcNow;

        if (req.FreezeCase && report.TargetType == "case")
        {
            var c = await db.Cases.FirstOrDefaultAsync(x => x.Id == report.TargetId, ct);
            if (c is not null && c.State == CaseStates.Funding)
                workflow.Transition(c, CaseStates.Suspended, adminId, "admin", "Báo cáo vi phạm: " + req.Resolution, "case.frozen");
        }

        Audit.Write(db, adminId, "admin", "report.resolved", "report", report.Id, after: new { req.Resolution, req.FreezeCase });
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = report.Id, state = report.State });
    }

    private static async Task<IResult> PayoutsAsync(VilepDbContext db, string? state, CancellationToken ct)
    {
        var query = db.Payouts.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(state) && state != "all") query = query.Where(p => p.State == state);
        var rows = await query.OrderByDescending(p => p.CreatedAt).Take(100).ToListAsync(ct);
        var caseIds = rows.Select(p => p.CaseId).ToList();
        var cases = await db.Cases.Where(c => caseIds.Contains(c.Id)).ToDictionaryAsync(c => c.Id, c => new { c.Code, c.Title }, ct);
        return ApiResult.Ok(new
        {
            items = rows.Select(p => new
            {
                p.Id, p.CaseId, p.Amount, p.State, p.ProviderRef, p.CreatedAt, p.PaidAt, p.CreditorConfirmedAt,
                p.FailureReason,
                caseCode = cases.GetValueOrDefault(p.CaseId)?.Code,
                caseTitle = cases.GetValueOrDefault(p.CaseId)?.Title
            })
        });
    }

    private static async Task<IResult> ApprovePayoutAsync(Guid id, VilepDbContext db, CurrentUser current, PayoutService payouts, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        var payout = await db.Payouts.FirstOrDefaultAsync(p => p.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy payout");
        if (payout.State != PayoutStates.Pending) throw ApiException.Conflict("invalid_state", "Payout không ở trạng thái chờ duyệt");
        var c = await db.Cases.FirstAsync(x => x.Id == payout.CaseId, ct);

        payout.State = PayoutStates.Approved;
        payout.CheckerId = adminId;
        await db.SaveChangesAsync(ct);
        await payouts.ExecuteAsync(payout, c, adminId, ct);
        return ApiResult.Ok(new { id = payout.Id, state = payout.State, caseState = c.State });
    }

    private static async Task<IResult> RejectPayoutAsync(Guid id, RejectPayoutRequest req, VilepDbContext db, CurrentUser current,
        PayoutService payouts, RefundService refunds, CaseWorkflow workflow, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        var payout = await db.Payouts.FirstOrDefaultAsync(p => p.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy payout");
        if (payout.State is PayoutStates.Paid) throw ApiException.Conflict("already_paid", "Payout đã chuyển");

        payout.State = PayoutStates.Cancelled;
        payout.FailureReason = req.Reason;
        Audit.Write(db, adminId, "admin", "payout.rejected", "payout", payout.Id, after: new { req.Reason });
        var c = await db.Cases.FirstAsync(x => x.Id == payout.CaseId, ct);
        if (c.State == CaseStates.PayoutPending)
        {
            workflow.Transition(c, CaseStates.Refunding, adminId, "admin", "Payout bị từ chối: " + req.Reason);
            await db.SaveChangesAsync(ct);
            await refunds.RefundCaseAsync(c, "payout_rejected", adminId, ct);
        }
        else await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = payout.Id, state = payout.State, caseState = c.State });
    }

    private static async Task<IResult> MarkPaidAsync(Guid id, MarkPaidRequest req, VilepDbContext db, CurrentUser current,
        LedgerService ledger, CaseWorkflow workflow, NotificationService notify, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        var payout = await db.Payouts.FirstOrDefaultAsync(p => p.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy payout");
        if (payout.State == PayoutStates.Paid) throw ApiException.Conflict("already_paid", "Payout đã chuyển");
        var c = await db.Cases.FirstAsync(x => x.Id == payout.CaseId, ct);

        payout.State = PayoutStates.Paid;
        payout.ProviderRef = req.ProviderRef;
        payout.ReceiptKey = req.ReceiptKey ?? $"manual/{payout.Id:N}";
        payout.PaidAt = DateTimeOffset.UtcNow;
        payout.CheckerId = adminId;

        ledger.Post(c.Id, "payout", payout.Id, LedgerAccounts.CaseEscrow, LedgerAccounts.CreditorPayoutClearing,
            payout.Amount, $"payout:{payout.Id}:transfer");
        if (c.State == CaseStates.PayoutPending)
            workflow.Transition(c, CaseStates.Paid, adminId, "admin", "Nhập chứng từ chuyển tiền thủ công");
        notify.Push(c.DebtorId, "payout_paid", "Đã trả nợ cho chủ nợ 🎉", $"Chứng từ: {req.ProviderRef}");
        Audit.Write(db, adminId, "admin", "payout.marked_paid", "payout", payout.Id, after: new { req.ProviderRef, req.ReceiptKey });
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = payout.Id, state = payout.State, caseState = c.State });
    }

    private static async Task<IResult> RefundsAsync(VilepDbContext db, string? state, CancellationToken ct)
    {
        var query = db.Refunds.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(state) && state != "all") query = query.Where(r => r.State == state);
        var rows = await query.OrderByDescending(r => r.CreatedAt).Take(100).ToListAsync(ct);
        return ApiResult.Ok(new { items = rows.Select(r => new { r.Id, r.CaseId, r.ContributionId, r.Amount, r.State, r.Reason, r.ProviderRef, r.CreatedAt, r.DoneAt }) });
    }

    private static async Task<IResult> InvariantsAsync(VilepDbContext db, LedgerService ledger, CancellationToken ct)
    {
        var problems = new List<object>();
        var cases = await db.Cases.Where(c => c.State != CaseStates.Draft && c.State != CaseStates.Cancelled).ToListAsync(ct);
        foreach (var c in cases)
        {
            var escrow = await ledger.CaseEscrowAsync(c.Id, ct);
            var hold = await ledger.BalanceAsync(LedgerAccounts.CaseHold, c.Id, ct);
            var available = await ledger.BalanceAsync(LedgerAccounts.CaseAvailable, c.Id, ct);
            var credited = await db.Contributions.Where(x => x.CaseId == c.Id
                    && x.State != ContributionStates.Pending && x.State != ContributionStates.Failed)
                .SumAsync(x => (long?)x.Amount, ct) ?? 0;
            var paidOut = await db.Payouts.Where(p => p.CaseId == c.Id && p.State == PayoutStates.Paid)
                .SumAsync(p => (long?)p.Amount, ct) ?? 0;
            var refunded = await db.Refunds.Where(r => r.CaseId == c.Id && r.State == RefundStates.Done)
                .SumAsync(r => (long?)r.Amount, ct) ?? 0;

            var expected = credited - paidOut - refunded;
            var actual = escrow + hold + available;

            if (actual != expected)
                problems.Add(new { caseId = c.Id, code = c.Code, escrow, hold, available, expected, credited, paidOut, refunded, mode = c.PayoutMode });

            if (c.PayoutMode == PayoutModes.Creditor && c.RaisedAmount > c.TargetAmount)
                problems.Add(new { caseId = c.Id, code = c.Code, problem = "raised_above_target", c.RaisedAmount, c.TargetAmount });
        }

        return ApiResult.Ok(new { ok = problems.Count == 0, checkedCases = cases.Count, problems });
    }

    private static async Task<IResult> ConfigAsync(ConfigService config, CancellationToken ct) =>
        ApiResult.Ok(await config.AllAsync(ct));

    private static async Task<IResult> UpdateConfigAsync(ConfigUpdateRequest req, ConfigService config, CurrentUser current, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        foreach (var (key, value) in req.Values)
            await config.SetAsync(key, value, adminId, ct);
        return ApiResult.Ok(await config.AllAsync(ct));
    }

    private static async Task<IResult> RunJobsAsync(IServiceScopeFactory scopeFactory, CancellationToken ct)
    {
        using var scope = scopeFactory.CreateScope();
        var jobs = scope.ServiceProvider.GetRequiredService<JobsRunner>();
        var report = await jobs.RunAllAsync(ct);
        return ApiResult.Ok(report);
    }

    private static async Task<IResult> UsersAsync(VilepDbContext db, string? q, CancellationToken ct)
    {
        var query = db.Users.AsNoTracking().Where(u => u.DeletedAt == null);
        if (!string.IsNullOrWhiteSpace(q)) query = query.Where(u => EF.Functions.Like(u.Phone, $"%{q}%") || EF.Functions.Like(u.Nickname, $"%{q}%"));
        var rows = await query.OrderByDescending(u => u.CreatedAt).Take(100).ToListAsync(ct);
        return ApiResult.Ok(new
        {
            items = rows.Select(u => new { u.Id, u.Phone, u.Nickname, u.KycTier, u.IsBlocked, u.TrustScore, u.AgeVerified, u.Role, u.CreatedAt })
        });
    }

    private static async Task<IResult> BlockUserAsync(Guid id, VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy người dùng");
        user.IsBlocked = true;
        var tokens = await db.RefreshTokens.Where(t => t.UserId == id && t.RevokedAt == null).ToListAsync(ct);
        foreach (var token in tokens) token.RevokedAt = DateTimeOffset.UtcNow;
        Audit.Write(db, adminId, "admin", "user.blocked", "user", user.Id);
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = user.Id, isBlocked = true });
    }

    private static async Task<IResult> UnblockUserAsync(Guid id, VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy người dùng");
        user.IsBlocked = false;
        Audit.Write(db, adminId, "admin", "user.unblocked", "user", user.Id);
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = user.Id, isBlocked = false });
    }

    private static async Task<IResult> AddBlacklistAsync(BlacklistRequest req, VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var adminId = current.RequireAdmin();
        var entry = new Blacklist { Type = req.Type, ValueHash = Hash.Sha256(req.Value.Trim()), Reason = req.Reason };
        db.Blacklists.Add(entry);
        Audit.Write(db, adminId, "admin", "blacklist.added", "blacklist", entry.Id, after: new { req.Type });
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { entry.Id });
    }

    private static async Task<IResult> AuditAsync(VilepDbContext db, string? entityType, Guid? entityId, int? limit, CancellationToken ct)
    {
        var query = db.AuditLogs.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(entityType)) query = query.Where(a => a.EntityType == entityType);
        if (entityId is not null) query = query.Where(a => a.EntityId == entityId);
        var rows = await query.OrderByDescending(a => a.At).Take(Math.Clamp(limit ?? 100, 1, 500)).ToListAsync(ct);
        return ApiResult.Ok(new { items = rows.Select(a => new { a.Id, a.ActorId, a.ActorRole, a.Action, a.EntityType, a.EntityId, a.Reason, a.At }) });
    }
}
