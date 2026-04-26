using System.Text;
using Scrabbler.Data;
using Scrabbler.Domain.BoardModel;

namespace Scrabbler.Solver;

public sealed class MoveSolver : IMoveSolver
{
    private const int RackBingoBonus = 25;
    private static readonly Direction[] Directions = [Direction.Horizontal, Direction.Vertical];
    private static readonly Dictionary<char, int> AlphabetIndexes = PolishAlphabet.Letters
        .Select((letter, index) => new KeyValuePair<char, int>(letter, index))
        .ToDictionary();
    private static readonly MoveRankComparer RankComparer = new();

    private readonly IWordDictionary _dictionary;
    private readonly IReadOnlyDictionary<char, int> _letterValues;

    public MoveSolver(IWordDictionary dictionary, IReadOnlyDictionary<char, int> letterValues)
    {
        _dictionary = dictionary;
        _letterValues = letterValues;
    }

    public IReadOnlyList<Move> FindBestMoves(Board board, Rack rack, int limit)
    {
        if (limit <= 0)
        {
            return Array.Empty<Move>();
        }

        var context = SolverContext.Create(board, rack);
        var bestMoves = new List<Move>(limit);

        foreach (var pair in _dictionary.WordsByLength)
        {
            if (pair.Key > Board.Size)
            {
                continue;
            }

            var words = pair.Value;
            for (var wordIndex = 0; wordIndex < words.Count; wordIndex++)
            {
                var word = words[wordIndex];
                if (!CouldBeMadeFromRackAndBoard(word, context.RackLetterCounts, rack.BlankCount, context.BoardLetterCounts))
                {
                    continue;
                }

                for (var directionIndex = 0; directionIndex < Directions.Length; directionIndex++)
                {
                    var direction = Directions[directionIndex];
                    var maxStart = Board.Size - word.Length;
                    for (var fixedAxis = 0; fixedAxis < Board.Size; fixedAxis++)
                    {
                        for (var start = 0; start <= maxStart; start++)
                        {
                            if (TryBuildMove(context, word, direction, fixedAxis, start, out var move))
                            {
                                InsertCandidate(bestMoves, move, limit);
                            }
                        }
                    }
                }
            }
        }

        return bestMoves;
    }

    private static void InsertCandidate(List<Move> bestMoves, Move candidate, int limit)
    {
        var index = 0;
        while (index < bestMoves.Count && RankComparer.Compare(bestMoves[index], candidate) <= 0)
        {
            index++;
        }

        if (index >= limit)
        {
            return;
        }

        bestMoves.Insert(index, candidate);
        if (bestMoves.Count > limit)
        {
            bestMoves.RemoveAt(bestMoves.Count - 1);
        }
    }

    private static bool CouldBeMadeFromRackAndBoard(string word, int[] rackLetters, int blankCount, int[] boardLetters)
    {
        Span<int> wordCounts = stackalloc int[AlphabetIndexes.Count];
        for (var i = 0; i < word.Length; i++)
        {
            wordCounts[AlphabetIndexes[word[i]]]++;
        }

        var blanksNeeded = 0;
        for (var i = 0; i < wordCounts.Length; i++)
        {
            var missing = wordCounts[i] - rackLetters[i] - boardLetters[i];
            if (missing <= 0)
            {
                continue;
            }

            blanksNeeded += missing;
            if (blanksNeeded > blankCount)
            {
                return false;
            }
        }

        return true;
    }

