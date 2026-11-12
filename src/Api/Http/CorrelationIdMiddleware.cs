namespace MiniErp.Api.Http;

public sealed class CorrelationIdMiddleware(RequestDelegate next, ILogger<CorrelationIdMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var supplied = context.Request.Headers[CorrelationId.HeaderName].ToString();
        var correlationId = CorrelationId.IsValid(supplied) ? supplied : CorrelationId.New();

        context.TraceIdentifier = correlationId;
        context.Response.Headers[CorrelationId.HeaderName] = correlationId;

        using (logger.BeginScope(new Dictionary<string, object>
        {
            ["CorrelationId"] = correlationId
        }))
        {
            await next(context);
        }
    }
}
