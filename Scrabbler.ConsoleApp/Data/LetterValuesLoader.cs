using System.Text.Json;
using Scrabbler.App.BoardModel;

namespace Scrabbler.App.Data;

public static class LetterValuesLoader
{
    public static IReadOnlyDictionary<char, int> Load(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("Letter values file was not found.", path);
        }

        var values = JsonSerializer.Deserialize<Dictionary<string, int>>(File.ReadAllText(path))
            ?? throw new InvalidOperationException("Letter values file is empty.");

        return values.ToDictionary(
            pair => PolishAlphabet.NormalizeLetter(pair.Key.Single()),
            pair => pair.Value);
    }
}
