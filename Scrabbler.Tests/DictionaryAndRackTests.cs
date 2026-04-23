using Scrabbler.Domain.BoardModel;
using Scrabbler.Data;

namespace Scrabbler.Tests;

public sealed class DictionaryAndRackTests
{
    [Fact]
    public void DictionaryNormalizesPolishWordsAndPrefixes()
    {
        var dictionary = PolishWordDictionary.FromWords(new[] { " żar ", "mąka" });

        Assert.True(dictionary.Contains("ŻAR"));
        Assert.True(dictionary.Contains("MĄKA"));
        Assert.True(dictionary.HasPrefix("MĄ"));
        Assert.False(dictionary.Contains("MAKA"));
    }

    [Fact]
    public void RackParsesRepeatedPolishLettersAndBlanks()
    {
        var rack = Rack.Parse("aąa?");

        Assert.Equal(2, rack.Letters['A']);
        Assert.Equal(1, rack.Letters['Ą']);
        Assert.Equal(1, rack.BlankCount);
    }
}
