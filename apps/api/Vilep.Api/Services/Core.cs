using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Vilep.Api.Infrastructure;
using Vilep.Api.Data;
using Vilep.Api.Domain;

namespace Vilep.Api.Services;

public static class Audit
{
    public static void Write(VilepDbContext db, Guid? actorId, string actorRole, string action, string entityType, Guid entityId,
        object? before = null, object? after = null, string? reason = null)
    {
        db.AuditLogs.Add(new AuditLog
        {
            ActorId = actorId,
            ActorRole = actorRole,
            Action = action,
            EntityType = entityType,
            EntityId = entityId,
            BeforeJson = before is null ? null : JsonSerializer.Serialize(before),
            AfterJson = after is null ? null : JsonSerializer.Serialize(after),
            Reason = reason
        });
    }
}

public class LedgerService
{
    private readonly VilepDbContext _db;

    public LedgerService(VilepDbContext db) => _db = db;

    public void Post(Guid? caseId, string refType, Guid refId, string debitAccount, string creditAccount,
        long amount, string idempotencyKey)
    {
        if (amount <= 0) throw new InvalidOperationException("Ledger amount must be positive");
        if (string.IsNullOrWhiteSpace(idempotencyKey)) throw new InvalidOperationException("Ledger entry requires idempotency key");
        if (debitAccount == creditAccount) throw new InvalidOperationException("Debit and credit accounts must differ");

        var exists = _db.LedgerEntries.Local.Any(e => e.IdempotencyKey == idempotencyKey)
                     || _db.LedgerEntries.AsNoTracking().Any(e => e.IdempotencyKey == idempotencyKey);
        if (exists) return;

        _db.LedgerEntries.Add(new LedgerEntry
        {
            CaseId = caseId,
            RefType = refType,
            RefId = refId,
            DebitAccount = debitAccount,
            CreditAccount = creditAccount,
            Amount = amount,
            IdempotencyKey = idempotencyKey
        });
    }

    public async Task<long> BalanceAsync(string account, Guid? caseId, CancellationToken ct)
    {
        var credits = await _db.LedgerEntries
            .Where(e => e.CreditAccount == account && (caseId == null || e.CaseId == caseId))
            .SumAsync(e => (long?)e.Amount, ct) ?? 0;
        var debits = await _db.LedgerEntries
            .Where(e => e.DebitAccount == account && (caseId == null || e.CaseId == caseId))
            .SumAsync(e => (long?)e.Amount, ct) ?? 0;
        return credits - debits;
    }

    public Task<long> CaseEscrowAsync(Guid caseId, CancellationToken ct) => BalanceAsync(LedgerAccounts.CaseEscrow, caseId, ct);

    public async Task<List<LedgerEntry>> ForCaseAsync(Guid caseId, CancellationToken ct) =>
        await _db.LedgerEntries.AsNoTracking().Where(e => e.CaseId == caseId).OrderBy(e => e.CreatedAt).ToListAsync(ct);
}

public class NotificationService
{
    private readonly VilepDbContext _db;

    public NotificationService(VilepDbContext db) => _db = db;

    public void Push(Guid userId, string type, string title, string body, object? payload = null)
    {
        _db.Notifications.Add(new Notification
        {
            UserId = userId,
            Type = type,
            Title = title,
            Body = body,
            PayloadJson = payload is null ? null : JsonSerializer.Serialize(payload)
        });
    }
}

/// <summary>
/// Single domain entry point for case state changes. Never mutate <see cref="Case.State"/> directly.
/// </summary>
public class CaseWorkflow
{
    private readonly VilepDbContext _db;

    public CaseWorkflow(VilepDbContext db) => _db = db;

    public void Transition(Case c, string to, Guid? actorId, string actorRole, string? reason, string action = "case.transition")
    {
        if (!CaseStateMachine.CanTransition(c.PayoutMode, c.State, to))
            throw ApiException.Conflict("invalid_transition",
                $"Không thể chuyển case từ '{c.State}' sang '{to}' ở chế độ {c.PayoutMode}");

        var before = c.State;
        c.State = to;
        c.Version++;
        if (to == CaseStates.Closed) c.ClosedAt = DateTimeOffset.UtcNow;

        Audit.Write(_db, actorId, actorRole, action, "case", c.Id,
            new { state = before }, new { state = to }, reason);
    }
}

