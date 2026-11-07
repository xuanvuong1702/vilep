using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Vilep.Api.Data;
using Vilep.Api.Domain;
using Vilep.Api.Infrastructure;
using Vilep.Api.Services;

namespace Vilep.Api.Features.Cases;

public record CreateCaseRequest(
    string Title,
    string Story,
    string Category,
    long DebtAmount,
    long TargetAmount,
    string? DisplayMode,
    int? FundraisingDays,
    string? TemplateKey);

public record UpdateCaseRequest(string? Title, string? Story, string? Category, long? DebtAmount, long? TargetAmount, string? DisplayMode);

public record PublishCaseRequest(string Mode); // creditor | debtor

public record InviteCreditorRequest(string Name, string Phone);

public record ConfirmCreditorRequest(string AccountName, string BankCode, string AccountNo);

public static class CaseEndpoints
{
    private static readonly HashSet<string> Categories = new()
    { "tra-sua", "nhau", "ca-cuoc", "an-uong", "qua-sinh-nhat", "muon-tien", "khac" };

    public static void MapCaseEndpoints(this IEndpointRouteBuilder app)
    {
        var v1 = app.MapGroup("/api/v1");

        v1.MapGet("/cases", ListCasesAsync);
        v1.MapGet("/cases/{id:guid}", GetCaseAsync);
        v1.MapGet("/meta/config", GetPublicConfigAsync);
        v1.MapGet("/meta/templates", GetTemplates);

        var mine = v1.MapGroup("/my/cases").RequireAuthorization();
        mine.MapGet("", MyCasesAsync);
        mine.MapPost("", CreateCaseAsync);
        mine.MapPut("/{id:guid}", UpdateCaseAsync);
        mine.MapPost("/{id:guid}/publish", PublishCaseAsync);
        mine.MapPost("/{id:guid}/cancel", CancelCaseAsync);
        mine.MapPost("/{id:guid}/invite-creditor", InviteCreditorAsync);
        mine.MapPost("/{id:guid}/upgrade-to-creditor", UpgradeToCreditorAsync);

        var creditor = v1.MapGroup("/creditor");
        creditor.MapGet("/invite/{token}", GetInviteAsync);
        creditor.MapPost("/invite/{token}/confirm", ConfirmInviteAsync);
        creditor.MapPost("/{token}/received", ConfirmReceivedAsync);
    }

