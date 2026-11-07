namespace Vilep.Api.Domain;

public static class Branches
{
    public const string Fun = "fun";
    public const string Real = "real";
}

public static class PayoutModes
{
    public const string Creditor = "creditor";
    public const string Debtor = "debtor";
}

public static class CaseStates
{
    public const string Draft = "draft";
    public const string PendingCreditor = "pending_creditor";
    public const string Submitted = "submitted";
    public const string Verifying = "verifying";
    public const string Rejected = "rejected";
    public const string Funding = "funding";
    public const string Suspended = "suspended";
    public const string Disputed = "disputed";
    public const string Cancelled = "cancelled";
    public const string Closed = "closed";
    // Mode A branch
    public const string Funded = "funded";
    public const string PayoutPending = "payout_pending";
    public const string PayoutFailed = "payout_failed";
    public const string Paid = "paid";
    public const string Expired = "expired";
    public const string Refunding = "refunding";
    public const string Refunded = "refunded";
    // Mode B branch
    public const string Ended = "ended";
    public const string ProofPending = "proof_pending";
    public const string ProofVerified = "proof_verified";
    public const string ProofOverdue = "proof_overdue";
}

public static class ContributionStates
{
    public const string Pending = "pending";
    public const string Succeeded = "succeeded";
    public const string Held = "held";
    public const string Available = "available";
    public const string Withdrawn = "withdrawn";
    public const string Refunded = "refunded";
    public const string Failed = "failed";
}

public static class PayoutStates
{
    public const string Pending = "pending";
    public const string Approved = "approved";
    public const string Processing = "processing";
    public const string Paid = "paid";
    public const string Failed = "failed";
    public const string Cancelled = "cancelled";
}

public static class RefundStates
{
    public const string Pending = "pending";
    public const string Done = "done";
    public const string Failed = "failed";
}

public static class LedgerAccounts
{
    public const string GatewayClearing = "gateway_clearing";
    public const string CaseEscrow = "case_escrow";
    public const string CaseHold = "case_hold";
    public const string CaseAvailable = "case_available";
    public const string CreditorPayoutClearing = "creditor_payout_clearing";
    public const string WithdrawalClearing = "withdrawal_clearing";
    public const string RefundClearing = "refund_clearing";
    public const string PlatformTip = "platform_tip";
    public const string ProcessingFee = "processing_fee";
}

public static class DisplayModes
{
    public const string RealName = "real";
    public const string Nickname = "nickname";
    public const string Anonymous = "anonymous";
}

public static class KycTiers
{
    public const int None = 0;
    public const int Light = 1;
    public const int Full = 2;
}

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Phone { get; set; } = "";
    public string? Email { get; set; }
    public string Nickname { get; set; } = "";
    public string AvatarKey { get; set; } = "wallet-1";
    public string Bio { get; set; } = "";
    public int KycTier { get; set; }
    public bool AgeVerified { get; set; }
    public int TrustScore { get; set; } = 100;
    public bool IsBlocked { get; set; }
    public string Role { get; set; } = "user";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? DeletedAt { get; set; }
}

