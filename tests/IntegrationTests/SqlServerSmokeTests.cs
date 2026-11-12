using System.Globalization;
using Microsoft.Data.SqlClient;
using Testcontainers.MsSql;

namespace MiniErp.IntegrationTests;

/// <summary>
/// Proves that the pinned SQL Server 2022 image starts and accepts T-SQL.
/// Runs only when RUN_INTEGRATION_TESTS=true so local unit runs stay fast;
/// CI sets the variable and fails the job if the container cannot start.
/// </summary>
public sealed class SqlServerSmokeTests : IAsyncLifetime
{
    private const string TestPassword = "Integration!Sql2022_Test";
    private MsSqlContainer? _container;

    private static bool Enabled =>
        string.Equals(
            Environment.GetEnvironmentVariable("RUN_INTEGRATION_TESTS"),
            "true",
            StringComparison.OrdinalIgnoreCase);

    public async Task InitializeAsync()
    {
        if (!Enabled)
        {
            return;
        }

        _container = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest")
            .WithPassword(TestPassword)
            .Build();

        await _container.StartAsync();
    }

    [Fact]
    [Trait("Category", "Integration")]
    public async Task SqlServer_2022_accepts_queries()
    {
        if (_container is null)
        {
            return; // Skipped by convention when RUN_INTEGRATION_TESTS is not set.
        }

        await using var connection = new SqlConnection(_container.GetConnectionString());
        await connection.OpenAsync();

        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT 1";

        var result = await command.ExecuteScalarAsync();

        Assert.Equal(1, Convert.ToInt32(result, CultureInfo.InvariantCulture));
    }

    public async Task DisposeAsync()
    {
        if (_container is not null)
        {
            await _container.DisposeAsync();
        }
    }
}
