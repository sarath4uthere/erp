using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.OpenApi.Models;
using MiniErp.Api.Http;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options =>
{
    // Do not advertise the server implementation.
    options.AddServerHeader = false;

    // Baseline request-size limit. Module-specific limits may be stricter.
    options.Limits.MaxRequestBodySize = 10 * 1024 * 1024;
});

builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = context =>
    {
        // RFC 7807 responses always carry the correlation id used in logs.
        context.ProblemDetails.Extensions["correlationId"] = context.HttpContext.TraceIdentifier;
    };
});

builder.Services
    .AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
    });

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Mini-ERP API",
        Version = "v1",
        Description = "Contract-first API. The authoritative definition is openapi/openapi.yaml."
    });
});

builder.Services.AddHealthChecks();
builder.Services.AddAuthorization();

var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(options =>
{
    options.AddPolicy("web", policy =>
    {
        // Fail closed: an empty allow-list permits no browser origin.
        policy.WithOrigins(allowedOrigins.Length == 0 ? ["https://invalid.local"] : allowedOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseMiddleware<CorrelationIdMiddleware>();
app.UseMiddleware<SecurityHeadersMiddleware>();

if (app.Configuration.GetValue("Security:UseHttpsRedirection", true))
{
    app.UseHsts();
    app.UseHttpsRedirection();
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("web");
app.MapControllers();

// Container liveness probe; not part of the public contract.
app.MapHealthChecks("/healthz").AllowAnonymous();

app.Run();

// Exposed so WebApplicationFactory<Program> can boot the real pipeline in tests.
public partial class Program;
