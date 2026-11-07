using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Vilep.Api.Data;
using Vilep.Api.Domain;
using Vilep.Api.Infrastructure;
using Vilep.Api.Services;

namespace Vilep.Api.Features.Accounts;

public record OtpRequest(string Phone);
public record OtpVerify(string Phone, string Code);
public record RefreshRequest(string RefreshToken);

public record UpdateProfileRequest(string? Nickname, string? AvatarKey, string? Bio);

public record KycRequest(int Tier, string FullName, string IdNumber, string? Dob);

public record BankAccountRequest(string BankCode, string AccountNo, string AccountName, bool IsPrimary = true);

public static partial class AccountEndpoints
{
    public static void MapAccountEndpoints(this IEndpointRouteBuilder app)
    {
        var v1 = app.MapGroup("/api/v1/auth");
        v1.MapPost("/otp/request", RequestOtpAsync);
        v1.MapPost("/otp/verify", VerifyOtpAsync);
        v1.MapPost("/refresh", RefreshAsync);
        v1.MapPost("/logout", LogoutAsync).RequireAuthorization();

        var me = app.MapGroup("/api/v1/me").RequireAuthorization();
        me.MapGet("", GetMeAsync);
        me.MapPut("", UpdateMeAsync);
        me.MapPost("/kyc", SubmitKycAsync);
        me.MapGet("/bank-accounts", ListBanksAsync);
        me.MapPost("/bank-accounts", AddBankAsync);
        me.MapDelete("/bank-accounts/{id:guid}", DeleteBankAsync);
        me.MapDelete("", DeleteAccountAsync);
        me.MapGet("/stats", MyStatsAsync);
    }

    private static async Task<IResult> RequestOtpAsync(OtpRequest req, VilepDbContext db, IOptions<JwtOptions> jwt,
        IOptions<VilepOptions> opts, TimeProvider clock, CancellationToken ct)
    {
        var phone = NormalizePhone(req.Phone);
        if (phone is null) throw ApiException.BadRequest("invalid_phone", "Số điện thoại không hợp lệ (VD: 0901234567)");

        var now = clock.GetUtcNow();
        var recent = await db.OtpCodes.CountAsync(x => x.Phone == phone && x.CreatedAt > now.AddMinutes(-1), ct);
        if (recent >= 3) throw ApiException.Conflict("otp_rate_limited", "Bạn thao tác quá nhanh, thử lại sau 1 phút");

        var code = Hash.OtpCode();
        db.OtpCodes.Add(new OtpCode
        {
            Phone = phone,
            CodeHash = Hash.Hmac(jwt.Value.Key, phone + ":" + code),
            ExpiresAt = now.AddMinutes(5)
        });
        await db.SaveChangesAsync(ct);

        // TODO(production): send via SMS/Zalo provider. Dev mode returns the code so the app is testable offline.
        return ApiResult.Ok(new
        {
            phone,
            expiresIn = 300,
            devCode = opts.Value.ExposeOtpInResponse ? code : null,
            hint = opts.Value.ExposeOtpInResponse ? "Mã OTP hiển thị ở đây vì đang ở chế độ dev" : null
        });
    }

    private static async Task<IResult> VerifyOtpAsync(OtpVerify req, VilepDbContext db, IOptions<JwtOptions> jwtOpts,
        TokenService tokens, TimeProvider clock, CancellationToken ct)
    {
        var phone = NormalizePhone(req.Phone);
        if (phone is null) throw ApiException.BadRequest("invalid_phone", "Số điện thoại không hợp lệ");

        var now = clock.GetUtcNow();
        var otp = await db.OtpCodes
            .Where(x => x.Phone == phone && x.ConsumedAt == null)
            .OrderByDescending(x => x.CreatedAt)
            .FirstOrDefaultAsync(ct) ?? throw ApiException.BadRequest("otp_not_found", "Chưa có mã OTP, hãy gửi lại");

        if (otp.ExpiresAt < now) throw ApiException.BadRequest("otp_expired", "Mã OTP đã hết hạn");
        if (otp.Attempts >= 5) throw ApiException.BadRequest("otp_locked", "Nhập sai quá nhiều lần, hãy gửi mã mới");

        var expected = Hash.Hmac(jwtOpts.Value.Key, phone + ":" + req.Code.Trim());
        if (!Hash.FixedTimeEquals(expected, otp.CodeHash))
        {
            otp.Attempts++;
            await db.SaveChangesAsync(ct);
            throw ApiException.BadRequest("otp_invalid", "Mã OTP không đúng");
        }

        otp.ConsumedAt = now;

        var user = await db.Users.FirstOrDefaultAsync(x => x.Phone == phone && x.DeletedAt == null, ct);
        if (user is null)
        {
            user = new User
            {
                Phone = phone,
                Nickname = "Ví mới " + Hash.ShortCode(4),
                AvatarKey = "wallet-1",
                AgeVerified = false
            };
            db.Users.Add(user);
        }

        if (user.IsBlocked) throw ApiException.Forbidden("Tài khoản đang bị khoá");

        await db.SaveChangesAsync(ct);
        var (access, expiresIn) = tokens.CreateAccessToken(user);
        var refresh = await tokens.CreateRefreshTokenAsync(user, ct);

        return ApiResult.Ok(new
        {
            accessToken = access,
            refreshToken = refresh,
            expiresIn,
            user = MapUser(user)
        });
    }

