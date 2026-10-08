public class TodoRulesTests
{
    [Theory]
    [InlineData("Buy milk")]
    [InlineData(" x ")]
    public void AcceptsValidTitles(string title) => Assert.True(TodoRules.IsValidTitle(title));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void RejectsEmptyTitles(string? title) => Assert.False(TodoRules.IsValidTitle(title));

    [Fact]
    public void RejectsLongTitles() => Assert.False(TodoRules.IsValidTitle(new string('x', 201)));
}
