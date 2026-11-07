namespace Vilep.Api.Infrastructure;

public class DatabaseOptions
{
    public string Provider { get; set; } = "sqlite"; // sqlite | postgres
    public string ConnectionString { get; set; } = "Data Source=App_Data/vilep.db";
}

public class JwtOptions
{
    public string Issuer { get; set; } = "vilep";
    public string Audience { get; set; } = "vilep-app";
    public string Key { get; set; } = "dev-only-change-me-0123456789abcdef0123456789abcdef";
    public int AccessMinutes { get; set; } = 120;
    public int RefreshDays { get; set; } = 30;
}

public class PaymentOptions
{
    public string Provider { get; set; } = "mock"; // mock | payos
    public string WebhookSecret { get; set; } = "dev-webhook-secret-change-me";
    public string ClientId { get; set; } = "";
    public string ApiKey { get; set; } = "";
    public string ChecksumKey { get; set; } = "";
    public string BaseUrl { get; set; } = "https://api-merchant.payos.vn";
    public long AutoApprovePayoutLimit { get; set; } = 500_000;
    public int ProcessingFeeBps { get; set; } = 0;
    public int TipSuggestPercent { get; set; } = 5;
}

public class VilepOptions
{
    public long MinContribution { get; set; } = 10_000;
    public long FunModeAMin { get; set; } = 20_000;
    public long FunModeAMax { get; set; } = 500_000;
    public long FunModeBMax { get; set; } = 300_000;
    public int CreditorInviteHours { get; set; } = 72;
    public int MaxActiveCasesModeA { get; set; } = 2;
    public int MaxActiveCasesModeB { get; set; } = 1;
    public int DefaultFundraisingDays { get; set; } = 30;
    public int HoldDays { get; set; } = 3;
    public string BaseUrl { get; set; } = "http://localhost:5080";
    public string PublicAppUrl { get; set; } = "http://localhost:5080/share";
    public bool ExposeOtpInResponse { get; set; } = true;
    public bool AutoVerifyKyc { get; set; } = true;
    public bool EnableDevPayments { get; set; } = true;
    public string DevSimulateSecret { get; set; } = "dev-simulate";
}

public class SeedOptions
{
    public bool Enabled { get; set; } = true;
}