public class RefreshToken
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string TokenHash { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public class OtpCode
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Phone { get; set; } = "";
    public string CodeHash { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? ConsumedAt { get; set; }
    public int Attempts { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public class KycProfile
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string IdNumberHash { get; set; } = "";
    public string FullName { get; set; } = "";
    public DateOnly? Dob { get; set; }
    public int Tier { get; set; }
    public string Status { get; set; } = "pending";
    public DateTimeOffset? VerifiedAt { get; set; }
    public string? ProviderRef { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public class BankAccount
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string OwnerType { get; set; } = "user";
    public Guid OwnerId { get; set; }
    public string BankCode { get; set; } = "";
    public string AccountNoEnc { get; set; } = "";
    public string AccountNoLast4 { get; set; } = "";
    public string AccountName { get; set; } = "";
    public bool NameMatchedKyc { get; set; }
    public bool Verified { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public class Creditor
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Phone { get; set; } = "";
    public string ContactToken { get; set; } = "";
    public DateTimeOffset? ConfirmedAt { get; set; }
    public Guid? BankAccountId { get; set; }
    public DateTimeOffset InviteExpiresAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public class Case
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Code { get; set; } = "";
    public string Branch { get; set; } = Branches.Fun;
    public string PayoutMode { get; set; } = PayoutModes.Creditor;
    public Guid DebtorId { get; set; }
    public Guid? CreditorId { get; set; }
    public string Title { get; set; } = "";
    public string Story { get; set; } = "";
    public string Category { get; set; } = "other";
    public string TemplateKey { get; set; } = "";
    public long DebtAmount { get; set; }
    public long TargetAmount { get; set; }
    public long RaisedAmount { get; set; }
    public string State { get; set; } = CaseStates.Draft;
    public DateTimeOffset? Deadline { get; set; }
    public string DisplayMode { get; set; } = DisplayModes.Nickname;
    public int HoldDays { get; set; } = 3;
    public DateTimeOffset? UpgradedToCreditorAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? PublishedAt { get; set; }
    public DateTimeOffset? ClosedAt { get; set; }
    public long Version { get; set; }
    public int ViewCount { get; set; }
    public User? Debtor { get; set; }
    public Creditor? Creditor { get; set; }
    public List<Contribution> Contributions { get; set; } = new();
}

public class Contribution
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CaseId { get; set; }
    public Guid ContributorId { get; set; }
    public long Amount { get; set; }
    public long TipAmount { get; set; }
    public long FeeAmount { get; set; }
    public string State { get; set; } = ContributionStates.Pending;
    public bool Anonymous { get; set; }
    public string? Message { get; set; }
    public string? Sticker { get; set; }
    public string IdempotencyKey { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? PaidAt { get; set; }
    public DateTimeOffset? AvailableAt { get; set; }
    public User? Contributor { get; set; }
    public Case? Case { get; set; }
}

public class PaymentTransaction
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Provider { get; set; } = "mock";
    public string ProviderRef { get; set; } = "";
    public string Direction { get; set; } = "in";
    public long Amount { get; set; }
    public string Status { get; set; } = "pending";
    public string? RawPayload { get; set; }
    public string? CheckoutUrl { get; set; }
    public string? QrPayload { get; set; }
    public string IdempotencyKey { get; set; } = "";
    public Guid? ContributionId { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? CompletedAt { get; set; }
}

public class LedgerEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid? CaseId { get; set; }
    public string RefType { get; set; } = "";
    public Guid RefId { get; set; }
    public string DebitAccount { get; set; } = "";
    public string CreditAccount { get; set; } = "";
    public long Amount { get; set; }
    public string IdempotencyKey { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public class Payout
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CaseId { get; set; }
    public Guid CreditorId { get; set; }
    public long Amount { get; set; }
    public string State { get; set; } = PayoutStates.Pending;
    public Guid? MakerId { get; set; }
    public Guid? CheckerId { get; set; }
    public string? ProviderRef { get; set; }
    public string? ReceiptKey { get; set; }
    public string? FailureReason { get; set; }
    public DateTimeOffset? CreditorConfirmedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? PaidAt { get; set; }
}

public class Refund
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ContributionId { get; set; }
    public Guid CaseId { get; set; }
    public long Amount { get; set; }
    public string State { get; set; } = RefundStates.Pending;
    public string Reason { get; set; } = "";
    public string? ProviderRef { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? DoneAt { get; set; }
}

public class Notification
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Type { get; set; } = "";
    public string Title { get; set; } = "";
    public string Body { get; set; } = "";
    public string? PayloadJson { get; set; }
    public DateTimeOffset? ReadAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public class AuditLog
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid? ActorId { get; set; }
    public string ActorRole { get; set; } = "system";
    public string Action { get; set; } = "";
    public string EntityType { get; set; } = "";
    public Guid EntityId { get; set; }
    public string? BeforeJson { get; set; }
    public string? AfterJson { get; set; }
    public string? Reason { get; set; }
    public DateTimeOffset At { get; set; } = DateTimeOffset.UtcNow;
}

public class Report
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string TargetType { get; set; } = "case";
    public Guid TargetId { get; set; }
    public Guid ReporterId { get; set; }
    public string Reason { get; set; } = "";
    public string Details { get; set; } = "";
    public string State { get; set; } = "open";
    public string? Resolution { get; set; }
    public Guid? ResolvedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? ResolvedAt { get; set; }
}

public class AppConfig
{
    public string Key { get; set; } = "";
    public string Value { get; set; } = "";
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public class Blacklist
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Type { get; set; } = "";
    public string ValueHash { get; set; } = "";
    public string Reason { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

/// <summary>
/// Single source of truth for case state transitions (spec 3.5).
/// Every transition must go through this machine and must be audited.
/// </summary>
public static class CaseStateMachine
{
    private static readonly Dictionary<string, string[]> Common = new()
    {
        [CaseStates.Draft] = new[] { CaseStates.PendingCreditor, CaseStates.Funding, CaseStates.Submitted, CaseStates.Cancelled },
        [CaseStates.PendingCreditor] = new[] { CaseStates.Funding, CaseStates.Cancelled },
        [CaseStates.Submitted] = new[] { CaseStates.Verifying, CaseStates.Rejected },
        [CaseStates.Verifying] = new[] { CaseStates.Funding, CaseStates.Rejected },
        [CaseStates.Rejected] = new[] { CaseStates.Draft },
        [CaseStates.Suspended] = new[] { CaseStates.Funding, CaseStates.Refunding },
        [CaseStates.Disputed] = new[] { CaseStates.Closed, CaseStates.Refunding },
        [CaseStates.Cancelled] = Array.Empty<string>(),
        [CaseStates.Closed] = Array.Empty<string>(),
    };

    private static readonly Dictionary<string, string[]> ModeA = new()
    {
        [CaseStates.Funding] = new[] { CaseStates.Funded, CaseStates.Expired, CaseStates.Suspended, CaseStates.Refunding },
        [CaseStates.Funded] = new[] { CaseStates.PayoutPending, CaseStates.Suspended },
        [CaseStates.PayoutPending] = new[] { CaseStates.Paid, CaseStates.PayoutFailed },
        [CaseStates.PayoutFailed] = new[] { CaseStates.PayoutPending, CaseStates.Disputed, CaseStates.Refunding },
        [CaseStates.Paid] = new[] { CaseStates.Closed, CaseStates.Disputed },
        [CaseStates.Expired] = new[] { CaseStates.Refunding },
        [CaseStates.Refunding] = new[] { CaseStates.Refunded },
        [CaseStates.Refunded] = Array.Empty<string>(),
    };

    private static readonly Dictionary<string, string[]> ModeB = new()
    {
        [CaseStates.Funding] = new[] { CaseStates.Ended, CaseStates.Suspended, CaseStates.Refunding },
        [CaseStates.Ended] = new[] { CaseStates.ProofPending, CaseStates.Closed, CaseStates.Refunding },
        [CaseStates.ProofPending] = new[] { CaseStates.ProofVerified, CaseStates.ProofOverdue },
        [CaseStates.ProofVerified] = new[] { CaseStates.Closed },
        [CaseStates.ProofOverdue] = new[] { CaseStates.ProofPending, CaseStates.Disputed, CaseStates.Refunding },
    };

    public static bool CanTransition(string payoutMode, string from, string to)
    {
        if (from == to) return false;
        var map = payoutMode == PayoutModes.Debtor ? ModeB : ModeA;
        if (map.TryGetValue(from, out var specific) && specific.Contains(to)) return true;
        if (Common.TryGetValue(from, out var common) && common.Contains(to))
        {
            // `funding -> expired` only exists in mode A; `funding -> ended` only in mode B.
            if (from == CaseStates.Funding) return false;
            return true;
        }
        return false;
    }

    public static string[] NextStates(string payoutMode, string from)
    {
        var map = payoutMode == PayoutModes.Debtor ? ModeB : ModeA;
        var list = new List<string>();
        if (map.TryGetValue(from, out var specific)) list.AddRange(specific);
        if (Common.TryGetValue(from, out var common) && from != CaseStates.Funding) list.AddRange(common);
        return list.Distinct().ToArray();
    }

    public static bool IsTerminal(string state) =>
        state is CaseStates.Closed or CaseStates.Cancelled or CaseStates.Refunded;
}