    private bool TryBuildMove(SolverContext context, string word, Direction direction, int fixedAxis, int start, out Move move)
    {
        move = default!;

        var row = direction == Direction.Horizontal ? fixedAxis : start;
        var col = direction == Direction.Horizontal ? start : fixedAxis;
        if (HasAdjacentBeforeOrAfter(context.Occupied, word.Length, row, col, direction))
        {
            return false;
        }

        Span<int> remaining = stackalloc int[AlphabetIndexes.Count];
        context.RackLetterCounts.CopyTo(remaining);
        Span<PlacementCandidate> placedBuffer = stackalloc PlacementCandidate[Board.Size];
        var placedCount = 0;
        var blanks = context.Rack.BlankCount;
        var touchedExisting = false;
        var touchedNeighbor = false;
        var score = 0;
        var wordMultiplier = 1;

        for (var i = 0; i < word.Length; i++)
        {
            var (r, c) = Coordinate(row, col, direction, i);
            var cell = context.Board[r, c];
            var letter = word[i];

            if (cell.Letter is { } existing)
            {
                if (existing != letter)
                {
                    return false;
                }

                touchedExisting = true;
                score += LetterScore(letter, cell.IsBlank);
                continue;
            }

            var letterIndex = AlphabetIndexes[letter];
            if (remaining[letterIndex] > 0)
            {
                remaining[letterIndex]--;
                placedBuffer[placedCount++] = new PlacementCandidate(r, c, letter, false);
                score += LetterScore(letter, false) * LetterMultiplier(cell.Bonus);
            }
            else if (blanks > 0)
            {
                blanks--;
                placedBuffer[placedCount++] = new PlacementCandidate(r, c, letter, true);
                score += LetterScore(letter, true) * LetterMultiplier(cell.Bonus);
            }
            else
            {
                return false;
            }

            wordMultiplier *= WordMultiplier(cell.Bonus);
            touchedNeighbor |= context.HasNeighbor[r, c];
        }

        if (placedCount == 0)
        {
            return false;
        }

        if (context.IsBoardEmpty)
        {
            if (!CoversCenter(row, col, direction, word.Length))
            {
                return false;
            }
        }
        else if (!touchedExisting && !touchedNeighbor)
        {
            return false;
        }

        score *= wordMultiplier;
        var crossWords = new List<string>(placedCount);

        for (var i = 0; i < placedCount; i++)
        {
            var tile = placedBuffer[i];
            var crossDirection = direction == Direction.Horizontal ? Direction.Vertical : Direction.Horizontal;
            if (!TryScoreCrossWord(context.Board, tile, crossDirection, out var crossWord, out var crossScore))
            {
                return false;
            }

            if (crossWord is null)
            {
                continue;
            }

            crossWords.Add(crossWord);
            score += crossScore;
        }

        if (placedCount == 7)
        {
            score += RackBingoBonus;
        }

        var placedTiles = new List<PlacedTile>(placedCount);
        for (var i = 0; i < placedCount; i++)
        {
            var tile = placedBuffer[i];
            placedTiles.Add(new PlacedTile(tile.Row, tile.Column, tile.Letter, tile.IsBlank));
        }

        move = new Move(word, row, col, direction, placedTiles, score, crossWords);
        return true;
    }

    private bool TryScoreCrossWord(Board board, PlacementCandidate newTile, Direction direction, out string? crossWord, out int score)
    {
        var startRow = newTile.Row;
        var startCol = newTile.Column;
        while (true)
        {
            var previous = direction == Direction.Horizontal
                ? (Row: startRow, Col: startCol - 1)
                : (Row: startRow - 1, Col: startCol);
            if (!IsOccupied(board, previous.Row, previous.Col))
            {
                break;
            }

            startRow = previous.Row;
            startCol = previous.Col;
        }

        var builder = new StringBuilder();
        var currentRow = startRow;
        var currentCol = startCol;
        var wordMultiplier = 1;
        var wordScore = 0;

        while (Board.IsInside(currentRow, currentCol))
        {
            var isNewTile = currentRow == newTile.Row && currentCol == newTile.Column;
            var letter = isNewTile ? newTile.Letter : board[currentRow, currentCol].Letter;
            if (letter is null)
            {
                break;
            }

            builder.Append(letter.Value);
            var cell = board[currentRow, currentCol];
            if (isNewTile)
            {
                wordScore += LetterScore(letter.Value, newTile.IsBlank) * LetterMultiplier(cell.Bonus);
                wordMultiplier *= WordMultiplier(cell.Bonus);
            }
            else
            {
                wordScore += LetterScore(letter.Value, cell.IsBlank);
            }

            if (direction == Direction.Horizontal)
            {
                currentCol++;
            }
            else
            {
                currentRow++;
            }
        }

        if (builder.Length <= 1)
        {
            crossWord = null;
            score = 0;
            return true;
        }

        crossWord = builder.ToString();
        if (!_dictionary.Contains(crossWord))
        {
            score = 0;
            return false;
        }

        score = wordScore * wordMultiplier;
        return true;
    }