    private static async Task<IResult> RefreshAsync(RefreshRequest req, VilepDbContext db, TokenService tokens,
        TimeProvider clock, CancellationToken ct)
    {
        var hash = Hash.Sha256(req.RefreshToken ?? "");
        var token = await db.RefreshTokens.FirstOrDefaultAsync(x => x.TokenHash == hash, ct)
                    ?? throw ApiException.Unauthorized("Refresh token không hợp lệ");
        if (token.RevokedAt is not null || token.ExpiresAt < clock.GetUtcNow())
            throw ApiException.Unauthorized("Refresh token đã hết hạn");

        var user = await db.Users.FirstOrDefaultAsync(x => x.Id == token.UserId, ct)
                   ?? throw ApiException.Unauthorized();
        if (user.IsBlocked) throw ApiException.Forbidden("Tài khoản đang bị khoá");

        token.RevokedAt = clock.GetUtcNow();
        await db.SaveChangesAsync(ct);

        var (access, expiresIn) = tokens.CreateAccessToken(user);
        var refresh = await tokens.CreateRefreshTokenAsync(user, ct);
        return ApiResult.Ok(new { accessToken = access, refreshToken = refresh, expiresIn, user = MapUser(user) });
    }

    private static async Task<IResult> LogoutAsync(RefreshRequest req, VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var hash = Hash.Sha256(req.RefreshToken ?? "");
        var token = await db.RefreshTokens.FirstOrDefaultAsync(x => x.TokenHash == hash && x.UserId == userId, ct);
        if (token is not null)
        {
            token.RevokedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
        }
        return ApiResult.Ok(new { loggedOut = true });
    }

    private static async Task<IResult> GetMeAsync(VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(x => x.Id == userId, ct) ?? throw ApiException.Unauthorized();
        var kyc = await db.KycProfiles.AsNoTracking().Where(x => x.UserId == userId).OrderByDescending(x => x.CreatedAt).FirstOrDefaultAsync(ct);
        var banks = await db.BankAccounts.AsNoTracking().Where(x => x.OwnerType == "user" && x.OwnerId == userId).ToListAsync(ct);
        var contributed = await db.Contributions.AsNoTracking()
            .Where(x => x.ContributorId == userId && x.State != ContributionStates.Pending && x.State != ContributionStates.Failed)
            .SumAsync(x => (long?)x.Amount, ct) ?? 0;
        var saved = await db.Cases.AsNoTracking().CountAsync(c => c.DebtorId == userId && c.State == CaseStates.Closed, ct);

        return ApiResult.Ok(new
        {
            user = MapUser(user),
            kyc = kyc is null ? null : new { kyc.Tier, kyc.Status, kyc.FullName, kyc.VerifiedAt },
            bankAccounts = banks.Select(b => new { b.Id, b.BankCode, accountNoMasked = "••••" + b.AccountNoLast4, b.AccountName, b.NameMatchedKyc, b.Verified }),
            stats = new { contributedAmount = contributed, casesClosed = saved }
        });
    }

