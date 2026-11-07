using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using Vilep.Api.Domain;

namespace Vilep.Api.Data;

public class VilepDbContext : DbContext
{
    public VilepDbContext(DbContextOptions<VilepDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<OtpCode> OtpCodes => Set<OtpCode>();
    public DbSet<KycProfile> KycProfiles => Set<KycProfile>();
    public DbSet<BankAccount> BankAccounts => Set<BankAccount>();
    public DbSet<Creditor> Creditors => Set<Creditor>();
    public DbSet<Case> Cases => Set<Case>();
    public DbSet<Contribution> Contributions => Set<Contribution>();
    public DbSet<PaymentTransaction> PaymentTransactions => Set<PaymentTransaction>();
    public DbSet<LedgerEntry> LedgerEntries => Set<LedgerEntry>();
    public DbSet<Payout> Payouts => Set<Payout>();
    public DbSet<Refund> Refunds => Set<Refund>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<Report> Reports => Set<Report>();
    public DbSet<AppConfig> AppConfigs => Set<AppConfig>();
    public DbSet<Blacklist> Blacklists => Set<Blacklist>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>(e =>
        {
            e.ToTable("users");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Phone).IsUnique();
            e.Property(x => x.Phone).HasMaxLength(20).IsRequired();
            e.Property(x => x.Nickname).HasMaxLength(60);
            e.Property(x => x.Role).HasMaxLength(20);
        });

        b.Entity<RefreshToken>(e =>
        {
            e.ToTable("refresh_tokens");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.TokenHash).IsUnique();
            e.HasIndex(x => x.UserId);
        });

        b.Entity<OtpCode>(e =>
        {
            e.ToTable("otp_codes");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.Phone, x.CreatedAt });
        });

        b.Entity<KycProfile>(e =>
        {
            e.ToTable("kyc_profiles");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.UserId);
            e.HasIndex(x => x.IdNumberHash);
        });

        b.Entity<BankAccount>(e =>
        {
            e.ToTable("bank_accounts");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.OwnerType, x.OwnerId });
        });

        b.Entity<Creditor>(e =>
        {
            e.ToTable("creditors");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.ContactToken).IsUnique();
        });

        b.Entity<Case>(e =>
        {
            e.ToTable("cases");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Code).IsUnique();
            e.HasIndex(x => new { x.State, x.PayoutMode, x.CreatedAt });
            e.HasIndex(x => x.DebtorId);
            e.HasOne(x => x.Debtor).WithMany().HasForeignKey(x => x.DebtorId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Creditor).WithMany().HasForeignKey(x => x.CreditorId).OnDelete(DeleteBehavior.SetNull);
            e.Property(x => x.Version).IsConcurrencyToken();
            e.Property(x => x.Title).HasMaxLength(120).IsRequired();
            e.Property(x => x.Story).HasMaxLength(4000);
            e.Property(x => x.State).HasMaxLength(30);
            e.Property(x => x.PayoutMode).HasMaxLength(20);
            e.Property(x => x.Branch).HasMaxLength(20);
        });

        b.Entity<Contribution>(e =>
        {
            e.ToTable("contributions");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.IdempotencyKey).IsUnique();
            e.HasIndex(x => new { x.CaseId, x.State });
            e.HasIndex(x => x.ContributorId);
            e.HasOne(x => x.Contributor).WithMany().HasForeignKey(x => x.ContributorId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Case).WithMany(c => c.Contributions).HasForeignKey(x => x.CaseId).OnDelete(DeleteBehavior.Cascade);
            e.Property(x => x.State).HasMaxLength(20);
        });

        b.Entity<PaymentTransaction>(e =>
        {
            e.ToTable("payment_transactions");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.Provider, x.ProviderRef }).IsUnique();
            e.HasIndex(x => x.ContributionId);
        });

        b.Entity<LedgerEntry>(e =>
        {
            e.ToTable("ledger_entries");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.IdempotencyKey).IsUnique();
            e.HasIndex(x => x.CaseId);
            e.HasIndex(x => x.CreatedAt);
        });

        b.Entity<Payout>(e =>
        {
            e.ToTable("payouts");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.CaseId);
            e.HasIndex(x => x.State);
        });

        b.Entity<Refund>(e =>
        {
            e.ToTable("refunds");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.ContributionId);
            e.HasIndex(x => x.CaseId);
        });

        b.Entity<Notification>(e =>
        {
            e.ToTable("notifications");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.UserId, x.CreatedAt });
        });

        b.Entity<AuditLog>(e =>
        {
            e.ToTable("audit_logs");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.EntityType, x.EntityId });
            e.HasIndex(x => x.At);
        });

        b.Entity<Report>(e =>
        {
            e.ToTable("reports");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.State);
        });

        b.Entity<AppConfig>(e =>
        {
            e.ToTable("app_config");
            e.HasKey(x => x.Key);
        });

        b.Entity<Blacklist>(e =>
        {
            e.ToTable("blacklists");
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.Type, x.ValueHash });
        });

        // SQLite has no native DateTimeOffset type; store it as an order-preserving binary long
        // so ORDER BY / comparisons still work locally. Postgres keeps timestamptz natively.
        if (Database.ProviderName?.Contains("Sqlite", StringComparison.OrdinalIgnoreCase) == true)
        {
            var converter = new Microsoft.EntityFrameworkCore.Storage.ValueConversion.DateTimeOffsetToBinaryConverter();
            foreach (var entity in b.Model.GetEntityTypes())
            {
                foreach (var prop in entity.GetProperties())
                {
                    var type = Nullable.GetUnderlyingType(prop.ClrType) ?? prop.ClrType;
                    if (type == typeof(DateTimeOffset)) prop.SetValueConverter(converter);
                }
            }
        }

        foreach (var entity in b.Model.GetEntityTypes())
        {
            var table = entity.GetTableName();
            if (table is null) continue;
            foreach (var prop in entity.GetProperties())
            {
                var column = prop.GetColumnName(StoreObjectIdentifier.Table(table, entity.GetSchema()));
                if (column is null) continue;
                prop.SetColumnName(ToSnakeCase(column));
            }
        }
    }

    private static string ToSnakeCase(string name)
    {
        if (string.IsNullOrEmpty(name)) return name;
        var sb = new System.Text.StringBuilder(name.Length + 8);
        for (var i = 0; i < name.Length; i++)
        {
            var c = name[i];
            if (char.IsUpper(c))
            {
                if (i > 0 && (char.IsLower(name[i - 1]) || (i + 1 < name.Length && char.IsLower(name[i + 1]))))
                    sb.Append('_');
                sb.Append(char.ToLowerInvariant(c));
            }
            else sb.Append(c);
        }
        return sb.ToString();
    }
}
