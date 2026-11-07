using System.Text.Json;
using Vilep.Api.Domain;
using Xunit;

namespace Vilep.Tests;

public class ContributionFlowTests : IClassFixture<VilepFactory>
{
    private readonly VilepFactory _factory;
    private readonly HttpClient _client;

    public ContributionFlowTests(VilepFactory factory)
    {
        _factory = factory;
        _client = factory.Client();
    }

    private static string Phone() => "09" + Random.Shared.Next(10000000, 99999999);

    [Fact]
    public async Task Duplicate_webhook_credits_only_once()
    {
        var debtor = await _client.NewUserWithKyc(Phone());
        var (caseId, _) = await _client.NewFundingCase(debtor, 60_000);

        var donor = await _client.NewUserWithKyc(Phone());
        var created = await _client.Contribute(donor, caseId, 20_000, tip: 5_000);
        var contributionId = created.GetProperty("contributionId").GetString()!;

        var first = await _client.Pay(donor, contributionId);
        Assert.Equal(20_000, first.GetProperty("credited").GetInt64());

        var second = await _client.Pay(donor, contributionId);
        var third = await _client.Pay(donor, contributionId);
        Assert.True(second.GetProperty("duplicate").GetBoolean());
        Assert.True(third.GetProperty("duplicate").GetBoolean());
        Assert.Equal(0, second.GetProperty("credited").GetInt64());

        var detail = await _client.Get($"/api/v1/cases/{caseId}");
        Assert.Equal(20_000, detail.GetProperty("raisedAmount").GetInt64());

        var tipBalance = _factory.WithDb(db =>
            db.LedgerEntries.Where(e => e.CreditAccount == LedgerAccounts.PlatformTip).Sum(e => e.Amount));
        Assert.Equal(5_000, tipBalance);
    }

    [Fact]
    public async Task Contribution_above_remaining_is_rejected()
    {
        var debtor = await _client.NewUserWithKyc(Phone());
        var (caseId, _) = await _client.NewFundingCase(debtor, 30_000);

        var donor = await _client.NewUserWithKyc(Phone());
        var first = await _client.Contribute(donor, caseId, 20_000);
        await _client.Pay(donor, first.GetProperty("contributionId").GetString()!);

        var error = await Assert.ThrowsAsync<ApiCallException>(() => _client.Contribute(donor, caseId, 20_000));
        Assert.True(error.Status is 400 or 409, error.Message);

        var detail = await _client.Get($"/api/v1/cases/{caseId}");
        Assert.Equal(20_000, detail.GetProperty("raisedAmount").GetInt64());
        Assert.Equal(66, detail.GetProperty("percent").GetInt32());
    }

    [Fact]
    public async Task Self_contribution_is_forbidden()
    {
        var debtor = await _client.NewUserWithKyc(Phone());
        var (caseId, _) = await _client.NewFundingCase(debtor, 50_000);

        var error = await Assert.ThrowsAsync<ApiCallException>(() => _client.Contribute(debtor, caseId, 10_000));
        Assert.Equal(403, error.Status);
    }

    [Fact]
    public async Task Funding_case_creates_single_payout_and_zero_escrow()
    {
        var debtor = await _client.NewUserWithKyc(Phone());
        var (caseId, creditorToken) = await _client.NewFundingCase(debtor, 40_000);

        var donor = await _client.NewUserWithKyc(Phone());
        var contribution = await _client.Contribute(donor, caseId, 40_000);
        var paid = await _client.Pay(donor, contribution.GetProperty("contributionId").GetString()!);
        Assert.Contains(paid.GetProperty("caseState").GetString(), new[] { "paid", "closed" });

        // Duplicate webhook must not create a second payout nor pay twice.
        await _client.Pay(donor, contribution.GetProperty("contributionId").GetString()!);

        var payouts = _factory.WithDb(db => db.Payouts.Count(p => p.CaseId == Guid.Parse(caseId)));
        Assert.Equal(1, payouts);

        var adminToken = await _factory.AdminToken(_client);
        var ledger = await _client.Get($"/api/v1/admin/cases/{caseId}/ledger", adminToken);
        Assert.Equal(0, ledger.GetProperty("escrowBalance").GetInt64());

        var received = await _client.Post($"/api/v1/creditor/{creditorToken}/received", new { });
        Assert.Equal("closed", received.GetProperty("state").GetString());

        var invariants = await _client.Get("/api/v1/admin/invariants", adminToken);
        Assert.True(invariants.GetProperty("ok").GetBoolean(), invariants.ToString());
    }