    private static async Task<IResult> UpdateMeAsync(UpdateProfileRequest req, VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var user = await db.Users.FirstAsync(x => x.Id == userId, ct);
        if (req.Nickname is not null)
        {
            if (req.Nickname.Trim().Length < 2) throw ApiException.BadRequest("invalid_nickname", "Biệt danh quá ngắn");
            user.Nickname = req.Nickname.Trim()[..Math.Min(40, req.Nickname.Trim().Length)];
        }
        if (req.AvatarKey is not null) user.AvatarKey = req.AvatarKey;
        if (req.Bio is not null) user.Bio = req.Bio.Trim()[..Math.Min(200, req.Bio.Trim().Length)];
        Audit.Write(db, userId, "user", "user.updated", "user", userId, after: new { user.Nickname, user.AvatarKey });
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(MapUser(user));
    }

    private static async Task<IResult> SubmitKycAsync(KycRequest req, VilepDbContext db, CurrentUser current,
        IOptions<VilepOptions> opts, TimeProvider clock, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var user = await db.Users.FirstAsync(x => x.Id == userId, ct);
        if (req.Tier is < 1 or > 2) throw ApiException.BadRequest("invalid_tier", "Bậc KYC không hợp lệ");
        if (string.IsNullOrWhiteSpace(req.FullName) || req.IdNumber.Trim().Length < 9)
            throw ApiException.BadRequest("invalid_kyc", "Cần họ tên và số CCCD hợp lệ");

        var idHash = Hash.Sha256(req.IdNumber.Trim());
        var blacklisted = await db.Blacklists.AnyAsync(x => x.Type == "cccd" && x.ValueHash == idHash, ct);
        if (blacklisted) throw ApiException.Forbidden("blacklisted", "Giấy tờ này đang bị chặn");

        DateOnly? dob = null;
        if (!string.IsNullOrWhiteSpace(req.Dob) && DateOnly.TryParse(req.Dob, out var parsed)) dob = parsed;
        var isAdult = dob is null || dob.Value <= DateOnly.FromDateTime(DateTime.UtcNow.AddYears(-18));

        var profile = new KycProfile
        {
            UserId = userId,
            IdNumberHash = idHash,
            FullName = req.FullName.Trim(),
            Dob = dob,
            Tier = req.Tier,
            Status = opts.Value.AutoVerifyKyc ? "verified" : "pending",
            VerifiedAt = opts.Value.AutoVerifyKyc ? clock.GetUtcNow() : null,
            ProviderRef = "mock-ekyc:" + Hash.ShortCode(8)
        };
        db.KycProfiles.Add(profile);

        if (opts.Value.AutoVerifyKyc)
        {
            user.KycTier = Math.Max(user.KycTier, req.Tier);
            user.AgeVerified = isAdult;
            if (!isAdult)
                throw ApiException.Forbidden("underage", "Bạn phải đủ 18 tuổi để dùng Ví Lép");
        }

        Audit.Write(db, userId, "user", "kyc.submitted", "user", userId, after: new { tier = req.Tier, status = profile.Status });
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { tier = user.KycTier, status = profile.Status, ageVerified = user.AgeVerified });
    }

    private static async Task<IResult> ListBanksAsync(VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var banks = await db.BankAccounts.AsNoTracking()
            .Where(x => x.OwnerType == "user" && x.OwnerId == userId).ToListAsync(ct);
        return ApiResult.Ok(new { items = banks.Select(b => new { b.Id, b.BankCode, accountNoMasked = "••••" + b.AccountNoLast4, b.AccountName, b.NameMatchedKyc }) });
    }

    private static async Task<IResult> AddBankAsync(BankAccountRequest req, VilepDbContext db, CurrentUser current,
        Encryptor encryptor, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var user = await db.Users.FirstAsync(x => x.Id == userId, ct);
        if (req.AccountNo.Trim().Length < 6) throw ApiException.BadRequest("invalid_account", "Số tài khoản không hợp lệ");
        if (string.IsNullOrWhiteSpace(req.AccountName)) throw ApiException.BadRequest("invalid_account_name", "Thiếu tên chủ tài khoản");

        var kyc = await db.KycProfiles.AsNoTracking().OrderByDescending(x => x.CreatedAt)
            .FirstOrDefaultAsync(x => x.UserId == userId && x.Status == "verified", ct);
        var nameMatches = kyc is not null &&
                          string.Equals(NormalizeName(kyc.FullName), NormalizeName(req.AccountName), StringComparison.Ordinal);

        var account = new BankAccount
        {
            OwnerType = "user",
            OwnerId = userId,
            BankCode = req.BankCode.Trim().ToUpperInvariant(),
            AccountNoLast4 = encryptor.Last4(req.AccountNo.Trim()),
            AccountName = req.AccountName.Trim().ToUpperInvariant(),
            NameMatchedKyc = nameMatches,
            Verified = nameMatches
        };
        account.AccountNoEnc = encryptor.Encrypt(req.AccountNo.Trim());
        db.BankAccounts.Add(account);
        Audit.Write(db, userId, "user", "bank_account.added", "bank_account", account.Id, after: new { account.BankCode, account.AccountNoLast4 });
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { account.Id, account.BankCode, accountNoMasked = "••••" + account.AccountNoLast4, account.AccountName, account.NameMatchedKyc });
    }

    private static async Task<IResult> DeleteBankAsync(Guid id, VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var account = await db.BankAccounts.FirstOrDefaultAsync(x => x.Id == id && x.OwnerId == userId && x.OwnerType == "user", ct)
                      ?? throw ApiException.NotFound("Không tìm thấy tài khoản");
        db.BankAccounts.Remove(account);
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { deleted = true });
    }

    private static async Task<IResult> DeleteAccountAsync(VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var user = await db.Users.FirstAsync(x => x.Id == userId, ct);
        var activeCases = await db.Cases.CountAsync(c => c.DebtorId == userId
            && (c.State == CaseStates.Funding || c.State == CaseStates.PendingCreditor || c.State == CaseStates.Draft), ct);
        if (activeCases > 0) throw ApiException.Conflict("has_active_cases", "Hãy đóng các case đang chạy trước khi xoá tài khoản");

        user.DeletedAt = DateTimeOffset.UtcNow;
        user.Phone = "deleted-" + user.Id.ToString("N");
        user.Nickname = "Tài khoản đã xoá";
        user.Bio = "";
        user.AvatarKey = "wallet-mask";
        user.KycTier = 0;
        user.AgeVerified = false;
        user.IsBlocked = true;

        var tokens = await db.RefreshTokens.Where(x => x.UserId == userId && x.RevokedAt == null).ToListAsync(ct);
        foreach (var token in tokens) token.RevokedAt = DateTimeOffset.UtcNow;

        var banks = await db.BankAccounts.Where(x => x.OwnerType == "user" && x.OwnerId == userId).ToListAsync(ct);
        db.BankAccounts.RemoveRange(banks);

        var kyc = await db.KycProfiles.Where(x => x.UserId == userId).ToListAsync(ct);
        db.KycProfiles.RemoveRange(kyc);

        Audit.Write(db, userId, "user", "account.deleted", "user", userId);
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { deleted = true });
    }

    private static async Task<IResult> MyStatsAsync(VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var created = await db.Cases.CountAsync(c => c.DebtorId == userId, ct);
        var closed = await db.Cases.CountAsync(c => c.DebtorId == userId && c.State == CaseStates.Closed, ct);
        var rescues = await db.Contributions.CountAsync(x => x.ContributorId == userId
            && (x.State == ContributionStates.Succeeded || x.State == ContributionStates.Available), ct);
        var amount = await db.Contributions.Where(x => x.ContributorId == userId
                && (x.State == ContributionStates.Succeeded || x.State == ContributionStates.Available))
            .SumAsync(x => (long?)x.Amount, ct) ?? 0;
        return ApiResult.Ok(new { casesCreated = created, casesClosed = closed, rescues, rescuedAmount = amount });
    }

    private static object MapUser(User u) => new
    {
        id = u.Id,
        phone = u.Phone,
        nickname = u.Nickname,
        avatarKey = u.AvatarKey,
        bio = u.Bio,
        kycTier = u.KycTier,
        ageVerified = u.AgeVerified,
        trustScore = u.TrustScore,
        role = u.Role,
        createdAt = u.CreatedAt
    };

    private static string NormalizeName(string name) =>
        Regex.Replace(name.Trim().ToUpperInvariant(), @"\s+", " ");

    internal static string? NormalizePhone(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var digits = new string(raw.Where(char.IsDigit).ToArray());
        if (digits.StartsWith("84") && digits.Length == 11) digits = "0" + digits[2..];
        if (digits.Length is < 9 or > 11) return null;
        if (!digits.StartsWith('0')) return null;
        return digits;
    }
}
