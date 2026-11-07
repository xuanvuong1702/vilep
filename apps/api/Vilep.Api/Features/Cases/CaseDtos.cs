using Vilep.Api.Domain;

namespace Vilep.Api.Features.Cases;

public record UserBrief(Guid Id, string Nickname, string AvatarKey);

public record ContributorDto(string Name, string AvatarKey, long Amount, string? Message, string? Sticker,
    DateTimeOffset CreatedAt, bool IsLastToClose);

public record CaseSummary(
    Guid Id,
    string Code,
    string Title,
    string Category,
    string PayoutMode,
    string State,
    string DisplayMode,
    int Percent,
    long TargetAmount,
    long RaisedAmount,
    int ContributorCount,
    DateTimeOffset? Deadline,
    int DaysLeft,
    DateTimeOffset CreatedAt,
    UserBrief? Debtor,
    bool CreditorConfirmed,
    string CreditorName,
    string Label,
    string CoverEmoji,
    string CoverColor,
    bool IsMine,
    bool CanContribute,
    string? LatestMessage);

public record CaseDetail(
    Guid Id,
    string Code,
    string Title,
    string Story,
    string Category,
    string PayoutMode,
    string State,
    string DisplayMode,
    int Percent,
    long TargetAmount,
    long RaisedAmount,
    long DebtAmount,
    int ContributorCount,
    DateTimeOffset? Deadline,
    int DaysLeft,
    DateTimeOffset CreatedAt,
    UserBrief? Debtor,
    bool CreditorConfirmed,
    string CreditorName,
    string CreditorBankMasked,
    string Label,
    string MoneyDestination,
    string CoverEmoji,
    string CoverColor,
    bool IsMine,
    bool CanContribute,
    long Remaining,
    long MinContribution,
    long TipSuggestAmount,
    IReadOnlyList<ContributorDto> Contributors,
    IReadOnlyList<string> NextStates,
    string? CertificateCode,
    DateTimeOffset? PaidAt,
    string? PayoutReceiptRef);

public static class CaseMapper
{
    private static readonly Dictionary<string, (string Emoji, string Color)> Covers = new()
    {
        ["tra-sua"] = ("🧋", "#FFB4A2"),
        ["nhau"] = ("🍻", "#FFD166"),
        ["ca-cuoc"] = ("⚽", "#8ECAE6"),
        ["an-uong"] = ("🍜", "#B7E4C7"),
        ["qua-sinh-nhat"] = ("🎁", "#CDB4DB"),
        ["muon-tien"] = ("🤝", "#A2D2FF"),
        ["hoc-phi"] = ("📚", "#FDE2E4"),
        ["khac"] = ("👛", "#D0F4DE")
    };

    public static (string Emoji, string Color) CoverFor(string category) =>
        Covers.TryGetValue(category, out var cover) ? cover : Covers["khac"];

    public static string LabelFor(Case c) => c.PayoutMode == PayoutModes.Creditor
        ? "Chủ nợ đã xác nhận"
        : "Cần bằng chứng trả nợ";

    public static string MoneyDestinationFor(Case c) => c.PayoutMode == PayoutModes.Creditor
        ? "Chuyển thẳng cho chủ nợ khi đủ mục tiêu"
        : "Về ví con nợ, kèm bằng chứng trả nợ";

    public static int PercentOf(Case c) =>
        c.TargetAmount <= 0 ? 0 : (int)Math.Clamp(c.RaisedAmount * 100 / c.TargetAmount, 0, 100);

    public static int DaysLeft(Case c) =>
        c.Deadline is null ? 0 : Math.Max(0, (int)Math.Ceiling((c.Deadline.Value - DateTimeOffset.UtcNow).TotalDays));

    public static UserBrief? DebtorBrief(Case c, bool isMine)
    {
        if (c.Debtor is null) return null;
        var name = c.DisplayMode switch
        {
            DisplayModes.Anonymous => "Người giấu tên",
            DisplayModes.RealName => c.Debtor.Nickname,
            _ => c.Debtor.Nickname
        };
        return new UserBrief(c.Debtor.Id, name, c.Debtor.AvatarKey);
    }

    public static CaseSummary ToSummary(Case c, Guid? viewerId, int contributorCount, string? latestMessage)
    {
        var cover = CoverFor(c.Category);
        var isMine = viewerId is not null && viewerId == c.DebtorId;
        return new CaseSummary(
            c.Id, c.Code, c.Title, c.Category, c.PayoutMode, c.State, c.DisplayMode,
            PercentOf(c), c.TargetAmount, c.RaisedAmount, contributorCount, c.Deadline, DaysLeft(c), c.CreatedAt,
            DebtorBrief(c, isMine), c.Creditor?.ConfirmedAt is not null,
            c.Creditor?.Name is null ? "" : MaskName(c.Creditor.Name),
            LabelFor(c), cover.Emoji, cover.Color, isMine,
            c.State == CaseStates.Funding && !isMine, latestMessage);
    }

    public static string MaskName(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return "Chủ nợ";
        var parts = name.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 1)
            return parts[0].Length <= 2 ? parts[0] : parts[0][0] + new string('*', parts[0].Length - 1);
        return string.Join(' ', parts.Take(parts.Length - 1)) + " " + parts[^1][0] + ".";
    }
}