public class ConfigService
{
    private readonly VilepDbContext _db;
    private readonly VilepOptions _defaults;

    public ConfigService(VilepDbContext db, IOptions<VilepOptions> defaults)
    {
        _db = db;
        _defaults = defaults.Value;
    }

    public async Task<string?> GetRawAsync(string key, CancellationToken ct = default)
    {
        var row = await _db.AppConfigs.AsNoTracking().FirstOrDefaultAsync(x => x.Key == key, ct);
        return row?.Value;
    }

    public async Task<long> GetLongAsync(string key, long fallback, CancellationToken ct = default)
    {
        var raw = await GetRawAsync(key, ct);
        return long.TryParse(raw, out var value) ? value : fallback;
    }

    public async Task<int> GetIntAsync(string key, int fallback, CancellationToken ct = default)
    {
        var raw = await GetRawAsync(key, ct);
        return int.TryParse(raw, out var value) ? value : fallback;
    }

    public async Task SetAsync(string key, string value, Guid? actorId, CancellationToken ct = default)
    {
        var row = await _db.AppConfigs.FirstOrDefaultAsync(x => x.Key == key, ct);
        if (row is null)
        {
            _db.AppConfigs.Add(new AppConfig { Key = key, Value = value });
        }
        else
        {
            row.Value = value;
            row.UpdatedAt = DateTimeOffset.UtcNow;
        }
        Audit.Write(_db, actorId, "admin", "config.set", "app_config", Guid.Empty, new { key, value });
        await _db.SaveChangesAsync(ct);
    }

    public async Task<Dictionary<string, string>> AllAsync(CancellationToken ct = default)
    {
        var stored = await _db.AppConfigs.AsNoTracking().ToDictionaryAsync(x => x.Key, x => x.Value, ct);
        return new Dictionary<string, string>
        {
            ["min_contribution"] = stored.GetValueOrDefault("min_contribution", _defaults.MinContribution.ToString()),
            ["fun_mode_a_min"] = stored.GetValueOrDefault("fun_mode_a_min", _defaults.FunModeAMin.ToString()),
            ["fun_mode_a_max"] = stored.GetValueOrDefault("fun_mode_a_max", _defaults.FunModeAMax.ToString()),
            ["fun_mode_b_max"] = stored.GetValueOrDefault("fun_mode_b_max", _defaults.FunModeBMax.ToString()),
            ["creditor_invite_hours"] = stored.GetValueOrDefault("creditor_invite_hours", _defaults.CreditorInviteHours.ToString()),
            ["hold_days"] = stored.GetValueOrDefault("hold_days", _defaults.HoldDays.ToString()),
            ["max_active_cases_a"] = stored.GetValueOrDefault("max_active_cases_a", _defaults.MaxActiveCasesModeA.ToString()),
            ["max_active_cases_b"] = stored.GetValueOrDefault("max_active_cases_b", _defaults.MaxActiveCasesModeB.ToString())
        };
    }

    public async Task<long> MinContributionAsync(CancellationToken ct = default) =>
        await GetLongAsync("min_contribution", _defaults.MinContribution, ct);

    public async Task<long> ModeAMaxAsync(CancellationToken ct = default) =>
        await GetLongAsync("fun_mode_a_max", _defaults.FunModeAMax, ct);

    public async Task<long> ModeAMinAsync(CancellationToken ct = default) =>
        await GetLongAsync("fun_mode_a_min", _defaults.FunModeAMin, ct);

    public async Task<int> CreditorInviteHoursAsync(CancellationToken ct = default) =>
        await GetIntAsync("creditor_invite_hours", _defaults.CreditorInviteHours, ct);

    public async Task<int> HoldDaysAsync(CancellationToken ct = default) =>
        await GetIntAsync("hold_days", _defaults.HoldDays, ct);
}
