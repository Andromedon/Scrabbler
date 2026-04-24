using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Scrabbler.Domain.BoardModel;

namespace Scrabbler.Data;

public sealed class PolishWordDictionary : IWordDictionary
{
    private const int CacheVersion = 1;
    private readonly HashSet<string> _words;
    private readonly Lazy<HashSet<string>> _prefixes;

    private PolishWordDictionary(HashSet<string> words, IReadOnlyDictionary<int, IReadOnlyList<string>> wordsByLength)
    {
        _words = words;
        WordsByLength = wordsByLength;
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
        var cached = TryReadBinaryCache(cachePath, source, reportStatus)
            ?? TryReadLegacyJsonCache(GetLegacyJsonCachePath(cacheDirectory, source.FullName), source, cachePath, reportStatus);
        var snapshot = cached ?? BuildAndWriteCache(path, source, cachePath, reportStatus);

        if (snapshot.Words.Count == 0)
        {
            throw new InvalidOperationException("Dictionary did not contain any valid Polish words with length 2..15.");
        }

        return Create(snapshot.Words, snapshot.WordsByLength);
    }

    public static PolishWordDictionary FromWords(IEnumerable<string> words)
    {
        var normalized = words
            .Select(PolishAlphabet.NormalizeWord)
            .Where(IsUsableWord)
            .ToHashSet(StringComparer.Ordinal);
        return Create(normalized, GroupWordsByLength(normalized));
    }

    public bool Contains(string word)
    {
        return _words.Contains(PolishAlphabet.NormalizeWord(word));
    }

    public bool HasPrefix(string prefix)
    {
        return _prefixes.Value.Contains(PolishAlphabet.NormalizeWord(prefix));
    }

    private static PolishWordDictionary Create(HashSet<string> words, IReadOnlyDictionary<int, IReadOnlyList<string>> wordsByLength)
    {
        return new PolishWordDictionary(words, wordsByLength);
    }

    private static DictionarySnapshot? TryReadBinaryCache(string cachePath, FileInfo source, Action<string>? reportStatus)
    {
        if (!File.Exists(cachePath))
        {
            return null;
        }

        try
        {
            using var stream = File.OpenRead(cachePath);
            using var reader = new BinaryReader(stream, Encoding.UTF8, leaveOpen: false);

            if (reader.ReadInt32() != CacheVersion)
            {
                return null;
            }

            var sourceFullPath = reader.ReadString();
            var sourceLength = reader.ReadInt64();
            var sourceLastWriteUtcTicks = reader.ReadInt64();

            if (!StringComparer.Ordinal.Equals(sourceFullPath, source.FullName)
                || sourceLength != source.Length
                || sourceLastWriteUtcTicks != source.LastWriteTimeUtc.Ticks)
            {
                return null;
            }

            var wordsByLength = new Dictionary<int, IReadOnlyList<string>>();
            var words = new HashSet<string>(StringComparer.Ordinal);
            var groupCount = reader.ReadInt32();
            for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
            {
                var length = reader.ReadInt32();
                var wordCount = reader.ReadInt32();
                var groupWords = new string[wordCount];
                for (var wordIndex = 0; wordIndex < wordCount; wordIndex++)
                {
                    var word = reader.ReadString();
                    groupWords[wordIndex] = word;
                    words.Add(word);
                }

                wordsByLength[length] = groupWords;
            }

            reportStatus?.Invoke($"Loading processed dictionary cache: {cachePath}");
            return new DictionarySnapshot(words, wordsByLength);
        }
        catch
        {
            return null;
        }
    }

    private static DictionarySnapshot? TryReadLegacyJsonCache(string legacyCachePath, FileInfo source, string binaryCachePath, Action<string>? reportStatus)
    {
        if (!File.Exists(legacyCachePath))
        {
            return null;
        }

        try
        {
            var cache = JsonSerializer.Deserialize<LegacyDictionaryCache>(File.ReadAllText(legacyCachePath));
            if (cache is null
                || !StringComparer.Ordinal.Equals(cache.SourceFullPath, source.FullName)
                || cache.SourceLength != source.Length
                || cache.SourceLastWriteUtcTicks != source.LastWriteTimeUtc.Ticks)
            {
                return null;
            }

            reportStatus?.Invoke($"Loading legacy processed dictionary cache: {legacyCachePath}");
            var words = cache.Words.ToHashSet(StringComparer.Ordinal);
            var snapshot = new DictionarySnapshot(words, GroupWordsByLength(words));
            WriteBinaryCache(binaryCachePath, source, snapshot);
            reportStatus?.Invoke($"Saved processed dictionary cache: {binaryCachePath}");
            return snapshot;
        }
        catch
        {
            return null;
        }
    }

    private static DictionarySnapshot BuildAndWriteCache(string path, FileInfo source, string cachePath, Action<string>? reportStatus)
    {
        reportStatus?.Invoke("Building processed dictionary cache. This can take a while the first time.");
        var words = File.ReadLines(path)
            .Select(line => line.Split('#')[0])
            .Select(PolishAlphabet.NormalizeWord)
            .Where(IsUsableWord)
            .ToHashSet(StringComparer.Ordinal);
        var wordsByLength = GroupWordsByLength(words);

        WriteBinaryCache(cachePath, source, new DictionarySnapshot(words, wordsByLength));

        reportStatus?.Invoke($"Saved processed dictionary cache: {cachePath}");
        return new DictionarySnapshot(words, wordsByLength);
    }

    private static void WriteBinaryCache(string cachePath, FileInfo source, DictionarySnapshot snapshot)
    {
        using (var stream = File.Create(cachePath))
        using (var writer = new BinaryWriter(stream, Encoding.UTF8, leaveOpen: false))
        {
            writer.Write(CacheVersion);
            writer.Write(source.FullName);
            writer.Write(source.Length);
            writer.Write(source.LastWriteTimeUtc.Ticks);
            writer.Write(snapshot.WordsByLength.Count);

            foreach (var pair in snapshot.WordsByLength.OrderBy(pair => pair.Key))
            {
                writer.Write(pair.Key);
                writer.Write(pair.Value.Count);
                foreach (var word in pair.Value)
                {
                    writer.Write(word);
                }
            }
        }
    }

    private static IReadOnlyDictionary<int, IReadOnlyList<string>> GroupWordsByLength(IEnumerable<string> words)
    {
        return words
            .GroupBy(word => word.Length)
            .ToDictionary(
                group => group.Key,
                group => (IReadOnlyList<string>)group.Order(StringComparer.Ordinal).ToArray());
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
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(dictionaryPath)))[..16];
        return Path.Combine(cacheDirectory, $"dictionary-{hash}.bin");
    }

    private static string GetLegacyJsonCachePath(string cacheDirectory, string dictionaryPath)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(dictionaryPath)))[..16];
        return Path.Combine(cacheDirectory, $"dictionary-{hash}.json");
    }

    private sealed record DictionarySnapshot(HashSet<string> Words, IReadOnlyDictionary<int, IReadOnlyList<string>> WordsByLength);

    private sealed record LegacyDictionaryCache(string SourceFullPath, long SourceLength, long SourceLastWriteUtcTicks, string[] Words);
}
