using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Vilep.Api.Data;

namespace Vilep.Tests;

/// <summary>
/// Spins up the real API against a throw-away SQLite file so the money paths
/// (ledger, webhook idempotency, payout, refund) are exercised end to end.
/// </summary>
public class VilepFactory : WebApplicationFactory<Program>
{
    private static readonly string DataDir = Directory.CreateDirectory(Path.Combine(AppContext.BaseDirectory, "test-data")).FullName;
    private readonly string _dbPath = Path.Combine(DataDir, $"vilep-test-{Guid.NewGuid():N}.db");

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.UseSetting("Database:Provider", "sqlite");
        builder.UseSetting("Database:ConnectionString", $"Data Source={_dbPath}");
        builder.UseSetting("Seed:Enabled", "false");
        builder.UseSetting("Vilep:ExposeOtpInResponse", "true");
        builder.UseSetting("Vilep:EnableDevPayments", "true");
        builder.UseSetting("Jobs:IntervalSeconds", "3600");
    }

    public HttpClient Client() => CreateClient();

    public void WithDb(Action<VilepDbContext> action)
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<VilepDbContext>();
        action(db);
        db.SaveChanges();
    }

    public T WithDb<T>(Func<VilepDbContext, T> action)
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<VilepDbContext>();
        return action(db);
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        try
        {
            if (File.Exists(_dbPath)) File.Delete(_dbPath);
        }
        catch
        {
            // temp file cleanup is best effort
        }
    }
}

public static class Api
{
    public static async Task<JsonElement> Post(this HttpClient client, string url, object? body = null,
        string? token = null, string? idempotencyKey = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, url);
        if (body is not null) request.Content = JsonContent.Create(body);
        if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (idempotencyKey is not null) request.Headers.Add("Idempotency-Key", idempotencyKey);
        var response = await client.SendAsync(request);
        var raw = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(raw);
        var root = doc.RootElement.Clone();
        if (!response.IsSuccessStatusCode || !root.TryGetProperty("ok", out var ok) || ok.GetBoolean() == false)
        {
            var message = root.TryGetProperty("error", out var error) && error.TryGetProperty("message", out var m) ? m.GetString() : raw;
            throw new ApiCallException((int)response.StatusCode, message ?? raw);
        }
        return root.GetProperty("data").Clone();
    }

    public static async Task<JsonElement> Get(this HttpClient client, string url, string? token = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var response = await client.SendAsync(request);
        var raw = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(raw);
        var root = doc.RootElement.Clone();
        if (!response.IsSuccessStatusCode) throw new ApiCallException((int)response.StatusCode, raw);
        return root.GetProperty("data").Clone();
    }

    public static async Task<(string token, JsonElement user)> Login(this HttpClient client, string phone)
    {
        var otp = await client.Post("/api/v1/auth/otp/request", new { phone });
        var code = otp.GetProperty("devCode").GetString()!;
        var verified = await client.Post("/api/v1/auth/otp/verify", new { phone, code });
        return (verified.GetProperty("accessToken").GetString()!, verified.GetProperty("user").Clone());
    }

    public static async Task<string> NewUserWithKyc(this HttpClient client, string phone, int tier = 1)
    {
        var (token, _) = await client.Login(phone);
        await client.Post("/api/v1/me/kyc", new
        {
            tier,
            fullName = "NGUYEN VAN TEST",
            idNumber = "0792000" + Random.Shared.Next(10000, 99999),
            dob = "2000-01-01"
        }, token);
        return token;
    }

    /// <summary>Creates a user, promotes it to admin in the DB, then re-logs in so the JWT carries role=admin.</summary>
    public static async Task<string> AdminToken(this VilepFactory factory, HttpClient client, string? phone = null)
    {
        phone ??= "0900" + Random.Shared.Next(1000000, 9999999);
        await client.Login(phone);
        factory.WithDb(db =>
        {
            var user = db.Users.First(u => u.Phone == phone);
            user.Role = "admin";
        });
        var (token, _) = await client.Login(phone);
        return token;
    }

    public static async Task<(string caseId, string creditorToken)> NewFundingCase(this HttpClient client,
        string debtorToken, long target, string title = "Case kiểm thử đóng góp")
    {
        var created = await client.Post("/api/v1/my/cases", new
        {
            title,
            story = "Đây là case kiểm thử tự động, nội dung đủ dài để vượt qua kiểm tra tối thiểu 20 ký tự.",
            category = "tra-sua",
            debtAmount = target,
            targetAmount = target,
            displayMode = "nickname"
        }, debtorToken);
        var caseId = created.GetProperty("id").GetString()!;

        var invite = await client.Post($"/api/v1/my/cases/{caseId}/invite-creditor",
            new { name = "Chủ Nợ Kiểm Thử", phone = "0912000111" }, debtorToken);
        var token = invite.GetProperty("token").GetString()!;

        await client.Post($"/api/v1/creditor/invite/{token}/confirm",
            new { accountName = "CHU NO KIEM THU", bankCode = "VCB", accountNo = "0123456789" });
        return (caseId, token);
    }

    public static async Task<JsonElement> Contribute(this HttpClient client, string token, string caseId, long amount, long tip = 0)
    {
        var created = await client.Post($"/api/v1/cases/{caseId}/contributions",
            new { amount, tipAmount = tip, anonymous = false, message = "Test góp" }, token,
            idempotencyKey: Guid.NewGuid().ToString());
        return created.GetProperty("created");
    }

    public static async Task<JsonElement> Pay(this HttpClient client, string token, string contributionId) =>
        await client.Post($"/api/v1/dev/pay/{contributionId}", new { }, token);
}

public class ApiCallException : Exception
{
    public int Status { get; }

    public ApiCallException(int status, string message) : base(message) => Status = status;
}
