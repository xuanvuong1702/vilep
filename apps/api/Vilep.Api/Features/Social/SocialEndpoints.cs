using System.Net;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Vilep.Api.Data;
using Vilep.Api.Domain;
using Vilep.Api.Features.Cases;
using Vilep.Api.Infrastructure;
using Vilep.Api.Services;

namespace Vilep.Api.Features.Social;

public record ReportRequest(string TargetType, Guid TargetId, string Reason, string? Details);

public static class SocialEndpoints
{
    public static void MapSocialEndpoints(this IEndpointRouteBuilder app)
    {
        var v1 = app.MapGroup("/api/v1");

        var me = v1.MapGroup("/me").RequireAuthorization();
        me.MapGet("/notifications", NotificationsAsync);
        me.MapPost("/notifications/{id:guid}/read", MarkReadAsync);
        me.MapPost("/notifications/read-all", MarkAllReadAsync);
        me.MapGet("/reports", MyReportsAsync);

        v1.MapPost("/reports", CreateReportAsync).RequireAuthorization();
        v1.MapGet("/cases/{id:guid}/share-card.svg", ShareCardAsync).AllowAnonymous();
        v1.MapGet("/share/{code}", ShareInfoAsync).AllowAnonymous();

        app.MapGet("/share/{code}", SharePageAsync).AllowAnonymous();
        app.MapGet("/c/{code}", (string code) => Results.Redirect($"/share/{code}")).AllowAnonymous();
        app.MapGet("/pay/mock/{providerRef}", (string providerRef) => Results.Redirect($"/api/v1/dev/pay/mock/{providerRef}")).AllowAnonymous();
    }

    private static async Task<IResult> NotificationsAsync(VilepDbContext db, CurrentUser current, bool? unreadOnly, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var query = db.Notifications.AsNoTracking().Where(n => n.UserId == userId);
        if (unreadOnly == true) query = query.Where(n => n.ReadAt == null);
        var items = await query.OrderByDescending(n => n.CreatedAt).Take(100).ToListAsync(ct);
        var unread = await db.Notifications.CountAsync(n => n.UserId == userId && n.ReadAt == null, ct);
        return ApiResult.Ok(new
        {
            unreadCount = unread,
            items = items.Select(n => new { n.Id, n.Type, n.Title, n.Body, n.PayloadJson, n.ReadAt, n.CreatedAt })
        });
    }

