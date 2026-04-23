namespace Scrabbler.Data;

public interface IWordDictionary
{
    IEnumerable<string> Words { get; }
    IReadOnlyDictionary<int, IReadOnlyList<string>> WordsByLength { get; }
    bool Contains(string word);
    bool HasPrefix(string prefix);
}
