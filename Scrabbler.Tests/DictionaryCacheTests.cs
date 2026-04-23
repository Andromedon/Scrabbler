using Scrabbler.Data;

namespace Scrabbler.Tests;

public sealed class DictionaryCacheTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"scrabbler-dict-{Guid.NewGuid():N}");

    public DictionaryCacheTests()
    {
        Directory.CreateDirectory(_directory);
    }

    [Fact]
    public void LoadFiltersInvalidAndTooLongWords()
    {
        var dictionaryPath = WriteDictionary("ALA", "ZAŻÓŁĆ", "ABCDEFGHIJKLMNOP", "A", "QX", "KOT # comment");

        var dictionary = PolishWordDictionary.Load(dictionaryPath, Path.Combine(_directory, "cache"));

        Assert.True(dictionary.Contains("ALA"));
        Assert.True(dictionary.Contains("ZAŻÓŁĆ"));
        Assert.True(dictionary.Contains("KOT"));
        Assert.False(dictionary.Contains("ABCDEFGHIJKLMNOP"));
        Assert.False(dictionary.Contains("QX"));
        Assert.DoesNotContain(dictionary.Words, word => word.Length > 15);
    }

    [Fact]
    public void LoadUsesCacheWhenSourceMetadataMatches()
    {
        var cacheDirectory = Path.Combine(_directory, "cache");
        var dictionaryPath = WriteDictionary("ALA", "KOT");
        var messages = new List<string>();

        _ = PolishWordDictionary.Load(dictionaryPath, cacheDirectory, messages.Add);
        messages.Clear();
        var dictionary = PolishWordDictionary.Load(dictionaryPath, cacheDirectory, messages.Add);

        Assert.True(dictionary.Contains("ALA"));
        Assert.Contains(messages, message => message.StartsWith("Loading processed dictionary cache", StringComparison.Ordinal));
    }

    [Fact]
    public void LoadRebuildsCacheWhenDictionaryChanges()
    {
        var cacheDirectory = Path.Combine(_directory, "cache");
        var dictionaryPath = WriteDictionary("ALA");
        _ = PolishWordDictionary.Load(dictionaryPath, cacheDirectory);

        Thread.Sleep(20);
        File.AppendAllText(dictionaryPath, $"{Environment.NewLine}KOT");
        var messages = new List<string>();
        var dictionary = PolishWordDictionary.Load(dictionaryPath, cacheDirectory, messages.Add);

        Assert.True(dictionary.Contains("KOT"));
        Assert.Contains(messages, message => message.StartsWith("Building processed dictionary cache", StringComparison.Ordinal));
    }

    public void Dispose()
    {
        Directory.Delete(_directory, recursive: true);
    }

    private string WriteDictionary(params string[] words)
    {
        var path = Path.Combine(_directory, "dictionary.txt");
        File.WriteAllLines(path, words);
        return path;
    }
}
