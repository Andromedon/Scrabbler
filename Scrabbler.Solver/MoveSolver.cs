using System.Text;
using Scrabbler.Domain.BoardModel;
using Scrabbler.Data;

namespace Scrabbler.Solver;

public sealed class MoveSolver : IMoveSolver
{
    private readonly IWordDictionary _dictionary;
    private readonly IReadOnlyDictionary<char, int> _letterValues;

    public MoveSolver(IWordDictionary dictionary, IReadOnlyDictionary<char, int> letterValues)
    {
        _dictionary = dictionary;
        _letterValues = letterValues;
    }

    public IReadOnlyList<Move> FindBestMoves(Board board, Rack rack, int limit)
    {
        var moves = new List<Move>();

        var boardLetters = board.Cells
            .Where(cell => cell.Letter is not null)
            .GroupBy(cell => cell.Letter!.Value)
            .ToDictionary(group => group.Key, group => group.Count());

        foreach (var word in _dictionary.WordsByLength
            .Where(pair => pair.Key <= Board.Size)
            .SelectMany(pair => pair.Value)
            .Where(word => CouldBeMadeFromRackAndBoard(word, rack, boardLetters)))
        {
            foreach (Direction direction in Enum.GetValues<Direction>())
            {
                var maxStart = Board.Size - word.Length;
                for (var fixedAxis = 0; fixedAxis < Board.Size; fixedAxis++)
                {
                    for (var start = 0; start <= maxStart; start++)
                    {
                        if (TryBuildMove(board, rack, word, direction, fixedAxis, start, out var move))
                        {
                            moves.Add(move);
                        }
                    }
                }
            }
        }

        return moves
            .OrderByDescending(move => move.Score)
            .ThenBy(move => move.PlacedTiles.Count(tile => tile.IsBlank))
            .ThenByDescending(move => move.Word.Length)
            .ThenBy(move => move.Word, StringComparer.Ordinal)
            .ThenBy(move => move.Row)
            .ThenBy(move => move.Column)
            .Take(limit)
            .ToList();
    }

    private static bool CouldBeMadeFromRackAndBoard(string word, Rack rack, IReadOnlyDictionary<char, int> boardLetters)
    {
        var blanksNeeded = 0;
        foreach (var group in word.GroupBy(letter => letter))
        {
            rack.Letters.TryGetValue(group.Key, out var rackCount);
            boardLetters.TryGetValue(group.Key, out var boardCount);
            var missing = group.Count() - rackCount - boardCount;
            if (missing > 0)
            {
                blanksNeeded += missing;
                if (blanksNeeded > rack.BlankCount)
                {
                    return false;
                }
            }
        }

        return true;
    }

    private bool TryBuildMove(Board board, Rack rack, string word, Direction direction, int fixedAxis, int start, out Move move)
    {
        move = default!;

        var row = direction == Direction.Horizontal ? fixedAxis : start;
        var col = direction == Direction.Horizontal ? start : fixedAxis;
        if (HasAdjacentBeforeOrAfter(board, word.Length, row, col, direction))
        {
            return false;
        }

        var remaining = rack.Letters.ToDictionary(pair => pair.Key, pair => pair.Value);
        var blanks = rack.BlankCount;
        var placed = new List<PlacedTile>();
        var touchedExisting = false;

        for (var i = 0; i < word.Length; i++)
        {
            var (r, c) = Coordinate(row, col, direction, i);
            var cell = board[r, c];
            var letter = word[i];

            if (cell.Letter is { } existing)
            {
                if (existing != letter)
                {
                    return false;
                }

                touchedExisting = true;
                continue;
            }

            if (remaining.TryGetValue(letter, out var count) && count > 0)
            {
                remaining[letter] = count - 1;
                placed.Add(new PlacedTile(r, c, letter, false));
            }
            else if (blanks > 0)
            {
                blanks--;
                placed.Add(new PlacedTile(r, c, letter, true));
            }
            else
            {
                return false;
            }
        }

        if (placed.Count == 0)
        {
            return false;
        }

        if (board.IsEmpty)
        {
            if (!CoversCenter(row, col, direction, word.Length))
            {
                return false;
            }
        }
        else if (!touchedExisting && !placed.Any(tile => HasNeighbor(board, tile.Row, tile.Column)))
        {
            return false;
        }

        var crossWords = new List<string>();
        var score = ScoreMainWord(board, word, row, col, direction, placed);

        foreach (var tile in placed)
        {
            var crossDirection = direction == Direction.Horizontal ? Direction.Vertical : Direction.Horizontal;
            var cross = BuildWordThrough(board, tile.Row, tile.Column, crossDirection, tile.Letter);
            if (cross.Word.Length <= 1)
            {
                continue;
            }

            if (!_dictionary.Contains(cross.Word))
            {
                return false;
            }

            crossWords.Add(cross.Word);
            score += ScoreCrossWord(board, cross.Cells, tile);
        }

        move = new Move(word, row, col, direction, placed, score, crossWords);
        return true;
    }

