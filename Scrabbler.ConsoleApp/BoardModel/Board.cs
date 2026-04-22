using System.Text;

namespace Scrabbler.App.BoardModel;

public sealed class Board
{
    public const int Size = 15;
    private readonly BoardCell[,] _cells;

    public Board(BonusType[,] bonuses)
    {
        if (bonuses.GetLength(0) != Size || bonuses.GetLength(1) != Size)
        {
            throw new ArgumentException("Bonus matrix must be 15x15.", nameof(bonuses));
        }

        _cells = new BoardCell[Size, Size];
        for (var row = 0; row < Size; row++)
        {
            for (var col = 0; col < Size; col++)
            {
                _cells[row, col] = new BoardCell(row, col, null, false, bonuses[row, col]);
            }
        }
    }

    private Board(BoardCell[,] cells)
    {
        _cells = cells;
    }

    public BoardCell this[int row, int column] => _cells[row, column];

    public bool IsEmpty => Cells.All(cell => cell.IsEmpty);

    public IEnumerable<BoardCell> Cells
    {
        get
        {
            for (var row = 0; row < Size; row++)
            {
                for (var col = 0; col < Size; col++)
                {
                    yield return _cells[row, col];
                }
            }
        }
    }

    public Board SetCell(int row, int column, char? letter, bool isBlank = false)
    {
        if (!IsInside(row, column))
        {
            throw new ArgumentOutOfRangeException(nameof(row), "Cell is outside the 15x15 board.");
        }

        var copy = CloneCells();
        copy[row, column] = copy[row, column].WithLetter(letter is null ? null : PolishAlphabet.NormalizeLetter(letter.Value), isBlank);
        return new Board(copy);
    }

    public static bool IsInside(int row, int column)
    {
        return row >= 0 && row < Size && column >= 0 && column < Size;
    }

    public string Render()
    {
        var builder = new StringBuilder();
        builder.AppendLine("    A B C D E F G H I J K L M N O");
        for (var row = 0; row < Size; row++)
        {
            builder.Append($"{row + 1,2}  ");
            for (var col = 0; col < Size; col++)
            {
                builder.Append(_cells[row, col].Letter ?? '.');
                builder.Append(' ');
            }

            builder.AppendLine();
        }

        return builder.ToString();
    }

    private BoardCell[,] CloneCells()
    {
        var copy = new BoardCell[Size, Size];
        Array.Copy(_cells, copy, _cells.Length);
        return copy;
    }
}
