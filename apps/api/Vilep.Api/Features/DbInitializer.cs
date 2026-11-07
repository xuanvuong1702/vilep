using Microsoft.EntityFrameworkCore;
using Vilep.Api.Data;
using Vilep.Api.Domain;
using Vilep.Api.Infrastructure;
using Vilep.Api.Services;

namespace Vilep.Api.Features;

public static class DbInitializer
{
    public static async Task InitializeAsync(IServiceProvider services, ILogger logger)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<VilepDbContext>();
        var encryptor = scope.ServiceProvider.GetRequiredService<Encryptor>();
        var config = scope.ServiceProvider.GetRequiredService<IConfiguration>();

        await db.Database.EnsureCreatedAsync();
        await ApplyAppendOnlyTriggersAsync(db, logger);

        if (config.GetValue("Seed:Enabled", true))
            await SeedData.RunAsync(db, encryptor, logger);
    }

    private static async Task ApplyAppendOnlyTriggersAsync(VilepDbContext db, ILogger logger)
    {
        try
        {
            if (db.Database.IsSqlite())
            {
                await db.Database.ExecuteSqlRawAsync("""
                    CREATE TRIGGER IF NOT EXISTS ledger_entries_no_update
                    BEFORE UPDATE ON ledger_entries
                    BEGIN SELECT RAISE(ABORT, 'ledger_entries is append-only'); END;
                    """);
                await db.Database.ExecuteSqlRawAsync("""
                    CREATE TRIGGER IF NOT EXISTS ledger_entries_no_delete
                    BEFORE DELETE ON ledger_entries
                    BEGIN SELECT RAISE(ABORT, 'ledger_entries is append-only'); END;
                    """);
            }
            else if (db.Database.IsNpgsql())
            {
                await db.Database.ExecuteSqlRawAsync("""
                    CREATE OR REPLACE FUNCTION vilep_ledger_immutable() RETURNS trigger AS $$
                    BEGIN RAISE EXCEPTION 'ledger_entries is append-only'; END;
                    $$ LANGUAGE plpgsql;
                    """);
                await db.Database.ExecuteSqlRawAsync("DROP TRIGGER IF EXISTS ledger_entries_immutable ON ledger_entries;");
                await db.Database.ExecuteSqlRawAsync("""
                    CREATE TRIGGER ledger_entries_immutable BEFORE UPDATE OR DELETE ON ledger_entries
                    FOR EACH ROW EXECUTE FUNCTION vilep_ledger_immutable();
                    """);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Could not install ledger append-only triggers");
        }
    }
}