    private static async Task<IResult> MarkReadAsync(Guid id, VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var notification = await db.Notifications.FirstOrDefaultAsync(n => n.Id == id && n.UserId == userId, ct)
                            ?? throw ApiException.NotFound("Không tìm thấy thông báo");
        notification.ReadAt ??= DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id, read = true });
    }

    private static async Task<IResult> MarkAllReadAsync(VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var rows = await db.Notifications.Where(n => n.UserId == userId && n.ReadAt == null).ToListAsync(ct);
        foreach (var row in rows) row.ReadAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { marked = rows.Count });
    }

    private static async Task<IResult> CreateReportAsync(ReportRequest req, VilepDbContext db, CurrentUser current,
        NotificationService notify, CancellationToken ct)
    {
        var userId = current.RequireUser();
        if (string.IsNullOrWhiteSpace(req.Reason)) throw ApiException.BadRequest("reason_required", "Chọn lý do báo cáo");
        var targetType = req.TargetType is "case" or "user" or "comment" ? req.TargetType : "case";

        var report = new Report
        {
            TargetType = targetType,
            TargetId = req.TargetId,
            ReporterId = userId,
            Reason = req.Reason,
            Details = req.Details ?? ""
        };
        db.Reports.Add(report);

        Case? c = null;
        if (targetType == "case")
            c = await db.Cases.FirstOrDefaultAsync(x => x.Id == req.TargetId, ct);

        if (c?.DebtorId is not null && c.DebtorId != userId)
            notify.Push(c.DebtorId, "report_received", "Case của bạn đang được xem xét",
                "Có báo cáo vi phạm cho case của bạn. Đội kiểm duyệt sẽ xem xét trong thời gian sớm nhất.");

        Audit.Write(db, userId, "user", "report.created", "report", report.Id, after: new { targetType, req.TargetId, req.Reason });
        await db.SaveChangesAsync(ct);
        return ApiResult.Ok(new { id = report.Id, state = report.State });
    }

    private static async Task<IResult> MyReportsAsync(VilepDbContext db, CurrentUser current, CancellationToken ct)
    {
        var userId = current.RequireUser();
        var rows = await db.Reports.AsNoTracking().Where(r => r.ReporterId == userId)
            .OrderByDescending(r => r.CreatedAt).ToListAsync(ct);
        return ApiResult.Ok(new { items = rows.Select(r => new { r.Id, r.TargetType, r.TargetId, r.Reason, r.State, r.Resolution, r.CreatedAt }) });
    }

    private static async Task<IResult> ShareInfoAsync(string code, VilepDbContext db, IOptions<VilepOptions> options, CancellationToken ct)
    {
        var c = await db.Cases.AsNoTracking().Include(x => x.Debtor)
            .FirstOrDefaultAsync(x => x.Code == code, ct) ?? throw ApiException.NotFound("Không tìm thấy case");
        var baseUrl = options.Value.BaseUrl;
        return ApiResult.Ok(new
        {
            caseId = c.Id,
            code = c.Code,
            title = c.Title,
            percent = CaseMapper.PercentOf(c),
            raised = c.RaisedAmount,
            target = c.TargetAmount,
            webUrl = $"{baseUrl}/share/{c.Code}",
            deepLink = $"vilep://case/{c.Code}",
            shareImage = $"{baseUrl}/api/v1/cases/{c.Id}/share-card.svg",
            ogDescription = $"{CaseMapper.PercentOf(c)}% · {c.RaisedAmount:N0}đ / {c.TargetAmount:N0}đ — {CaseMapper.LabelFor(c)}"
        });
    }

    private static async Task<IResult> ShareCardAsync(Guid id, VilepDbContext db, CancellationToken ct)
    {
        var c = await db.Cases.AsNoTracking().Include(x => x.Debtor)
            .FirstOrDefaultAsync(x => x.Id == id, ct) ?? throw ApiException.NotFound("Không tìm thấy case");
        var svg = ShareCardRenderer.Render(c);
        return Results.Content(svg, "image/svg+xml; charset=utf-8");
    }

    private static async Task<IResult> SharePageAsync(string code, VilepDbContext db, IOptions<VilepOptions> options, CancellationToken ct)
    {
        var c = await db.Cases.AsNoTracking().Include(x => x.Debtor)
            .FirstOrDefaultAsync(x => x.Code == code, ct);
        if (c is null) return Results.Content("<h1>404</h1>", "text/html; charset=utf-8", statusCode: 404);

        var percent = CaseMapper.PercentOf(c);
        var baseUrl = options.Value.BaseUrl;
        var title = WebUtility.HtmlEncode(c.Title);
        var description = WebUtility.HtmlEncode($"{percent}% · {c.RaisedAmount:N0}đ / {c.TargetAmount:N0}đ — {CaseMapper.LabelFor(c)}");
        var image = $"{baseUrl}/api/v1/cases/{c.Id}/share-card.svg";

        var html = $$"""
        <!doctype html>
        <html lang="vi"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>{{title}} · Ví Lép</title>
        <meta property="og:type" content="website">
        <meta property="og:title" content="{{title}}">
        <meta property="og:description" content="{{description}}">
        <meta property="og:image" content="{{image}}">
        <meta property="og:url" content="{{baseUrl}}/share/{{c.Code}}">
        <meta name="twitter:card" content="summary_large_image">
        <style>
        :root{--green:#05CE78;--ink:#0B0B0B}
        *{box-sizing:border-box}
        body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#F7F7F5;color:var(--ink)}
        .wrap{max-width:520px;margin:0 auto;padding:20px}
        .hero{border-radius:24px;overflow:hidden;background:#fff;box-shadow:0 10px 40px rgba(0,0,0,.08)}
        .cover{height:220px;background:{{CaseMapper.CoverFor(c.Category).Color}};display:flex;align-items:center;justify-content:center;font-size:88px}
        .body{padding:22px}
        h1{font-size:26px;line-height:1.2;margin:0 0 10px}
        .label{display:inline-block;background:#E9FBF2;color:#067647;font-weight:700;font-size:12px;padding:6px 10px;border-radius:999px}
        .bar{height:10px;background:#EFEFEF;border-radius:999px;margin:18px 0 8px;overflow:hidden}
        .fill{height:100%;width:{{percent}}%;background:var(--green);border-radius:999px}
        .row{display:flex;justify-content:space-between;font-size:14px;color:#555;margin-top:6px}
        .big{font-size:22px;font-weight:800;color:var(--ink)}
        .cta{display:block;text-align:center;margin-top:22px;background:var(--green);color:#04170E;font-weight:800;text-decoration:none;padding:16px;border-radius:999px}
        .muted{text-align:center;color:#888;font-size:12px;margin-top:16px;line-height:1.5}
        </style></head>
        <body><div class="wrap"><div class="hero">
          <div class="cover">{{CaseMapper.CoverFor(c.Category).Emoji}}</div>
          <div class="body">
            <span class="label">{{CaseMapper.LabelFor(c)}}</span>
            <h1>{{title}}</h1>
            <div class="bar"><div class="fill"></div></div>
            <div class="row"><span class="big">{{c.RaisedAmount:N0}}đ</span><span>{{percent}}% / {{c.TargetAmount:N0}}đ</span></div>
            <div class="row"><span>Người đăng: {{WebUtility.HtmlEncode(c.Debtor?.Nickname ?? "Ẩn danh")}}</span><span>Còn {{CaseMapper.DaysLeft(c)}} ngày</span></div>
            <a class="cta" href="vilep://case/{{c.Code}}">Mở Ví Lép để cứu nợ</a>
            <p class="muted">{{CaseMapper.MoneyDestinationFor(c)}}<br>Ví lép, bạn bè lo!</p>
          </div>
        </div></div></body></html>
        """;
        return Results.Content(html, "text/html; charset=utf-8");
    }
}