    private bool HasAdjacentBeforeOrAfter(Board board, int length, int row, int col, Direction direction)
    {
        var before = direction == Direction.Horizontal ? (row, col - 1) : (row - 1, col);
        var after = direction == Direction.Horizontal ? (row, col + length) : (row + length, col);
        return IsOccupied(board, before) || IsOccupied(board, after);
    }

    private static bool CoversCenter(int row, int col, Direction direction, int length)
    {
        for (var i = 0; i < length; i++)
        {
            var (r, c) = Coordinate(row, col, direction, i);
            if (r == 7 && c == 7)
            {
                return true;
            }
        }

        return false;
    }

    private static bool HasNeighbor(Board board, int row, int col)
    {
        return IsOccupied(board, (row - 1, col))
            || IsOccupied(board, (row + 1, col))
            || IsOccupied(board, (row, col - 1))
            || IsOccupied(board, (row, col + 1));
    }

    private static bool IsOccupied(Board board, (int Row, int Col) coordinate)
    {
        return Board.IsInside(coordinate.Row, coordinate.Col) && board[coordinate.Row, coordinate.Col].Letter is not null;
    }

    private int ScoreMainWord(Board board, string word, int row, int col, Direction direction, IReadOnlyList<PlacedTile> placed)
    {
        var placedMap = placed.ToDictionary(tile => (tile.Row, tile.Column));
        var wordMultiplier = 1;
        var score = 0;

        for (var i = 0; i < word.Length; i++)
        {
            var (r, c) = Coordinate(row, col, direction, i);
            var cell = board[r, c];
            var letter = word[i];

            if (placedMap.TryGetValue((r, c), out var placedTile))
            {
                score += LetterScore(letter, placedTile.IsBlank) * LetterMultiplier(cell.Bonus);
                wordMultiplier *= WordMultiplier(cell.Bonus);
            }
            else
            {
                score += LetterScore(letter, cell.IsBlank);
            }
        }

        return score * wordMultiplier;
    }

    private int ScoreCrossWord(Board board, IReadOnlyList<(int Row, int Column, char Letter)> cells, PlacedTile newTile)
    {
        var wordMultiplier = 1;
        var score = 0;

        foreach (var (row, col, letter) in cells)
        {
            var cell = board[row, col];
            if (row == newTile.Row && col == newTile.Column)
            {
                score += LetterScore(letter, newTile.IsBlank) * LetterMultiplier(cell.Bonus);
                wordMultiplier *= WordMultiplier(cell.Bonus);
            }
            else
            {
                score += LetterScore(letter, cell.IsBlank);
            }
        }

        return score * wordMultiplier;
    }

    private (string Word, IReadOnlyList<(int Row, int Column, char Letter)> Cells) BuildWordThrough(
        Board board,
        int row,
        int col,
        Direction direction,
        char newLetter)
    {
        var startRow = row;
        var startCol = col;
        while (true)
        {
            var previous = direction == Direction.Horizontal ? (startRow, startCol - 1) : (startRow - 1, startCol);
            if (!IsOccupied(board, previous))
            {
                break;
            }

            startRow = previous.Item1;
            startCol = previous.Item2;
        }

        var builder = new StringBuilder();
        var cells = new List<(int Row, int Column, char Letter)>();
        var currentRow = startRow;
        var currentCol = startCol;

        while (Board.IsInside(currentRow, currentCol))
        {
            var letter = currentRow == row && currentCol == col ? newLetter : board[currentRow, currentCol].Letter;
            if (letter is null)
            {
                break;
            }

            builder.Append(letter.Value);
            cells.Add((currentRow, currentCol, letter.Value));

            if (direction == Direction.Horizontal)
            {
                currentCol++;
            }
            else
            {
                currentRow++;
            }
        }

        return (builder.ToString(), cells);
    }

    private int LetterScore(char letter, bool isBlank)
    {
        if (isBlank)
        {
            return 0;
        }

        if (!_letterValues.TryGetValue(letter, out var score))
        {
            throw new InvalidOperationException($"Missing value for letter '{letter}'.");
        }

        return score;
    }

    private static int LetterMultiplier(BonusType bonus)
    {
        return bonus switch
        {
            BonusType.DoubleLetter => 2,
            BonusType.TripleLetter => 3,
            _ => 1
        };
    }

    private static int WordMultiplier(BonusType bonus)
    {
        return bonus switch
        {
            BonusType.DoubleWord => 2,
            BonusType.TripleWord => 3,
            _ => 1
        };
    }

    private static (int Row, int Col) Coordinate(int row, int col, Direction direction, int offset)
    {
        return direction == Direction.Horizontal ? (row, col + offset) : (row + offset, col);
    }
}
