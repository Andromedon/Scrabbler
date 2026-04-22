using Scrabbler.App.BoardModel;
using Scrabbler.App.ImageAnalysis;
using Scrabbler.App.Solver;

namespace Scrabbler.App.ConsoleUi;

public sealed class ScrabblerConsole
{
    public void WriteInfo(string message)
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine(message);
        Console.ResetColor();
    }

    public void WriteError(string message)
    {
        Console.ForegroundColor = ConsoleColor.Red;
        Console.WriteLine(message);
        Console.ResetColor();
    }

    public void WriteBoard(Board board)
    {
        Console.WriteLine(board.Render());
    }

    public void WriteDetectedOccupiedCells(IReadOnlyList<CellRead> cells)
    {
        var occupied = cells
            .Where(cell => cell.IsOccupied)
            .Select(cell => $"{(char)('A' + cell.Column)}{cell.Row + 1}={(cell.Letter?.ToString() ?? "?")} ({cell.Confidence:P0})")
            .ToArray();

        if (occupied.Length == 0)
        {
            WriteInfo("No occupied tile cells were detected automatically.");
            return;
        }

        WriteInfo($"Detected occupied tile cells: {string.Join(", ", occupied)}");

        var uncertain = cells
            .Where(cell => cell.IsOccupied && (cell.Letter is null || cell.Confidence < 0.70f))
            .Select(cell => $"{(char)('A' + cell.Column)}{cell.Row + 1}")
            .ToArray();
        if (uncertain.Length > 0)
        {
            WriteInfo($"Review these low-confidence cells: {string.Join(", ", uncertain)}");
        }
    }

    public Board ApplyBoardCorrections(Board board)
    {
        while (true)
        {
            Console.Write("Corrections (example H8=Ł, H8=?, H8=.; empty to continue): ");
            var input = Console.ReadLine();
            if (string.IsNullOrWhiteSpace(input))
            {
                return board;
            }

            try
            {
                foreach (var item in input.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    board = ApplyCorrection(board, item);
                }
            }
            catch (ArgumentException ex)
            {
                WriteError(ex.Message);
                continue;
            }

            WriteBoard(board);
        }
    }

    public Rack ReadRack()
    {
        while (true)
        {
            Console.Write("Rack letters (? for blank): ");
            var input = Console.ReadLine() ?? string.Empty;
            try
            {
                return Rack.Parse(input);
            }
            catch (ArgumentException ex)
            {
                WriteError(ex.Message);
            }
        }
    }

    public void WriteBestMoves(IReadOnlyList<Move> moves)
    {
        WriteInfo("Best moves:");
        foreach (var move in moves)
        {
            var column = (char)('A' + move.Column);
            var direction = move.Direction == Direction.Horizontal ? "horizontal" : "vertical";
            var placed = string.Join(", ", move.PlacedTiles.Select(tile => $"{(char)('A' + tile.Column)}{tile.Row + 1}={tile.Letter}{(tile.IsBlank ? "?" : "")}"));
            var crosses = move.CrossWords.Count == 0 ? "-" : string.Join(", ", move.CrossWords);
            Console.WriteLine($"{move.Score,3}  {move.Word} at {column}{move.Row + 1} {direction}; placed: {placed}; crosses: {crosses}");
        }
    }

    private static Board ApplyCorrection(Board board, string correction)
    {
        var parts = correction.Split('=', 2, StringSplitOptions.TrimEntries);
        if (parts.Length != 2)
        {
            throw new ArgumentException($"Invalid correction: {correction}");
        }

        var (row, col) = ParseCoordinate(parts[0]);
        var value = parts[1].Trim();
        if (value == ".")
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

    private static (int Row, int Column) ParseCoordinate(string value)
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
