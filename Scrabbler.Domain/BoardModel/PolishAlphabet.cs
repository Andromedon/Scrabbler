using System.Globalization;

namespace Scrabbler.Domain.BoardModel;

public static class PolishAlphabet
{
    public const string Letters = "AĄBCĆDEĘFGHIJKLŁMNŃOÓPRSŚTUWYZŹŻ";
    private static readonly HashSet<char> LetterSet = Letters.ToHashSet();

    public static char NormalizeLetter(char letter)
    {
        return char.ToUpper(letter, new CultureInfo("pl-PL"));
    }

    public static string NormalizeWord(string word)
    {
        return string.Concat(word.Trim().Select(NormalizeLetter));
    }

    public static bool IsPolishLetter(char letter)
    {
        return LetterSet.Contains(NormalizeLetter(letter));
    }
}
