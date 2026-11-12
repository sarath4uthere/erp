using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace MiniErp.IntegrationTests;

public sealed class HealthEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public HealthEndpointTests(WebApplicationFactory<Program> factory)
    {
        _client = factory
            .WithWebHostBuilder(builder => builder.UseEnvironment("Testing"))
            .CreateClient();
    }

    [Fact]
    public async Task Health_returns_healthy_payload()
    {
        using var response = await _client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);

        var payload = await response.Content.ReadFromJsonAsync<HealthPayload>();
        Assert.NotNull(payload);
        Assert.Equal("Healthy", payload.Status);
        Assert.NotEqual(default, payload.Timestamp);
    }

    [Fact]
    public async Task Baseline_security_headers_are_applied()
    {
        using var response = await _client.GetAsync("/health");

        Assert.Equal("nosniff", response.Headers.GetValues("X-Content-Type-Options").Single());
        Assert.Equal("DENY", response.Headers.GetValues("X-Frame-Options").Single());
        Assert.Equal("no-referrer", response.Headers.GetValues("Referrer-Policy").Single());
        Assert.True(response.Headers.Contains("Content-Security-Policy"));
        Assert.True(response.Headers.CacheControl?.NoStore);
    }

    [Fact]
    public async Task Correlation_id_is_echoed_when_valid()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/health");
        request.Headers.Add("X-Correlation-ID", "test-correlation-1");

        using var response = await _client.SendAsync(request);

        Assert.Equal(
            "test-correlation-1",
            response.Headers.GetValues("X-Correlation-ID").Single());
    }

    [Fact]
    public async Task Invalid_correlation_id_is_replaced()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/health");
        request.Headers.TryAddWithoutValidation("X-Correlation-ID", new string('x', 200));

        using var response = await _client.SendAsync(request);

        var correlationId = response.Headers.GetValues("X-Correlation-ID").Single();
        Assert.NotEqual(new string('x', 200), correlationId);
        Assert.Equal(32, correlationId.Length);
    }

    [Fact]
    public async Task Unknown_route_returns_problem_details_with_correlation_id()
    {
        using var response = await _client.GetAsync("/does-not-exist");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);

        var payload = await response.Content.ReadFromJsonAsync<ProblemPayload>();
        Assert.NotNull(payload);
        Assert.Equal(404, payload.Status);
        Assert.False(string.IsNullOrWhiteSpace(payload.CorrelationId));
    }

    private sealed record HealthPayload(string Status, DateTimeOffset Timestamp);

    private sealed record ProblemPayload(int Status, string? CorrelationId);
}
