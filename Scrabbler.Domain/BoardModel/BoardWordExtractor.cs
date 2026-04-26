namespace Scrabbler.Domain.BoardModel;

public sealed record BoardWordCell(int Row, int Column, char Letter);

public sealed record BoardWord(string Text, Direction Direction, IReadOnlyList<BoardWordCell> Cells);

public static class BoardWordExtractor
{
    public static IReadOnlyList<BoardWord> ExtractWords(Board board)
    {
        var words = new List<BoardWord>();
        Extract(board, Direction.Horizontal, words);
        Extract(board, Direction.Vertical, words);
        return words;
    }

    public static IReadOnlyList<BoardWord> ExtractWordsAt(Board board, int row, int column)
    {
        return ExtractWords(board)
            .Where(word => word.Cells.Any(cell => cell.Row == row && cell.Column == column))
            .ToArray();
    }

    private static void Extract(Board board, Direction direction, List<BoardWord> words)
    {
        for (var fixedAxis = 0; fixedAxis < Board.Size; fixedAxis++)
        {
            var cells = new List<BoardWordCell>();
            for (var movingAxis = 0; movingAxis < Board.Size; movingAxis++)
            {
                var row = direction == Direction.Horizontal ? fixedAxis : movingAxis;
                var column = direction == Direction.Horizontal ? movingAxis : fixedAxis;
                var letter = board[row, column].Letter;
                if (letter is null)
                {
                    AddWord(direction, cells, words);
                    cells.Clear();
                    continue;
                }

                cells.Add(new BoardWordCell(row, column, letter.Value));
            }

            AddWord(direction, cells, words);
        }
    }

    private static void AddWord(Direction direction, IReadOnlyList<BoardWordCell> cells, List<BoardWord> words)
    {
        if (cells.Count <= 1)
        {
            return;
        }

        words.Add(new BoardWord(new string(cells.Select(cell => cell.Letter).ToArray()), direction, cells.ToArray()));
    }
}