/// <summary>Generates the share card as SVG (no image libraries needed, works offline).</summary>
public static class ShareCardRenderer
{
    public static string Render(Case c)
    {
        const int w = 1200, h = 630;
        var percent = CaseMapper.PercentOf(c);
        var cover = CaseMapper.CoverFor(c.Category);
        var title = Wrap(c.Title, 26, 3);
        var lines = title.Select((line, i) => $"<text x=\"80\" y=\"{250 + i * 62}\" font-size=\"52\" font-weight=\"800\" fill=\"#0B0B0B\">{Escape(line)}</text>");
        var barWidth = 1040;
        var fillWidth = Math.Max(8, barWidth * percent / 100);
        var wallet = Mascot(percent, 960, 210, 140);

        var svg = $"""
        <svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="Ví Lép share card">
          <defs>
            <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stop-color="#F2FFF8"/><stop offset="100%" stop-color="{cover.Color}"/>
            </linearGradient>
            <linearGradient id="fill" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0%" stop-color="#05CE78"/><stop offset="100%" stop-color="#08E68A"/>
            </linearGradient>
          </defs>
          <rect width="{w}" height="{h}" fill="url(#bg)"/>
          <rect x="0" y="0" width="14" height="{h}" fill="#05CE78"/>
          <text x="80" y="118" font-family="Arial, sans-serif" font-size="34" font-weight="800" fill="#05CE78">VÍ LÉP</text>
          <text x="80" y="162" font-family="Arial, sans-serif" font-size="24" fill="#5C6B63">{Escape(cover.Emoji)} {Escape(CategoryLabel(c.Category))} · {Escape(CaseMapper.LabelFor(c))}</text>
          {string.Join("\n  ", lines)}
          <rect x="80" y="430" width="{barWidth}" height="26" rx="13" fill="#FFFFFF" opacity="0.85"/>
          <rect x="80" y="430" width="{fillWidth}" height="26" rx="13" fill="url(#fill)"/>
          <text x="80" y="510" font-family="Arial, sans-serif" font-size="46" font-weight="800" fill="#0B0B0B">{c.RaisedAmount:N0}đ</text>
          <text x="1120" y="510" text-anchor="end" font-family="Arial, sans-serif" font-size="32" fill="#0B0B0B">{percent}% / {c.TargetAmount:N0}đ</text>
          <text x="80" y="572" font-family="Arial, sans-serif" font-size="24" fill="#4B5B52">{Escape(CaseMapper.MoneyDestinationFor(c))}</text>
          {wallet}
        </svg>
        """;
        return svg;
    }

    private static string Mascot(int percent, int x, int y, int size)
    {
        var fillHeight = Math.Clamp(percent * 100 / 100, 5, 100) * 0.5; // 0..50px of the belly
        var mood = percent >= 100 ? "M2 12 Q8 18 14 12" : percent >= 50 ? "M2 14 L14 14" : "M2 16 Q8 10 14 16";
        return $"""
        <g transform="translate({x},{y}) scale({size / 100.0})">
          <rect x="0" y="10" width="100" height="70" rx="18" fill="#1E1E1E"/>
          <rect x="4" y="30" width="92" height="46" rx="14" fill="#2B2B2B"/>
          <rect x="8" y="{72 - fillHeight}" width="84" height="{fillHeight}" rx="10" fill="#05CE78" opacity="0.9"/>
          <rect x="68" y="42" width="30" height="26" rx="8" fill="#05CE78"/>
          <circle cx="34" cy="48" r="4" fill="#FFFFFF"/>
          <circle cx="58" cy="48" r="4" fill="#FFFFFF"/>
          <path d="{mood}" stroke="#FFFFFF" stroke-width="3" fill="none" stroke-linecap="round" transform="translate(32,52)"/>
        </g>
        """;
    }

    private static IEnumerable<string> Wrap(string text, int max, int maxLines)
    {
        var lines = new List<string>();
        var current = new StringBuilder();
        foreach (var word in text.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        {
            if (current.Length > 0 && current.Length + word.Length + 1 > max)
            {
                lines.Add(current.ToString());
                current.Clear();
                if (lines.Count == maxLines) break;
            }
            if (current.Length > 0) current.Append(' ');
            current.Append(word);
        }
        if (lines.Count < maxLines && current.Length > 0) lines.Add(current.ToString());
        return lines;
    }

    private static string CategoryLabel(string category) => category switch
    {
        "tra-sua" => "Nợ trà sữa",
        "nhau" => "Nợ nhậu",
        "ca-cuoc" => "Thua cược",
        "an-uong" => "Mượn tiền ăn",
        "qua-sinh-nhat" => "Quà sinh nhật",
        "muon-tien" => "Mượn tiền",
        _ => "Nợ vui"
    };

    private static string Escape(string value) => WebUtility.HtmlEncode(value);
}
