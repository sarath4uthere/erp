using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace MiniErp.Api.Controllers;

[ApiController]
[Route("health")]
public sealed class HealthController(HealthCheckService healthChecks) : ControllerBase
{
    /// <summary>Liveness/readiness endpoint used by the SPA, containers and uptime checks.</summary>
    [HttpGet]
    [AllowAnonymous]
    [Produces("application/json")]
    [ProducesResponseType<HealthResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<HealthResponse>(StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<HealthResponse>> Get(CancellationToken cancellationToken)
    {
        var report = await healthChecks.CheckHealthAsync(cancellationToken);

        var response = new HealthResponse(
            report.Status == HealthStatus.Healthy ? "Healthy" : "Unhealthy",
            DateTimeOffset.UtcNow);

        return report.Status == HealthStatus.Healthy
            ? Ok(response)
            : StatusCode(StatusCodes.Status503ServiceUnavailable, response);
    }
}

public sealed record HealthResponse(string Status, DateTimeOffset Timestamp);
