namespace Scrabbler.Domain.BoardModel;

public static class BoardCorrectionParser
{
    public static Board ApplyCorrections(Board board, string input)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return board;
        }

        foreach (var item in input.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            board = ApplyCorrection(board, item);
        }

        return board;
    }

    public static Board ApplyCorrection(Board board, string correction)
    {
        var parts = correction.Split('=', 2, StringSplitOptions.TrimEntries);
        if (parts.Length != 2)
        {
            throw new ArgumentException($"Invalid correction: {correction}");
        }

        var (row, col) = ParseCoordinate(parts[0]);
        var value = parts[1].Trim();
        if (value == "." || value == "?")
        {
            return board.SetCell(row, col, null);
        }

        var isBlank = value.EndsWith('?');
        var letterText = isBlank ? value[..^1] : value;
        if (letterText.Length != 1 || !PolishAlphabet.IsPolishLetter(letterText[0]))
        {
            throw new ArgumentException($"Invalid correction letter: {value}");
        }

        return board.SetCell(row, col, letterText[0], isBlank);
    }

    public static (int Row, int Column) ParseCoordinate(string value)
    {
        value = value.Trim().ToUpperInvariant();
        if (value.Length < 2)
        {
            throw new ArgumentException($"Invalid coordinate: {value}");
        }

        var column = value[0] - 'A';
        if (!int.TryParse(value[1..], out var rowNumber))
        {
            throw new ArgumentException($"Invalid coordinate: {value}");
        }

        var row = rowNumber - 1;
        if (!Board.IsInside(row, column))
        {
            throw new ArgumentException($"Coordinate outside board: {value}");
        }

        return (row, column);
    }
}