public static class SeedData
{
    public static async Task RunAsync(VilepDbContext db, Encryptor encryptor, ILogger logger)
    {
        if (await db.Users.AnyAsync()) return;

        var now = DateTimeOffset.UtcNow;

        User U(string phone, string nick, string avatar, int kyc, string bio, bool admin = false) => new()
        {
            Phone = phone,
            Nickname = nick,
            AvatarKey = avatar,
            KycTier = kyc,
            AgeVerified = true,
            Bio = bio,
            Role = admin ? "admin" : "user",
            CreatedAt = now.AddDays(-60)
        };

        var minh = U("0900000001", "Minh Anh", "wallet-2", KycTiers.Full, "Sinh viên năm 3, chuyên gia hết tiền trước cuối tháng.");
        var lan = U("0900000002", "Lan Nhi", "wallet-3", KycTiers.Light, "Hay cứu bạn, ví cũng hay lép.");
        var admin = U("0900000003", "Admin Ví Lép", "wallet-1", KycTiers.Full, "Đội vận hành Ví Lép.", admin: true);
        var hung = U("0900000004", "Hùng Cò", "wallet-4", KycTiers.Light, "Bạn nhậu chính thức của Minh.");
        var mai = U("0900000005", "Mai Mập", "wallet-5", KycTiers.Light, "Nghiện trà sữa, cứu người như cứu mình.");
        var tuan = U("0900000006", "Tuấn Tí", "wallet-6", KycTiers.Light, "Chơi bóng đá, thua kèo nhiều hơn thắng.");

        db.Users.AddRange(minh, lan, admin, hung, mai, tuan);
        await db.SaveChangesAsync();

        db.KycProfiles.AddRange(
            new KycProfile { UserId = minh.Id, IdNumberHash = Hash.Sha256("079200001234"), FullName = "NGUYEN MINH ANH", Tier = 2, Status = "verified", VerifiedAt = now.AddDays(-40), ProviderRef = "seed" },
            new KycProfile { UserId = lan.Id, IdNumberHash = Hash.Sha256("079200005678"), FullName = "TRAN LAN NHI", Tier = 1, Status = "verified", VerifiedAt = now.AddDays(-30), ProviderRef = "seed" },
            new KycProfile { UserId = admin.Id, IdNumberHash = Hash.Sha256("079200009999"), FullName = "VI LEP OPS", Tier = 2, Status = "verified", VerifiedAt = now.AddDays(-90), ProviderRef = "seed" });
        await db.SaveChangesAsync();

        var ledger = new LedgerService(db);
        var contributors = new[] { lan, hung, mai, tuan };
        var random = new Random(20261107);

        async Task<Creditor> MakeCreditorAsync(string name, string phone, string bank, string accountNo, string accountName)
        {
            var account = new BankAccount
            {
                OwnerType = "creditor",
                OwnerId = Guid.NewGuid(),
                BankCode = bank,
                AccountNoLast4 = encryptor.Last4(accountNo),
                AccountName = accountName,
                NameMatchedKyc = true,
                Verified = true
            };
            account.AccountNoEnc = encryptor.Encrypt(accountNo);

            var creditor = new Creditor
            {
                Name = name,
                Phone = phone,
                ContactToken = Hash.ShortCode(10),
                ConfirmedAt = now.AddDays(-random.Next(2, 20)),
                InviteExpiresAt = now.AddDays(3),
                BankAccountId = account.Id
            };
            account.OwnerId = creditor.Id;
            db.Creditors.Add(creditor);
            db.BankAccounts.Add(account);
            return creditor;
        }

        Case NewCase(string code, User debtor, string title, string story, string category, long target, long debt, int daysLeft)
        {
            var c = new Case
            {
                Code = code,
                Branch = Branches.Fun,
                PayoutMode = PayoutModes.Creditor,
                DebtorId = debtor.Id,
                Title = title,
                Story = story,
                Category = category,
                TargetAmount = target,
                DebtAmount = debt,
                State = CaseStates.Funding,
                Deadline = now.AddDays(daysLeft),
                PublishedAt = now.AddDays(-random.Next(1, 10)),
                CreatedAt = now.AddDays(-random.Next(2, 14)),
                DisplayMode = DisplayModes.Nickname,
                HoldDays = 3
            };
            db.Cases.Add(c);
            return c;
        }

        void Fill(Case c, IReadOnlyList<long> amounts, int daysAgoStart = 8)
        {
            var i = 0;
            var pool = contributors.Where(x => x.Id != c.DebtorId).ToArray();
            foreach (var amount in amounts)
            {
                var contributor = pool[i % pool.Length];
                var paidAt = now.AddDays(-Math.Max(0, daysAgoStart - i)).AddHours(-i);
                var contribution = new Contribution
                {
                    CaseId = c.Id,
                    ContributorId = contributor.Id,
                    Amount = amount,
                    State = ContributionStates.Succeeded,
                    Anonymous = i % 5 == 3,
                    Message = Messages[(i + c.Code.Length) % Messages.Length],
                    Sticker = i % 4 == 0 ? "🧋" : null,
                    IdempotencyKey = $"seed:{c.Code}:{i}",
                    CreatedAt = paidAt,
                    PaidAt = paidAt
                };
                db.Contributions.Add(contribution);
                ledger.Post(c.Id, "contribution", contribution.Id, LedgerAccounts.GatewayClearing, LedgerAccounts.CaseEscrow,
                    amount, $"contrib:{contribution.Id}:escrow");
                c.RaisedAmount += amount;
                i++;
            }
        }

        var c1 = NewCase("trasua01", minh, "Cứu mình ly trà sữa cuối tháng",
            "Tháng này mình uống trà sữa hơi nhiều, đến hôm nay nhìn ví chỉ còn 12.000đ. Không dám xin mẹ, chỉ dám nhờ bạn bè cứu. Hứa tháng sau bớt 2 ly/tuần!",
            "tra-sua", 45_000, 45_000, 12);
        c1.CreditorId = (await MakeCreditorAsync("Quán Trà Sữa Nhà Lá", "0912000111", "VCB", "0123456789", "QUAN TRA SUA NHA LA")).Id;
        Fill(c1, new long[] { 10_000, 15_000, 5_000 });

        var c2 = NewCase("nhau01", hung, "Nợ tiền nhậu trận chung kết",
            "Trận chung kết mình hứa bao cả bàn, ai ngờ hoá đơn cao hơn dự tính. Bị trêu cả tuần rồi, mọi người cứu mình trả nợ với. Đổi lại mình hát bài 'Ví lép' trong buổi nhậu tới!",
            "nhau", 250_000, 320_000, 8);
        c2.CreditorId = (await MakeCreditorAsync("Quán Ốc Bà Tư", "0912000222", "TCB", "9876543210", "QUAN OC BA TU")).Id;
        Fill(c2, new long[] { 50_000, 50_000, 70_000, 50_000 }, 6);

        var c3 = NewCase("cacuoc01", tuan, "Thua kèo bóng, xin cứu ví",
            "Kèo này mình thua thật, chấp nhận bị trêu là 'chuyên gia thua kèo'. Ai cứu giúp mình trả nợ, mình xin tự nguyện làm bản kiểm điểm 500 chữ đọc trước lớp.",
            "ca-cuoc", 300_000, 300_000, 20);
        c3.CreditorId = (await MakeCreditorAsync("Anh Bảy Cáp Kèo", "0912000333", "ACB", "1122334455", "TRAN VAN BAY")).Id;
        Fill(c3, new long[] { 30_000, 20_000, 100_000 }, 9);

        var c4 = NewCase("anuong01", mai, "Mượn tiền ăn trưa cả tuần",
            "Chuyển tiền nhà trọ xong là ví lép toàn tập, còn đúng 20.000đ. Mượn mọi người tiền ăn trưa vài bữa, có lương trả ngay và trả thêm ly trà sữa cảm ơn.",
            "an-uong", 100_000, 100_000, 15);
        c4.CreditorId = (await MakeCreditorAsync("Cô Hạnh Bán Cơm", "0912000444", "BIDV", "5566778899", "NGUYEN THI HANH")).Id;
        Fill(c4, new long[] { 20_000, 20_000, 10_000 });

        var c5 = NewCase("sinhnhat01", minh, "Nợ tiền quà sinh nhật bạn thân",
            "Mua quà sinh nhật cho bạn thân hơi quá tay, giờ nợ lại chính bạn ấy. Case này mình mở để mọi người cứu, và mình sẽ tặng bạn ấy thêm một bài thơ tự sáng tác.",
            "qua-sinh-nhat", 200_000, 200_000, 18);
        c5.CreditorId = (await MakeCreditorAsync("Bạn Thân Gia Hân", "0912000555", "MB", "0011223344", "LE GIA HAN")).Id;
        Fill(c5, new long[] { 40_000 });

        var c6 = NewCase("muontien01", tuan, "Trả nợ tiền mượn đúng hẹn",
            "Mình đã hứa trả bạn đúng hẹn mà ví lép quá. Mọi người cứu mình lần này, mình giữ chữ tín bằng việc quay video cảm ơn 15 giây gửi cả nhóm.",
            "muon-tien", 150_000, 150_000, 25);
        c6.CreditorId = (await MakeCreditorAsync("Chị Thảo Đồng Nghiệp", "0912000666", "TPB", "6677889900", "PHAM THU THAO")).Id;
        Fill(c6, new long[] { 40_000, 40_000, 40_000 }, 5);

        // --- Case fully funded → paid → closed (mode A happy path) ---
        var closedCase = NewCase("tet01", minh, "Sạch nợ đón Tết sớm",
            "Mục tiêu nhỏ thôi: trả hết nợ trà sữa trước Tết để về quê không bị hỏi 'dạo này có dư không con'. Cảm ơn cả nhà đã cứu!",
            "tra-sua", 120_000, 120_000, -3);
        closedCase.CreatedAt = now.AddDays(-20);
        closedCase.PublishedAt = now.AddDays(-20);
        var closedCreditor = await MakeCreditorAsync("Chị Chủ Quán Trà Sữa", "0912000777", "VCB", "2233445566", "NGUYEN THI CHU");
        closedCase.CreditorId = closedCreditor.Id;
        Fill(closedCase, new long[] { 40_000, 40_000, 40_000 }, 18);
        closedCase.State = CaseStates.Closed;
        closedCase.ClosedAt = now.AddDays(-16);

        var payout = new Payout
        {
            CaseId = closedCase.Id,
            CreditorId = closedCreditor.Id,
            Amount = 120_000,
            State = PayoutStates.Paid,
            ProviderRef = "PAYOUT-SEED-0001",
            ReceiptKey = "receipt/seed-0001.png",
            CreatedAt = now.AddDays(-17),
            PaidAt = now.AddDays(-17),
            CreditorConfirmedAt = now.AddDays(-16)
        };
        db.Payouts.Add(payout);
        ledger.Post(closedCase.Id, "payout", payout.Id, LedgerAccounts.CaseEscrow, LedgerAccounts.CreditorPayoutClearing,
            120_000, $"payout:{payout.Id}:transfer");

        // --- Case expired and fully refunded ---
        var expiredCase = NewCase("hethan01", hung, "Nợ tiền sinh nhật mẹ",
            "Mình định tổ chức sinh nhật nho nhỏ cho mẹ, tiếc là case không kịp đủ. Cảm ơn mọi người đã định giúp, mình xin hoàn lại hết.",
            "khac", 200_000, 200_000, -2);
        expiredCase.CreatedAt = now.AddDays(-35);
        expiredCase.PublishedAt = now.AddDays(-35);
        expiredCase.CreditorId = (await MakeCreditorAsync("Chị Hàng Xóm Cô Hoa", "0912000888", "VCB", "3344556677", "NGUYEN THI HOA")).Id;
        Fill(expiredCase, new long[] { 30_000, 30_000 }, 33);
        expiredCase.State = CaseStates.Refunded;
        expiredCase.ClosedAt = now.AddDays(-1);

        var expiredContributions = await db.Contributions.Where(x => x.CaseId == expiredCase.Id).ToListAsync();
        foreach (var contribution in expiredContributions)
        {
            var refund = new Refund
            {
                ContributionId = contribution.Id,
                CaseId = expiredCase.Id,
                Amount = contribution.Amount,
                State = RefundStates.Done,
                Reason = "case_expired",
                ProviderRef = "REFUND-SEED-" + contribution.Id.ToString("N")[..6].ToUpperInvariant(),
                CreatedAt = now.AddDays(-1),
                DoneAt = now.AddDays(-1)
            };
            db.Refunds.Add(refund);
            ledger.Post(expiredCase.Id, "refund", refund.Id, LedgerAccounts.CaseEscrow, LedgerAccounts.RefundClearing,
                refund.Amount, $"refund:{refund.Id}:transfer");
            contribution.State = ContributionStates.Refunded;
        }
        expiredCase.RaisedAmount = 0;

        // --- Case waiting for creditor confirmation (demo of the invite link) ---
        var pending = new Case
        {
            Code = "caphe01",
            Branch = Branches.Fun,
            PayoutMode = PayoutModes.Creditor,
            DebtorId = mai.Id,
            Title = "Nợ cà phê sáng cả tháng",
            Story = "Sáng nào cũng ghé quán cô Lan, ghi sổ cả tháng. Giờ cô hỏi nhẹ một câu mà mình áp lực ghê. Cứu mình trả sổ cà phê với!",
            Category = "an-uong",
            TargetAmount = 90_000,
            DebtAmount = 90_000,
            State = CaseStates.PendingCreditor,
            Deadline = now.AddDays(30),
            CreatedAt = now.AddDays(-1),
            PublishedAt = now.AddDays(-1),
            DisplayMode = DisplayModes.Nickname
        };
        var pendingCreditor = new Creditor
        {
            Name = "Cô Lan Quán Cà Phê",
            Phone = "0912000999",
            ContactToken = "demo-caphe",
            InviteExpiresAt = now.AddHours(70)
        };
        db.Creditors.Add(pendingCreditor);
        pending.CreditorId = pendingCreditor.Id;
        db.Cases.Add(pending);

        db.Notifications.AddRange(
            new Notification { UserId = minh.Id, Type = "welcome", Title = "Chào mừng tới Ví Lép 👛", Body = "Ví lép, bạn bè lo! Bắt đầu bằng việc kể một khoản nợ vui.", CreatedAt = now.AddDays(-20) },
            new Notification { UserId = minh.Id, Type = "contribution_new", Title = "Có người vừa cứu nợ 💚", Body = "Lan Nhi vừa góp 15.000đ cho case \"Cứu mình ly trà sữa cuối tháng\".", CreatedAt = now.AddDays(-2) },
            new Notification { UserId = minh.Id, Type = "case_closed", Title = "Case đã hoàn tất 🎉", Body = "Chủ nợ đã xác nhận nhận tiền cho case \"Sạch nợ đón Tết sớm\".", CreatedAt = now.AddDays(-16) });

        db.AuditLogs.Add(new AuditLog
        {
            ActorId = admin.Id,
            ActorRole = "admin",
            Action = "seed.loaded",
            EntityType = "system",
            EntityId = Guid.Empty,
            AfterJson = "{\"cases\":9}",
            At = now
        });

        await db.SaveChangesAsync();
        logger.LogInformation("Seeded Ví Lép demo data: 6 users, 9 cases");
    }

    private static readonly string[] Messages =
    {
        "Cứu ví lép, cứu luôn tuổi trẻ!",
        "Uống ly trà sữa này coi như cứu mình một bậc.",
        "Ví lép nhưng tình dày, cảm ơn bạn!",
        "Mai mốt có tiền mình mời lại nha 🧋",
        "Ai cũng có lúc lép ví, cảm ơn bạn rất nhiều.",
        "Góp chút cho vui, đừng buồn nha!",
        "Chốt hạ! Ví phồng lên rồi 🎉",
        "Mình cũng từng lép, hiểu mà."
    };
}
