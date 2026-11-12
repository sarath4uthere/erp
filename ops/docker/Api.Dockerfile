# syntax=docker/dockerfile:1.7

# ---- build ------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Restore with the committed lock files for a reproducible, audited graph.
COPY Directory.Build.props Directory.Packages.props ./
COPY src/Domain/MiniErp.Domain.csproj src/Domain/packages.lock.json src/Domain/
COPY src/Application/MiniErp.Application.csproj src/Application/packages.lock.json src/Application/
COPY src/Infrastructure/MiniErp.Infrastructure.csproj src/Infrastructure/packages.lock.json src/Infrastructure/
COPY src/Api/MiniErp.Api.csproj src/Api/packages.lock.json src/Api/
RUN dotnet restore src/Api/MiniErp.Api.csproj --locked-mode

COPY src/ src/
RUN dotnet publish src/Api/MiniErp.Api.csproj \
        --configuration Release \
        --no-restore \
        --output /app/publish \
        /p:UseAppHost=false

# ---- runtime ----------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# curl is used only for the container health probe; the runtime image is minimal.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_NOLOGO=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

COPY --from=build /app/publish ./

# .NET 8 images define APP_UID (1654); never run as root.
USER $APP_UID
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD ["curl", "-fsS", "http://127.0.0.1:8080/healthz"]

ENTRYPOINT ["dotnet", "MiniErp.Api.dll"]