    private static async Task<IResult> ListCasesAsync(HttpContext http, VilepDbContext db, CurrentUser current,
        string? tab, string? category, string? q, string? mode, string? cursor, int? limit, CancellationToken ct)
    {
        var viewer = current.OptionalId;
        var take = Math.Clamp(limit ?? 20, 1, 50);
        var now = DateTimeOffset.UtcNow;

        var query = db.Cases.AsNoTracking()
            .Include(c => c.Debtor)
            .Include(c => c.Creditor)
            .Where(c => c.State == CaseStates.Funding || c.State == CaseStates.Funded || c.State == CaseStates.Paid);

        if (!string.IsNullOrWhiteSpace(category) && category != "all") query = query.Where(c => c.Category == category);
        if (!string.IsNullOrWhiteSpace(mode) && mode != "all") query = query.Where(c => c.PayoutMode == mode);
        if (!string.IsNullOrWhiteSpace(q))
        {
            var term = q.Trim();
            query = query.Where(c => EF.Functions.Like(c.Title, $"%{term}%") || EF.Functions.Like(c.Story, $"%{term}%"));
        }

        if (DateTimeOffset.TryParse(cursor, out var cursorAt))
            query = query.Where(c => c.CreatedAt < cursorAt);

        query = tab switch
        {
            "almost" => query.Where(c => c.RaisedAmount * 10 >= c.TargetAmount * 8).OrderByDescending(c => c.RaisedAmount * 100 / c.TargetAmount),
            "newest" => query.OrderByDescending(c => c.CreatedAt),
            "friends" => viewer is null
                ? query.Where(_ => false)
                : query.Where(c => db.Contributions.Any(x => x.ContributorId == viewer && x.Case!.DebtorId == c.DebtorId)),
            _ => query.OrderByDescending(c => c.PayoutMode == PayoutModes.Creditor).ThenByDescending(c => c.CreatedAt)
        };

        var cases = await query.Take(take + 1).ToListAsync(ct);
        var hasMore = cases.Count > take;
        if (hasMore) cases.RemoveAt(cases.Count - 1);

        var ids = cases.Select(c => c.Id).ToList();
        var counts = await db.Contributions.AsNoTracking()
            .Where(x => ids.Contains(x.CaseId) && (x.State == ContributionStates.Succeeded || x.State == ContributionStates.Held || x.State == ContributionStates.Available))
            .GroupBy(x => x.CaseId)
            .Select(g => new { g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.Count, ct);

        var items = cases.Select(c => CaseMapper.ToSummary(c, viewer, counts.GetValueOrDefault(c.Id), null)).ToList();
        var next = hasMore ? cases[^1].CreatedAt.ToString("O") : null;
        return ApiResult.Ok(new { items, nextCursor = next });
    }

    private static async Task<IResult> GetCaseAsync(Guid id, VilepDbContext db, CurrentUser current,
        ConfigService config, CancellationToken ct)
    {
        var viewer = current.OptionalId;
        var c = await db.Cases.AsNoTracking()
            .Include(x => x.Debtor)
            .Include(x => x.Creditor)
            .FirstOrDefaultAsync(x => x.Id == id, ct)
            ?? throw ApiException.NotFound("Không tìm thấy case");

        if (c.State == CaseStates.Draft && viewer != c.DebtorId && !current.IsAdmin)
            throw ApiException.NotFound("Không tìm thấy case");

        var contributions = await db.Contributions.AsNoTracking()
            .Include(x => x.Contributor)
            .Where(x => x.CaseId == id && (x.State == ContributionStates.Succeeded || x.State == ContributionStates.Held
                || x.State == ContributionStates.Available || x.State == ContributionStates.Withdrawn))
            .OrderBy(x => x.PaidAt).ThenBy(x => x.CreatedAt)
            .ToListAsync(ct);

        long cumulative = 0;
        var lastToClose = (Guid?)null;
        foreach (var contribution in contributions)
        {
            cumulative += contribution.Amount;
            if (lastToClose is null && cumulative >= c.TargetAmount) lastToClose = contribution.Id;
        }

        var list = contributions.Select(x => new ContributorDto(
                x.Anonymous ? "Người bạn giấu tên" : (x.Contributor?.Nickname ?? "Người dùng"),
                x.Anonymous ? "wallet-mask" : (x.Contributor?.AvatarKey ?? "wallet-1"),
                x.Amount, x.Message, x.Sticker, x.PaidAt ?? x.CreatedAt,
                x.Id == lastToClose && c.RaisedAmount >= c.TargetAmount))
            .ToList();

        var payout = await db.Payouts.AsNoTracking().Where(p => p.CaseId == id).OrderByDescending(p => p.CreatedAt).FirstOrDefaultAsync(ct);
        var creditorAccount = c.Creditor?.BankAccountId is null ? null
            : await db.BankAccounts.AsNoTracking().FirstOrDefaultAsync(x => x.Id == c.Creditor.BankAccountId, ct);

        var detail = new CaseDetail(
            c.Id, c.Code, c.Title, c.Story, c.Category, c.PayoutMode, c.State, c.DisplayMode,
            CaseMapper.PercentOf(c), c.TargetAmount, c.RaisedAmount, c.DebtAmount, list.Count, c.Deadline,
            CaseMapper.DaysLeft(c), c.CreatedAt, CaseMapper.DebtorBrief(c, viewer == c.DebtorId),
            c.Creditor?.ConfirmedAt is not null,
            c.Creditor is null ? "" : CaseMapper.MaskName(c.Creditor.Name),
            creditorAccount is null ? "" : $"••{creditorAccount.AccountNoLast4}",
            CaseMapper.LabelFor(c), CaseMapper.MoneyDestinationFor(c),
            CaseMapper.CoverFor(c.Category).Emoji, CaseMapper.CoverFor(c.Category).Color,
            viewer == c.DebtorId, c.State == CaseStates.Funding && viewer != c.DebtorId,
            Math.Max(0, c.TargetAmount - c.RaisedAmount),
            await config.MinContributionAsync(ct),
            Math.Max(10_000, c.RaisedAmount == 0 ? 10_000 : c.RaisedAmount / 20),
            list, CaseStateMachine.NextStates(c.PayoutMode, c.State),
            c.State is CaseStates.Paid or CaseStates.Closed ? "VL-" + c.Code.ToUpperInvariant() : null,
            payout?.PaidAt, payout?.ProviderRef);

        return ApiResult.Ok(detail);
    }

    private static async Task<IResult> GetPublicConfigAsync(ConfigService config, IOptions<VilepOptions> options, CancellationToken ct)
    {
        var all = await config.AllAsync(ct);
        return ApiResult.Ok(new
        {
            minContribution = all["min_contribution"],
            funModeAMin = all["fun_mode_a_min"],
            funModeAMax = all["fun_mode_a_max"],
            funModeBMax = all["fun_mode_b_max"],
            holdDays = all["hold_days"],
            categories = new[]
            {
                new { key = "tra-sua", label = "Trà sữa", emoji = "🧋" },
                new { key = "nhau", label = "Nợ nhậu", emoji = "🍻" },
                new { key = "ca-cuoc", label = "Thua cược", emoji = "⚽" },
                new { key = "an-uong", label = "Mượn tiền ăn", emoji = "🍜" },
                new { key = "qua-sinh-nhat", label = "Quà sinh nhật", emoji = "🎁" },
                new { key = "muon-tien", label = "Mượn tiền", emoji = "🤝" },
                new { key = "khac", label = "Khác", emoji = "👛" }
            }
        });
    }

    private static IResult GetTemplates()
    {
        var templates = new[]
        {
            new { key = "tra-sua", category = "tra-sua", emoji = "🧋", title = "Cứu mình ly trà sữa cuối tháng", amount = 45_000, story = "Tháng này uống trà sữa hơi nhiều, giờ ví lép quá rồi. Ai cứu mình ly trà sữa với!" },
            new { key = "nhau", category = "nhau", emoji = "🍻", title = "Nợ tiền nhậu trận chung kết", amount = 250_000, story = "Trận chung kết hứa bao cả bàn, giờ ngồi nhìn hoá đơn. Ví lép, bạn bè lo giúp nhé!" },
            new { key = "ca-cuoc", category = "ca-cuoc", emoji = "⚽", title = "Thua kèo bóng, xin cứu ví", amount = 300_000, story = "Kèo này mình thua thật, chấp nhận bị trêu. Ai cứu giúp mình trả nợ với!" },
            new { key = "an-uong", category = "an-uong", emoji = "🍜", title = "Mượn tiền ăn trưa cả tuần", amount = 100_000, story = "Cuối tháng cháy ví, mượn bạn tiền ăn trưa. Cứu mình vài bữa với!" },
            new { key = "qua-sinh-nhat", category = "qua-sinh-nhat", emoji = "🎁", title = "Nợ tiền quà sinh nhật bạn thân", amount = 200_000, story = "Mua quà sinh nhật hơi quá tay, giờ nợ. Mọi người giúp mình trả nợ nhé!" },
            new { key = "muon-tien", category = "muon-tien", emoji = "🤝", title = "Trả nợ tiền mượn đúng hẹn", amount = 150_000, story = "Đã hứa trả bạn đúng hẹn mà ví lép quá. Cứu mình lần này, mình giữ chữ tín!" }
        };
        return ApiResult.Ok(new { items = templates });
    }

    private static async Task<IResult> MyCasesAsync(VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var cases = await db.Cases.AsNoTracking()
            .Include(c => c.Debtor).Include(c => c.Creditor)
            .Where(c => c.DebtorId == userId)
            .OrderByDescending(c => c.CreatedAt)
            .ToListAsync(ct);
        var ids = cases.Select(c => c.Id).ToList();
        var counts = await db.Contributions.Where(x => ids.Contains(x.CaseId))
            .GroupBy(x => x.CaseId).Select(g => new { g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.Count, ct);
        return ApiResult.Ok(new { items = cases.Select(c => CaseMapper.ToSummary(c, userId, counts.GetValueOrDefault(c.Id), null)) });
    }

    private static async Task<IResult> CreateCaseAsync(CreateCaseRequest req, VilepDbContext db, CurrentUser current,
        ConfigService config, IOptions<VilepOptions> options, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var user = await db.Users.FirstAsync(u => u.Id == userId, ct);
        if (user.IsBlocked) throw ApiException.Forbidden("Tài khoản đang bị khoá");

        if (string.IsNullOrWhiteSpace(req.Title) || req.Title.Length < 6)
            throw ApiException.BadRequest("invalid_title", "Tiêu đề cần ít nhất 6 ký tự");
        if (req.Title.Length > 120) throw ApiException.BadRequest("invalid_title", "Tiêu đề tối đa 120 ký tự");
        if (string.IsNullOrWhiteSpace(req.Story) || req.Story.Length < 20)
            throw ApiException.BadRequest("invalid_story", "Lời kể cần ít nhất 20 ký tự");
        if (!Categories.Contains(req.Category)) throw ApiException.BadRequest("invalid_category", "Danh mục không hợp lệ");

        var min = await config.ModeAMinAsync(ct);
        var max = await config.ModeAMaxAsync(ct);
        if (req.TargetAmount < min || req.TargetAmount > max)
            throw ApiException.BadRequest("invalid_target", $"Số tiền mục tiêu phải từ {min:N0}đ đến {max:N0}đ");
        if (req.DebtAmount < req.TargetAmount)
            throw ApiException.BadRequest("invalid_debt", "Số tiền nợ phải lớn hơn hoặc bằng mục tiêu");

        var active = await db.Cases.CountAsync(c => c.DebtorId == userId
            && (c.State == CaseStates.Funding || c.State == CaseStates.PendingCreditor || c.State == CaseStates.Draft), ct);
        var limit = await config.GetIntAsync("max_active_cases_a", options.Value.MaxActiveCasesModeA, ct);
        if (active >= limit) throw ApiException.Conflict("too_many_cases", $"Bạn chỉ được có {limit} case đang hoạt động");

        var c = new Case
        {
            Code = await NewCodeAsync(db, ct),
            Branch = Branches.Fun,
            PayoutMode = PayoutModes.Creditor,
            DebtorId = userId,
            Title = req.Title.Trim(),
            Story = req.Story.Trim(),
            Category = req.Category,
            TemplateKey = req.TemplateKey ?? "",
            DebtAmount = req.DebtAmount,
            TargetAmount = req.TargetAmount,
            State = CaseStates.Draft,
            DisplayMode = req.DisplayMode is DisplayModes.Anonymous or DisplayModes.RealName ? req.DisplayMode : DisplayModes.Nickname,
            HoldDays = await config.HoldDaysAsync(ct)
        };
        db.Cases.Add(c);
        Audit.Write(db, userId, "user", "case.created", "case", c.Id, after: new { c.Title, c.TargetAmount });
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = c.Id, code = c.Code, state = c.State });
    }

