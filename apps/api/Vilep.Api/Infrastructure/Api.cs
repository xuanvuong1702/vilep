using System.Text.Json;
using System.Text.Json.Serialization;

namespace Vilep.Api.Infrastructure;

public class ApiException : Exception
{
    public int Status { get; }
    public string Code { get; }

    public ApiException(int status, string code, string message) : base(message)
    {
        Status = status;
        Code = code;
    }

    public static ApiException NotFound(string what = "Không tìm thấy") => new(404, "not_found", what);
    public static ApiException BadRequest(string code, string message) => new(400, code, message);
    public static ApiException Forbidden(string message = "Bạn không có quyền làm việc này") => new(403, "forbidden", message);
    public static ApiException Forbidden(string code, string message) => new(403, code, message);
    public static ApiException Unauthorized(string message = "Cần đăng nhập") => new(401, "unauthorized", message);
    public static ApiException Conflict(string code, string message) => new(409, code, message);
}

public static class ApiResult
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter() }
    };

    public static IResult Ok(object? data = null) =>
        Results.Json(new { ok = true, data }, Json);

    public static IResult Fail(int status, string code, string message) =>
        Results.Json(new { ok = false, error = new { code, message } }, Json, statusCode: status);

    public static IResult Page(object items, string? nextCursor) =>
        Ok(new { items, nextCursor });
}

public class ApiExceptionMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ApiExceptionMiddleware> _logger;

    public ApiExceptionMiddleware(RequestDelegate next, ILogger<ApiExceptionMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task Invoke(HttpContext ctx)
    {
        try
        {
            await _next(ctx);
        }
        catch (ApiException ex)
        {
            await Write(ctx, ex.Status, ex.Code, ex.Message);
        }
        catch (Microsoft.EntityFrameworkCore.DbUpdateConcurrencyException)
        {
            await Write(ctx, 409, "concurrent_update", "Dữ liệu vừa thay đổi, vui lòng thử lại");
        }
        catch (BadHttpRequestException ex)
        {
            await Write(ctx, 400, "bad_request", ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unhandled error on {Path}", ctx.Request.Path);
            await Write(ctx, 500, "internal_error", "Có lỗi xảy ra, vui lòng thử lại");
        }
    }

    private static async Task Write(HttpContext ctx, int status, string code, string message)
    {
        if (ctx.Response.HasStarted) return;
        ctx.Response.Clear();
        ctx.Response.StatusCode = status;
        ctx.Response.ContentType = "application/json; charset=utf-8";
        await ctx.Response.WriteAsync(JsonSerializer.Serialize(new
        {
            ok = false,
            error = new { code, message }
        }, ApiResult.Json));
    }
}