    private static bool HasAdjacentBeforeOrAfter(bool[,] occupied, int length, int row, int col, Direction direction)
    {
        var before = direction == Direction.Horizontal ? (row, col - 1) : (row - 1, col);
        var after = direction == Direction.Horizontal ? (row, col + length) : (row + length, col);
        return IsOccupied(occupied, before.Item1, before.Item2) || IsOccupied(occupied, after.Item1, after.Item2);
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

    private static bool IsOccupied(Board board, int row, int col)
    {
        return Board.IsInside(row, col) && board[row, col].Letter is not null;
    }

    private static bool IsOccupied(bool[,] occupied, int row, int col)
    {
        return Board.IsInside(row, col) && occupied[row, col];
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

    private static int BlankTileCount(Move move)
    {
        var count = 0;
        for (var i = 0; i < move.PlacedTiles.Count; i++)
        {
            if (move.PlacedTiles[i].IsBlank)
            {
                count++;
            }
        }

        return count;
    }

    private sealed class MoveRankComparer : IComparer<Move>
    {
        public int Compare(Move? x, Move? y)
        {
            if (ReferenceEquals(x, y))
            {
                return 0;
            }

            ArgumentNullException.ThrowIfNull(x);
            ArgumentNullException.ThrowIfNull(y);

            var byScore = y.Score.CompareTo(x.Score);
            if (byScore != 0)
            {
                return byScore;
            }

            var byBlanks = BlankTileCount(x).CompareTo(BlankTileCount(y));
            if (byBlanks != 0)
            {
                return byBlanks;
            }

            var byLength = y.Word.Length.CompareTo(x.Word.Length);
            if (byLength != 0)
            {
                return byLength;
            }

            var byWord = StringComparer.Ordinal.Compare(x.Word, y.Word);
            if (byWord != 0)
            {
                return byWord;
            }

            var byRow = x.Row.CompareTo(y.Row);
            if (byRow != 0)
            {
                return byRow;
            }

            return x.Column.CompareTo(y.Column);
        }
    }

    private readonly record struct PlacementCandidate(int Row, int Column, char Letter, bool IsBlank);

    private sealed class SolverContext
    {
        private SolverContext(Board board, Rack rack, bool isBoardEmpty, bool[,] occupied, bool[,] hasNeighbor, int[] boardLetterCounts, int[] rackLetterCounts)
        {
            Board = board;
            Rack = rack;
            IsBoardEmpty = isBoardEmpty;
            Occupied = occupied;
            HasNeighbor = hasNeighbor;
            BoardLetterCounts = boardLetterCounts;
            RackLetterCounts = rackLetterCounts;
        }

        public Board Board { get; }
        public Rack Rack { get; }
        public bool IsBoardEmpty { get; }
        public bool[,] Occupied { get; }
        public bool[,] HasNeighbor { get; }
        public int[] BoardLetterCounts { get; }
        public int[] RackLetterCounts { get; }

        public static SolverContext Create(Board board, Rack rack)
        {
            var occupied = new bool[Board.Size, Board.Size];
            var hasNeighbor = new bool[Board.Size, Board.Size];
            var boardLetterCounts = new int[AlphabetIndexes.Count];
            var rackLetterCounts = new int[AlphabetIndexes.Count];
            var isBoardEmpty = true;

            foreach (var pair in rack.Letters)
            {
                rackLetterCounts[AlphabetIndexes[pair.Key]] = pair.Value;
            }

            for (var row = 0; row < Board.Size; row++)
            {
                for (var col = 0; col < Board.Size; col++)
                {
                    var letter = board[row, col].Letter;
                    if (letter is null)
                    {
                        continue;
                    }

                    isBoardEmpty = false;
                    occupied[row, col] = true;
                    boardLetterCounts[AlphabetIndexes[letter.Value]]++;
                }
            }

            if (!isBoardEmpty)
            {
                for (var row = 0; row < Board.Size; row++)
                {
                    for (var col = 0; col < Board.Size; col++)
                    {
                        if (occupied[row, col])
                        {
                            continue;
                        }

                        hasNeighbor[row, col] = IsOccupied(occupied, row - 1, col)
                            || IsOccupied(occupied, row + 1, col)
                            || IsOccupied(occupied, row, col - 1)
                            || IsOccupied(occupied, row, col + 1);
                    }
                }
            }

            return new SolverContext(board, rack, isBoardEmpty, occupied, hasNeighbor, boardLetterCounts, rackLetterCounts);
        }
    }
}
