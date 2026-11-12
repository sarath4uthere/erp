using MiniErp.Api.Http;

namespace MiniErp.UnitTests;

public sealed class CorrelationIdTests
{
    [Theory]
    [InlineData("abc-123_DEF.456")]
    [InlineData("a")]
    [InlineData("0123456789abcdef0123456789abcdef")]
    public void Valid_values_are_accepted(string value)
    {
        Assert.True(CorrelationId.IsValid(value));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("has space")]
    [InlineData("line\r\nbreak")]
    [InlineData("semi;colon")]
    [InlineData("ümlaut")]
    public void Invalid_values_are_rejected(string? value)
    {
        Assert.False(CorrelationId.IsValid(value));
    }

    [Fact]
    public void Values_longer_than_the_limit_are_rejected()
    {
        var value = new string('a', CorrelationId.MaxLength + 1);

        Assert.False(CorrelationId.IsValid(value));
    }

    [Fact]
    public void Generated_values_are_valid_and_unique()
    {
        var first = CorrelationId.New();
        var second = CorrelationId.New();

        Assert.True(CorrelationId.IsValid(first));
        Assert.True(CorrelationId.IsValid(second));
        Assert.NotEqual(first, second);
    }
}
