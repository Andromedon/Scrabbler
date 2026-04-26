using Scrabbler.Domain.BoardModel;

namespace Scrabbler.Tests;

public sealed class BoardWordExtractorTests
{
    [Fact]
    public void ExtractsHorizontalAndVerticalWordsWithCoordinates()
    {
        var board = EmptyBoard()
            .SetCell(7, 7, 'K')
            .SetCell(7, 8, 'O')
            .SetCell(7, 9, 'T')
            .SetCell(6, 8, 'N')
            .SetCell(8, 8, 'S');

        var words = BoardWordExtractor.ExtractWords(board);

        var horizontal = Assert.Single(words, word => word.Direction == Direction.Horizontal);
        Assert.Equal("KOT", horizontal.Text);
        Assert.Equal([(7, 7), (7, 8), (7, 9)], horizontal.Cells.Select(cell => (cell.Row, cell.Column)).ToArray());

        var vertical = Assert.Single(words, word => word.Direction == Direction.Vertical);
        Assert.Equal("NOS", vertical.Text);
        Assert.Equal([(6, 8), (7, 8), (8, 8)], vertical.Cells.Select(cell => (cell.Row, cell.Column)).ToArray());
    }

    [Fact]
    public void IgnoresSingleLetterRuns()
    {
        var board = EmptyBoard()
            .SetCell(0, 0, 'A')
            .SetCell(2, 2, 'K')
            .SetCell(2, 3, 'O');

        var words = BoardWordExtractor.ExtractWords(board);

        var word = Assert.Single(words);
        Assert.Equal("KO", word.Text);
    }

    private static Board EmptyBoard()
    {
        return new Board(new BonusType[Board.Size, Board.Size]);
    }
}
