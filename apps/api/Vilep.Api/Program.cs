using System.Security.Claims;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Http.Json;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Vilep.Api.Data;
using Vilep.Api.Domain;
using Vilep.Api.Features;
using Vilep.Api.Features.Accounts;
using Vilep.Api.Features.Admin;
using Vilep.Api.Features.Cases;
using Vilep.Api.Features.Payments;
using Vilep.Api.Features.Social;
using Vilep.Api.Infrastructure;
using Vilep.Api.Jobs;
using Vilep.Api.Services;

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

builder.Services.Configure<DatabaseOptions>(config.GetSection("Database"));
builder.Services.Configure<JwtOptions>(config.GetSection("Jwt"));
builder.Services.Configure<PaymentOptions>(config.GetSection("Payments"));
builder.Services.Configure<VilepOptions>(config.GetSection("Vilep"));
builder.Services.Configure<SeedOptions>(config.GetSection("Seed"));
builder.Services.AddSingleton(TimeProvider.System);
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(o => o.SingleLine = false);
builder.Services.AddHttpContextAccessor();

var database = config.GetSection("Database").Get<DatabaseOptions>() ?? new DatabaseOptions();
var dataDir = Path.Combine(AppContext.BaseDirectory, "App_Data");
Directory.CreateDirectory(dataDir);
if (database.Provider.Equals("sqlite", StringComparison.OrdinalIgnoreCase))
    database.ConnectionString = database.ConnectionString.Replace("{DataDir}", dataDir);

builder.Services.AddDbContext<VilepDbContext>(options =>
{
    if (database.Provider.Equals("postgres", StringComparison.OrdinalIgnoreCase))
        options.UseNpgsql(database.ConnectionString, npgsql => npgsql.EnableRetryOnFailure(3));
    else
        options.UseSqlite(database.ConnectionString);
});



var jwt = config.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
{
    options.MapInboundClaims = false;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwt.Issuer,
        ValidAudience = jwt.Audience,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Key)),
        RoleClaimType = "role",
        NameClaimType = "sub",
        ClockSkew = TimeSpan.FromSeconds(30)
    };
});
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("admin", policy => policy.RequireAuthenticatedUser().RequireRole("admin"));
});

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy => policy
        .AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("otp", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "anon",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 12, Window = TimeSpan.FromMinutes(1) }));
    options.AddPolicy("money", context => RateLimitPartition.GetFixedWindowLimiter(
        context.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? context.Connection.RemoteIpAddress?.ToString() ?? "anon",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 30, Window = TimeSpan.FromMinutes(1) }));
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddSingleton<Encryptor>();
builder.Services.AddScoped<TokenService>();
builder.Services.AddScoped<CurrentUser>();
builder.Services.AddScoped<LedgerService>();
builder.Services.AddScoped<NotificationService>();
builder.Services.AddScoped<CaseWorkflow>();
builder.Services.AddScoped<ConfigService>();
builder.Services.AddScoped<ContributionService>();
builder.Services.AddScoped<PayoutService>();
builder.Services.AddScoped<RefundService>();
builder.Services.AddScoped<JobsRunner>();

var paymentProvider = config.GetSection("Payments:Provider").Get<string>() ?? "mock";
if (paymentProvider.Equals("payos", StringComparison.OrdinalIgnoreCase))
{
    builder.Services.AddHttpClient<IPaymentGateway, PayOsPaymentGateway>();
}
else
{
    builder.Services.AddSingleton<IPaymentGateway, MockPaymentGateway>();
}

builder.Services.AddHostedService<JobsHostedService>();

var app = builder.Build();

app.UseMiddleware<ApiExceptionMiddleware>();
app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

if (app.Environment.IsDevelopment() || config.GetValue("Swagger:Enabled", true))
{
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "Ví Lép API v1");
        options.RoutePrefix = "swagger";
    });
}

app.MapGet("/", () => Results.Content("""
<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ví Lép API</title>
<style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F7F7F5;color:#111;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
.card{background:#fff;padding:40px;border-radius:24px;box-shadow:0 12px 40px rgba(0,0,0,.08);max-width:520px}
h1{margin:0 0 8px;font-size:28px}.tag{color:#05CE78;font-weight:800;letter-spacing:.08em;font-size:12px}
a{color:#05CE78;font-weight:700;text-decoration:none}li{margin:6px 0}code{background:#F1F7F4;padding:2px 6px;border-radius:6px}</style>
</head><body><div class="card"><div class="tag">VÍ LÉP · MVP API</div><h1>Ví lép, bạn bè lo!</h1>
<p>API đang chạy. Mở <a href="/swagger">/swagger</a> để xem hợp đồng OpenAPI.</p>
<ul><li>OTP dev: <code>POST /api/v1/auth/otp/request</code> trả mã trong <code>devCode</code></li>
<li>Demo: <code>0900000001</code> (con nợ), <code>0900000002</code> (người góp), <code>0900000003</code> (admin)</li></ul>
</div></body></html>
""", "text/html; charset=utf-8")).AllowAnonymous();

app.MapGet("/health", () => Results.Json(new { ok = true, service = "vilep-api", utc = DateTimeOffset.UtcNow })).AllowAnonymous();

app.MapAccountEndpoints();
app.MapCaseEndpoints();
app.MapPaymentEndpoints();
app.MapSocialEndpoints();
app.MapAdminEndpoints();

await DbInitializer.InitializeAsync(app.Services, app.Logger);

app.Run();

public partial class Program { }
