using Scrabbler.App.BoardModel;
using System.Security.Cryptography;
using System.Text.Json;

namespace Scrabbler.App.Data;

public sealed class PolishWordDictionary : IWordDictionary
{
    private readonly HashSet<string> _words;
    private readonly Lazy<HashSet<string>> _prefixes;

    private PolishWordDictionary(HashSet<string> words)
    {
        _words = words;
        WordsByLength = words
            .GroupBy(word => word.Length)
            .ToDictionary(
                group => group.Key,
                group => (IReadOnlyList<string>)group.Order(StringComparer.Ordinal).ToArray());
        _prefixes = new Lazy<HashSet<string>>(BuildPrefixes);
    }

    public IEnumerable<string> Words => _words;
    public IReadOnlyDictionary<int, IReadOnlyList<string>> WordsByLength { get; }

    public static PolishWordDictionary Load(string path, string? cacheDirectory = null, Action<string>? reportStatus = null)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("Dictionary file was not found.", path);
        }

        cacheDirectory ??= Path.Combine(Path.GetDirectoryName(Path.GetFullPath(path))!, ".cache");
        Directory.CreateDirectory(cacheDirectory);

        var source = new FileInfo(path);
        var cachePath = GetCachePath(cacheDirectory, source.FullName);
        var cached = TryReadCache(cachePath, source, reportStatus);
        var words = cached ?? BuildAndWriteCache(path, source, cachePath, reportStatus);

        if (words.Count == 0)
        {
            throw new InvalidOperationException("Dictionary did not contain any valid Polish words with length 2..15.");
        }

        return new PolishWordDictionary(words);
    }

    public static PolishWordDictionary FromWords(IEnumerable<string> words)
    {
        return new PolishWordDictionary(words
            .Select(PolishAlphabet.NormalizeWord)
            .Where(IsUsableWord)
            .ToHashSet(StringComparer.Ordinal));
    }

    public bool Contains(string word)
    {
        return _words.Contains(PolishAlphabet.NormalizeWord(word));
    }

    public bool HasPrefix(string prefix)
    {
        return _prefixes.Value.Contains(PolishAlphabet.NormalizeWord(prefix));
    }

    private static HashSet<string>? TryReadCache(string cachePath, FileInfo source, Action<string>? reportStatus)
    {
        if (!File.Exists(cachePath))
        {
            return null;
        }

        try
        {
            var cache = JsonSerializer.Deserialize<DictionaryCache>(File.ReadAllText(cachePath));
            if (cache is null
                || !StringComparer.Ordinal.Equals(cache.SourceFullPath, source.FullName)
                || cache.SourceLength != source.Length
                || cache.SourceLastWriteUtcTicks != source.LastWriteTimeUtc.Ticks)
            {
                return null;
            }

            reportStatus?.Invoke($"Loading processed dictionary cache: {cachePath}");
            return cache.Words.ToHashSet(StringComparer.Ordinal);
        }
        catch
        {
            return null;
        }
    }

    private static HashSet<string> BuildAndWriteCache(string path, FileInfo source, string cachePath, Action<string>? reportStatus)
    {
        reportStatus?.Invoke("Building processed dictionary cache. This can take a while the first time.");
        var words = File.ReadLines(path)
            .Select(line => line.Split('#')[0])
            .Select(PolishAlphabet.NormalizeWord)
            .Where(IsUsableWord)
            .ToHashSet(StringComparer.Ordinal);

        var cache = new DictionaryCache(
            source.FullName,
            source.Length,
            source.LastWriteTimeUtc.Ticks,
            words.Order(StringComparer.Ordinal).ToArray());
        File.WriteAllText(cachePath, JsonSerializer.Serialize(cache));
        reportStatus?.Invoke($"Saved processed dictionary cache: {cachePath}");
        return words;
    }

    private HashSet<string> BuildPrefixes()
    {
        var prefixes = new HashSet<string>(StringComparer.Ordinal);
        foreach (var word in _words)
        {
            for (var i = 1; i <= word.Length; i++)
            {
                prefixes.Add(word[..i]);
            }
        }

        return prefixes;
    }

    private static bool IsUsableWord(string word)
    {
        return word.Length is >= 2 and <= Board.Size && word.All(PolishAlphabet.IsPolishLetter);
    }

    private static string GetCachePath(string cacheDirectory, string dictionaryPath)
    {
        var hash = Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(dictionaryPath)))[..16];
        return Path.Combine(cacheDirectory, $"dictionary-{hash}.json");
    }

    private sealed record DictionaryCache(string SourceFullPath, long SourceLength, long SourceLastWriteUtcTicks, string[] Words);
}
