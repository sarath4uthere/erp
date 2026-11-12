namespace MiniErp.Api.Http;

/// <summary>
/// Creates and validates correlation identifiers used for log tracing and
/// problem-details responses. Input is restricted to a short ASCII allow-list so
/// that a caller-supplied header cannot inject characters into logs or headers.
/// </summary>
public static class CorrelationId
{
    public const string HeaderName = "X-Correlation-ID";
    public const int MaxLength = 64;

    public static bool IsValid(string? value)
    {
        if (string.IsNullOrEmpty(value) || value.Length > MaxLength)
        {
            return false;
        }

        foreach (var character in value)
        {
            if (!char.IsAsciiLetterOrDigit(character) &&
                character is not '-' and not '_' and not '.')
            {
                return false;
            }
        }

        return true;
    }

    public static string New() => Guid.NewGuid().ToString("N");
}