    private static async Task<IResult> UpdateCaseAsync(Guid id, UpdateCaseRequest req, VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var c = await db.Cases.FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy case");
        if (c.DebtorId != userId) throw ApiException.NotFound("Không tìm thấy case");
        if (c.State != CaseStates.Draft) throw ApiException.Conflict("case_locked", "Case đã mở gây quỹ, không sửa được nữa");

        if (req.Title is not null) c.Title = req.Title.Trim();
        if (req.Story is not null) c.Story = req.Story.Trim();
        if (req.Category is not null && Categories.Contains(req.Category)) c.Category = req.Category;
        if (req.DebtAmount is not null) c.DebtAmount = req.DebtAmount.Value;
        if (req.TargetAmount is not null) c.TargetAmount = req.TargetAmount.Value;
        if (req.DisplayMode is not null && req.DisplayMode is DisplayModes.Anonymous or DisplayModes.RealName or DisplayModes.Nickname)
            c.DisplayMode = req.DisplayMode;
        c.Version++;
        Audit.Write(db, userId, "user", "case.updated", "case", c.Id, after: new { c.Title, c.TargetAmount });
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = c.Id, state = c.State });
    }

    private static async Task<IResult> PublishCaseAsync(Guid id, PublishCaseRequest req, VilepDbContext db, CurrentUser current,
        CaseWorkflow workflow, IOptions<VilepOptions> options, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var user = await db.Users.FirstAsync(u => u.Id == userId, ct);
        var c = await db.Cases.Include(x => x.Creditor).FirstOrDefaultAsync(x => x.Id == id, ct)
                ?? throw ApiException.NotFound("Không tìm thấy case");
        if (c.DebtorId != userId) throw ApiException.NotFound("Không tìm thấy case");
        if (c.State != CaseStates.Draft) throw ApiException.Conflict("already_published", "Case đã được đăng");

        if (req.Mode != PayoutModes.Debtor)
        {
            // Mode A opens automatically when the creditor confirms the debt.
            if (c.Creditor?.ConfirmedAt is not null && c.State == CaseStates.PendingCreditor)
            {
                workflow.Transition(c, CaseStates.Funding, userId, "user", "Đăng case chế độ A");
                await db.SaveChangesAsync(ct);
                return ApiResult.Ok(new { id = c.Id, state = c.State, mode = c.PayoutMode });
            }
            throw ApiException.Conflict("creditor_not_confirmed",
                "Chế độ A cần chủ nợ bấm link xác nhận. Hãy gửi link mời chủ nợ trước.");
        }

        if (user.KycTier < KycTiers.Full)
            throw ApiException.Forbidden("kyc_required", "Chế độ B cần eKYC bậc 2 (CCCD + selfie + tài khoản chính chủ)");
        if (c.TargetAmount > options.Value.FunModeBMax)
            throw ApiException.BadRequest("over_limit", $"Chế độ B tối đa {options.Value.FunModeBMax:N0}đ");
        c.PayoutMode = PayoutModes.Debtor;
        c.Deadline = DateTimeOffset.UtcNow.AddDays(options.Value.DefaultFundraisingDays);
        c.PublishedAt = DateTimeOffset.UtcNow;
        workflow.Transition(c, CaseStates.Funding, userId, "user", "Đăng case chế độ B");
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = c.Id, state = c.State, mode = c.PayoutMode });
    }

    private static async Task<IResult> InviteCreditorAsync(Guid id, InviteCreditorRequest req, VilepDbContext db, CurrentUser current,
        ConfigService config, IOptions<VilepOptions> options, CaseWorkflow workflow, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var user = await db.Users.FirstAsync(u => u.Id == userId, ct);
        if (user.KycTier < KycTiers.Light)
            throw ApiException.Forbidden("kyc_required", "Cần eKYC bậc 1 trước khi mời chủ nợ xác nhận");
        var c = await db.Cases.Include(x => x.Creditor).FirstOrDefaultAsync(x => x.Id == id, ct)
                ?? throw ApiException.NotFound("Không tìm thấy case");
        if (c.DebtorId != userId) throw ApiException.NotFound("Không tìm thấy case");
        if (c.State != CaseStates.Draft && c.State != CaseStates.PendingCreditor)
            throw ApiException.Conflict("invalid_state", "Chỉ mời chủ nợ khi case đang ở bước chờ xác nhận");
        if (string.IsNullOrWhiteSpace(req.Name)) throw ApiException.BadRequest("invalid_name", "Nhập tên chủ nợ");
        if (string.IsNullOrWhiteSpace(req.Phone)) throw ApiException.BadRequest("invalid_phone", "Nhập số điện thoại chủ nợ");

        Creditor creditor;
        if (c.CreditorId is not null && c.Creditor is not null)
        {
            creditor = c.Creditor;
            creditor.Name = req.Name.Trim();
            creditor.Phone = req.Phone.Trim();
            creditor.InviteExpiresAt = DateTimeOffset.UtcNow.AddHours(await config.CreditorInviteHoursAsync(ct));
        }
        else
        {
            creditor = new Creditor
            {
                Name = req.Name.Trim(),
                Phone = req.Phone.Trim(),
                ContactToken = Hash.ShortCode(10),
                InviteExpiresAt = DateTimeOffset.UtcNow.AddHours(await config.CreditorInviteHoursAsync(ct))
            };
            db.Creditors.Add(creditor);
            c.CreditorId = creditor.Id;
        }

        c.Version++;
        Audit.Write(db, userId, "user", "creditor.invited", "case", c.Id, after: new { creditor.Id, creditor.Phone });

        if (c.State == CaseStates.Draft)
        {
            c.Deadline = DateTimeOffset.UtcNow.AddDays(options.Value.DefaultFundraisingDays);
            c.PublishedAt = DateTimeOffset.UtcNow;
            workflow.Transition(c, CaseStates.PendingCreditor, userId, "user", "Gửi lời mời chủ nợ xác nhận");
        }
        await db.SaveChangesAsync(ct);

        var link = $"{options.Value.BaseUrl}/api/v1/creditor/invite/{creditor.ContactToken}";
        var shortLink = $"{options.Value.BaseUrl}/c/{c.Code}";
        return ApiResult.Ok(new
        {
            creditorId = creditor.Id,
            token = creditor.ContactToken,
            inviteUrl = link,
            shortUrl = shortLink,
            expiresAt = creditor.InviteExpiresAt,
            deepLink = $"vilep://creditor/{creditor.ContactToken}"
        });
    }

    private static async Task<IResult> CancelCaseAsync(Guid id, VilepDbContext db, CurrentUser current, CaseWorkflow workflow,
        RefundService refunds, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var c = await db.Cases.FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy case");
        if (c.DebtorId != userId) throw ApiException.NotFound("Không tìm thấy case");
        if (CaseStateMachine.IsTerminal(c.State)) throw ApiException.Conflict("already_closed", "Case đã kết thúc");

        if (c.RaisedAmount == 0)
        {
            workflow.Transition(c, CaseStates.Cancelled, userId, "user", "Con nợ huỷ case");
            await db.SaveChangesAsync(ct);
            return ApiResult.Ok(new { id = c.Id, state = c.State });
        }

        workflow.Transition(c, CaseStates.Refunding, userId, "user", "Con nợ huỷ case đã có đóng góp, hoàn tiền");
        await db.SaveChangesAsync(ct);
        await refunds.RefundCaseAsync(c, "case_cancelled", userId, ct);
        return ApiResult.Ok(new { id = c.Id, state = c.State, refunded = true });
    }

    private static async Task<IResult> UpgradeToCreditorAsync(Guid id, VilepDbContext db, CurrentUser current,
        LedgerService ledger, CaseWorkflow workflow, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var c = await db.Cases.Include(x => x.Creditor).FirstOrDefaultAsync(x => x.Id == id, ct)
                ?? throw ApiException.NotFound("Không tìm thấy case");
        if (c.DebtorId != userId) throw ApiException.NotFound("Không tìm thấy case");
        if (c.PayoutMode != PayoutModes.Debtor) throw ApiException.Conflict("not_mode_b", "Case đang ở chế độ A");
        if (c.Creditor?.ConfirmedAt is null) throw ApiException.Conflict("creditor_required", "Chủ nợ chưa xác nhận");
        if (c.State is CaseStates.Paid or CaseStates.Closed or CaseStates.Refunded)
            throw ApiException.Conflict("already_closed", "Case đã kết thúc");

        var withdrawals = await db.Contributions.CountAsync(x => x.CaseId == id && x.State == ContributionStates.Withdrawn, ct);
        if (withdrawals > 0) throw ApiException.Conflict("already_withdrawn", "Đã có tiền rút, không nâng cấp được");

        // Move held/available funds into escrow and mark them as settled contributions.
        var contributions = await db.Contributions.Where(x => x.CaseId == id && (x.State == ContributionStates.Held || x.State == ContributionStates.Available)).ToListAsync(ct);
        foreach (var contribution in contributions)
        {
            ledger.Post(c.Id, "upgrade", contribution.Id, LedgerAccounts.CaseHold, LedgerAccounts.CaseEscrow,
                contribution.Amount, $"upgrade:{contribution.Id}:escrow");
            contribution.State = ContributionStates.Succeeded;
        }

        c.PayoutMode = PayoutModes.Creditor;
        c.UpgradedToCreditorAt = DateTimeOffset.UtcNow;
        c.Version++;
        Audit.Write(db, userId, "user", "case.upgraded_to_creditor", "case", c.Id,
            before: new { mode = PayoutModes.Debtor }, after: new { mode = PayoutModes.Creditor, contributions = contributions.Count });
        await db.SaveChangesAsync(ct);

        return ApiResult.Ok(new { id = c.Id, mode = c.PayoutMode, moved = contributions.Sum(x => x.Amount) });
    }

    private static async Task<IResult> GetInviteAsync(string token, VilepDbContext db, CancellationToken ct)
    {
        var creditor = await db.Creditors.AsNoTracking().FirstOrDefaultAsync(x => x.ContactToken == token, ct)
                       ?? throw ApiException.NotFound("Link không hợp lệ");
        var c = await db.Cases.AsNoTracking().Include(x => x.Debtor).FirstOrDefaultAsync(x => x.CreditorId == creditor.Id, ct)
                ?? throw ApiException.NotFound("Không tìm thấy case");
        if (creditor.InviteExpiresAt < DateTimeOffset.UtcNow && creditor.ConfirmedAt is null)
            return ApiResult.Ok(new { expired = true, caseTitle = c.Title, debtorName = c.Debtor?.Nickname ?? "", confirmed = false });

        return ApiResult.Ok(new
        {
            expired = false,
            confirmed = creditor.ConfirmedAt is not null,
            confirmedAt = creditor.ConfirmedAt,
            creditorName = creditor.Name,
            caseTitle = c.Title,
            story = c.Story,
            category = c.Category,
            debtorName = c.Debtor?.Nickname ?? "",
            debtorAvatar = c.Debtor?.AvatarKey ?? "wallet-1",
            amount = c.TargetAmount,
            debtAmount = c.DebtAmount,
            caseCode = c.Code,
            caseId = c.Id,
            displayMode = c.DisplayMode,
            token
        });
    }

    private static async Task<IResult> ConfirmInviteAsync(string token, ConfirmCreditorRequest req, VilepDbContext db,
        Encryptor encryptor, CaseWorkflow workflow, NotificationService notify, CancellationToken ct)
    {
        var creditor = await db.Creditors.FirstOrDefaultAsync(x => x.ContactToken == token, ct)
                       ?? throw ApiException.NotFound("Link không hợp lệ");
        if (creditor.InviteExpiresAt < DateTimeOffset.UtcNow && creditor.ConfirmedAt is null)
            throw ApiException.Conflict("invite_expired", "Link xác nhận đã hết hạn");
        if (creditor.ConfirmedAt is not null)
            throw ApiException.Conflict("already_confirmed", "Bạn đã xác nhận khoản nợ này");

        if (string.IsNullOrWhiteSpace(req.AccountName) || string.IsNullOrWhiteSpace(req.BankCode) || req.AccountNo.Length < 6)
            throw ApiException.BadRequest("invalid_bank", "Vui lòng nhập đủ tên, ngân hàng và số tài khoản");

        var account = new BankAccount
        {
            OwnerType = "creditor",
            OwnerId = creditor.Id,
            BankCode = req.BankCode.Trim().ToUpperInvariant(),
            AccountNoEnc = string.Empty,
            AccountNoLast4 = encryptor.Last4(req.AccountNo.Trim()),
            AccountName = req.AccountName.Trim().ToUpperInvariant(),
            NameMatchedKyc = true,
            Verified = true
        };
        account.AccountNoEnc = encryptor.Encrypt(req.AccountNo.Trim());
        db.BankAccounts.Add(account);

        creditor.BankAccountId = account.Id;
        creditor.ConfirmedAt = DateTimeOffset.UtcNow;
        creditor.Name = req.AccountName.Trim();

        var c = await db.Cases.Include(x => x.Debtor).FirstOrDefaultAsync(x => x.CreditorId == creditor.Id, ct)
                ?? throw ApiException.NotFound("Không tìm thấy case");
        c.CreditorId = creditor.Id;

        if (c.State == CaseStates.PendingCreditor)
            workflow.Transition(c, CaseStates.Funding, null, "creditor", "Chủ nợ xác nhận khoản nợ");
        else if (c.State == CaseStates.Draft)
            workflow.Transition(c, CaseStates.Funding, null, "creditor", "Chủ nợ xác nhận khoản nợ, case tự mở gây quỹ");

        c.Version++;
        notify.Push(c.DebtorId, "creditor_confirmed", "Chủ nợ đã xác nhận ✅",
            $"Case \"{c.Title}\" đã chuyển sang chế độ A và bắt đầu nhận đóng góp.");
        await db.SaveChangesAsync(ct);

        return ApiResult.Ok(new
        {
            confirmed = true,
            caseId = c.Id,
            caseCode = c.Code,
            state = c.State,
            mode = c.PayoutMode,
            message = "Đã xác nhận. Tiền sẽ được chuyển tới tài khoản bạn khai khi case đủ mục tiêu."
        });
    }

    private static async Task<IResult> ConfirmReceivedAsync(string token, VilepDbContext db, CaseWorkflow workflow,
        NotificationService notify, CancellationToken ct)
    {
        var creditor = await db.Creditors.FirstOrDefaultAsync(x => x.ContactToken == token, ct)
                       ?? throw ApiException.NotFound("Link không hợp lệ");
        var c = await db.Cases.FirstOrDefaultAsync(x => x.CreditorId == creditor.Id, ct)
                ?? throw ApiException.NotFound("Không tìm thấy case");
        var payout = await db.Payouts.OrderByDescending(p => p.CreatedAt).FirstOrDefaultAsync(p => p.CaseId == c.Id, ct)
                     ?? throw ApiException.BadRequest("no_payout", "Chưa có lệnh chuyển tiền");
        if (payout.CreditorConfirmedAt is not null) return ApiResult.Ok(new { alreadyConfirmed = true, state = c.State });
        if (payout.State != PayoutStates.Paid) throw ApiException.Conflict("not_paid", "Khoản tiền chưa được chuyển");

        payout.CreditorConfirmedAt = DateTimeOffset.UtcNow;
        Audit.Write(db, null, "creditor", "payout.received", "payout", payout.Id);
        if (c.State == CaseStates.Paid)
            workflow.Transition(c, CaseStates.Closed, null, "creditor", "Chủ nợ xác nhận đã nhận tiền");

        notify.Push(c.DebtorId, "case_closed", "Case đã hoàn tất 🎉",
            $"Chủ nợ đã xác nhận nhận tiền. Bạn có thể tải Giấy chứng nhận \"Ví đã phồng trở lại\".");
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { confirmed = true, state = c.State, certificate = "VL-" + c.Code.ToUpperInvariant() });
    }

    private static async Task<string> NewCodeAsync(VilepDbContext db, CancellationToken ct)
    {
        for (var i = 0; i < 10; i++)
        {
            var code = Hash.ShortCode(8);
            if (!await db.Cases.AnyAsync(c => c.Code == code, ct)) return code;
        }
        return Guid.NewGuid().ToString("N")[..10];
    }
}
