using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using Vilep.Api.Data;
using Vilep.Api.Domain;

namespace Vilep.Api.Infrastructure;

public class TokenService
{
    private readonly JwtOptions _opt;
    private readonly VilepDbContext _db;
    private readonly TimeProvider _clock;

    public TokenService(Microsoft.Extensions.Options.IOptions<JwtOptions> opt, VilepDbContext db, TimeProvider clock)
    {
        _opt = opt.Value;
        _db = db;
        _clock = clock;
    }

    public (string accessToken, int expiresIn) CreateAccessToken(User user)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_opt.Key));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var now = _clock.GetUtcNow();
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new("phone", user.Phone),
            new("nick", user.Nickname),
            new("role", user.Role),
            new("kyc", user.KycTier.ToString()),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString("N"))
        };
        var token = new JwtSecurityToken(
            issuer: _opt.Issuer,
            audience: _opt.Audience,
            claims: claims,
            notBefore: now.UtcDateTime,
            expires: now.AddMinutes(_opt.AccessMinutes).UtcDateTime,
            signingCredentials: creds);
        return (new JwtSecurityTokenHandler().WriteToken(token), _opt.AccessMinutes * 60);
    }

    public async Task<string> CreateRefreshTokenAsync(User user, CancellationToken ct)
    {
        var raw = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
        _db.RefreshTokens.Add(new RefreshToken
        {
            UserId = user.Id,
            TokenHash = Hash.Sha256(raw),
            ExpiresAt = _clock.GetUtcNow().AddDays(_opt.RefreshDays)
        });
        await _db.SaveChangesAsync(ct);
        return raw;
    }
}

public static class Hash
{
    public static string Sha256(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    public static string Hmac(string key, string value)
    {
        var bytes = HMACSHA256.HashData(Encoding.UTF8.GetBytes(key), Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    public static string OtpCode()
    {
        return RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
    }

    public static string ShortCode(int length = 8)
    {
        const string alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
        var chars = new char[length];
        for (var i = 0; i < length; i++) chars[i] = alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)];
        return new string(chars);
    }

    public static bool FixedTimeEquals(string a, string b)
    {
        var ba = Encoding.UTF8.GetBytes(a);
        var bb = Encoding.UTF8.GetBytes(b);
        if (ba.Length != bb.Length) return false;
        return CryptographicOperations.FixedTimeEquals(ba, bb);
    }
}


public class CurrentUser
{
    private readonly IHttpContextAccessor _accessor;

    public CurrentUser(IHttpContextAccessor accessor) => _accessor = accessor;

    public ClaimsPrincipal? Principal => _accessor.HttpContext?.User;

    public Guid? IdOrNull
    {
        get
        {
            var raw = Principal?.FindFirstValue(ClaimTypes.NameIdentifier) ?? Principal?.FindFirstValue(JwtRegisteredClaimNames.Sub);
            return Guid.TryParse(raw, out var id) ? id : null;
        }
    }

    public Guid Id => IdOrNull ?? throw ApiException.Unauthorized();

    public bool IsAdmin => Principal?.IsInRole("admin") == true;

    public Guid RequireUser()
    {
        if (Principal?.Identity?.IsAuthenticated != true) throw ApiException.Unauthorized();
        return Id;
    }

    public Guid RequireAdmin()
    {
        var id = RequireUser();
        if (!IsAdmin) throw ApiException.Forbidden("Chỉ admin được dùng chức năng này");
        return id;
    }

    public Guid? OptionalId => Principal?.Identity?.IsAuthenticated == true ? IdOrNull : null;
}