    [Fact]
    public async Task Expired_case_refunds_every_contribution()
    {
        var debtor = await _client.NewUserWithKyc(Phone());
        var (caseId, _) = await _client.NewFundingCase(debtor, 100_000);

        var donor = await _client.NewUserWithKyc(Phone());
        var contribution = await _client.Contribute(donor, caseId, 25_000);
        await _client.Pay(donor, contribution.GetProperty("contributionId").GetString()!);

        // Move the deadline into the past, then run the reconciliation job like the hourly scheduler would.
        _factory.WithDb(db =>
        {
            var entity = db.Cases.First(c => c.Id == Guid.Parse(caseId));
            entity.Deadline = DateTimeOffset.UtcNow.AddMinutes(-5);
        });

        var adminToken = await _factory.AdminToken(_client);
        await _client.Post("/api/v1/admin/jobs/run", new { }, adminToken);

        var detail = await _client.Get($"/api/v1/cases/{caseId}");
        Assert.Equal("refunded", detail.GetProperty("state").GetString());

        var refunds = _factory.WithDb(db => db.Refunds.Count(r => r.CaseId == Guid.Parse(caseId) && r.State == "done"));
        Assert.Equal(1, refunds);

        var invariants = await _client.Get("/api/v1/admin/invariants", adminToken);
        Assert.True(invariants.GetProperty("ok").GetBoolean(), invariants.ToString());
    }

    [Fact]
    public async Task Creditor_confirmation_moves_case_to_funding()
    {
        var debtor = await _client.NewUserWithKyc(Phone());
        var (caseId, _) = await _client.NewFundingCase(debtor, 45_000);

        var detail = await _client.Get($"/api/v1/cases/{caseId}");
        Assert.Equal("funding", detail.GetProperty("state").GetString());
        Assert.Equal("creditor", detail.GetProperty("payoutMode").GetString());
        Assert.True(detail.GetProperty("creditorConfirmed").GetBoolean());
    }

    [Fact]
    public async Task Idempotency_key_replays_the_same_contribution()
    {
        var debtor = await _client.NewUserWithKyc(Phone());
        var (caseId, _) = await _client.NewFundingCase(debtor, 60_000);
        var donor = await _client.NewUserWithKyc(Phone());

        var key = Guid.NewGuid().ToString();
        var first = await _client.Post($"/api/v1/cases/{caseId}/contributions",
            new { amount = 15_000, tipAmount = 0 }, donor, key);
        var second = await _client.Post($"/api/v1/cases/{caseId}/contributions",
            new { amount = 15_000, tipAmount = 0 }, donor, key);

        Assert.Equal(
            first.GetProperty("created").GetProperty("contributionId").GetString(),
            second.GetProperty("created").GetProperty("contributionId").GetString());

        var count = _factory.WithDb(db => db.Contributions.Count(x => x.CaseId == Guid.Parse(caseId)));
        Assert.Equal(1, count);
    }
}

public class StateMachineTests
{
    [Theory]
    [InlineData(CaseStates.Funding, CaseStates.Funded)]
    [InlineData(CaseStates.Funded, CaseStates.PayoutPending)]
    [InlineData(CaseStates.PayoutPending, CaseStates.Paid)]
    [InlineData(CaseStates.Paid, CaseStates.Closed)]
    [InlineData(CaseStates.Funding, CaseStates.Expired)]
    [InlineData(CaseStates.Expired, CaseStates.Refunding)]
    [InlineData(CaseStates.Refunding, CaseStates.Refunded)]
    public void Mode_a_allows_expected_transitions(string from, string to) =>
        Assert.True(CaseStateMachine.CanTransition(PayoutModes.Creditor, from, to));

    [Theory]
    [InlineData(CaseStates.Funding, CaseStates.Closed)]
    [InlineData(CaseStates.Paid, CaseStates.Funding)]
    [InlineData(CaseStates.Closed, CaseStates.Funding)]
    [InlineData(CaseStates.Cancelled, CaseStates.Funding)]
    public void Mode_a_rejects_invalid_transitions(string from, string to) =>
        Assert.False(CaseStateMachine.CanTransition(PayoutModes.Creditor, from, to));

    [Fact]
    public void Funding_does_not_expire_in_mode_b() =>
        Assert.False(CaseStateMachine.CanTransition(PayoutModes.Debtor, CaseStates.Funding, CaseStates.Expired));

    [Fact]
    public void Mode_b_ends_instead_of_expiring() =>
        Assert.True(CaseStateMachine.CanTransition(PayoutModes.Debtor, CaseStates.Funding, CaseStates.Ended));

    [Fact]
    public void Same_state_is_never_a_transition() =>
        Assert.False(CaseStateMachine.CanTransition(PayoutModes.Creditor, CaseStates.Funding, CaseStates.Funding));
}
