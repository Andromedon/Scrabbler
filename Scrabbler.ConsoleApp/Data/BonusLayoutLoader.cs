using System.Text.Json;
using Scrabbler.App.BoardModel;

namespace Scrabbler.App.Data;

public static class BonusLayoutLoader
{
    public static BonusType[,] Load(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("Bonus layout file was not found.", path);
        }

        var rows = JsonSerializer.Deserialize<string[][]>(File.ReadAllText(path))
            ?? throw new InvalidOperationException("Bonus layout file is empty.");

        if (rows.Length != Board.Size || rows.Any(row => row.Length != Board.Size))
        {
            throw new InvalidOperationException("Bonus layout must contain exactly 15 rows of 15 columns.");
        }

        var result = new BonusType[Board.Size, Board.Size];
        for (var row = 0; row < Board.Size; row++)
        {
            for (var col = 0; col < Board.Size; col++)
            {
                result[row, col] = Parse(rows[row][col]);
            }
        }

        return result;
    }

    public static BonusType Parse(string value)
    {
        return value.Trim().ToUpperInvariant() switch
        {
            "" or "NONE" or "." => BonusType.None,
            "2L" => BonusType.DoubleLetter,
            "3L" => BonusType.TripleLetter,
            "2W" => BonusType.DoubleWord,
            "3W" => BonusType.TripleWord,
            _ => throw new InvalidOperationException($"Unknown bonus type: {value}")
        };
    }
}
