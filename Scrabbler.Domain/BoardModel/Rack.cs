namespace Scrabbler.Domain.BoardModel;

public sealed class Rack
{
    private readonly Dictionary<char, int> _letters;

    public Rack(IEnumerable<char> letters, int blanks)
    {
        _letters = letters
            .Select(PolishAlphabet.NormalizeLetter)
            .GroupBy(letter => letter)
            .ToDictionary(group => group.Key, group => group.Count());
        BlankCount = blanks;
    }

    public int BlankCount { get; }

    public IReadOnlyDictionary<char, int> Letters => _letters;

    public static Rack Parse(string input)
    {
        var letters = new List<char>();
        var blanks = 0;

        foreach (var raw in input.Where(c => !char.IsWhiteSpace(c)))
        {
            if (raw == '?')
            {
                blanks++;
                continue;
            }

            var letter = PolishAlphabet.NormalizeLetter(raw);
            if (!PolishAlphabet.IsPolishLetter(letter))
            {
                throw new ArgumentException($"Unsupported rack letter: {raw}");
            }

            letters.Add(letter);
        }

        return new Rack(letters, blanks);
    }
}
