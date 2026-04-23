using Scrabbler.Domain.BoardModel;

namespace Scrabbler.Tests;

public sealed class BoardCorrectionParserTests
{
    [Fact]
    public void AppliesSingleLetterCorrection()
    {
        var board = EmptyBoard();

        board = BoardCorrectionParser.ApplyCorrections(board, "A1=Ł");

        Assert.Equal('Ł', board[0, 0].Letter);
        Assert.False(board[0, 0].IsBlank);
    }

    [Fact]
    public void AppliesKnownBlankTileCorrection()
    {
        var board = EmptyBoard();

        board = BoardCorrectionParser.ApplyCorrections(board, "H8=Ł?");

        Assert.Equal('Ł', board[7, 7].Letter);
        Assert.True(board[7, 7].IsBlank);
    }

    [Fact]
    public void ClearsCellWithDotOrQuestionMark()
    {
        var board = EmptyBoard().SetCell(7, 7, 'A');

        Assert.Null(BoardCorrectionParser.ApplyCorrections(board, "H8=.")[7, 7].Letter);
        Assert.Null(BoardCorrectionParser.ApplyCorrections(board, "H8=?")[7, 7].Letter);
    }

    [Fact]
    public void AppliesCommaSeparatedCorrections()
    {
        var board = EmptyBoard();

        board = BoardCorrectionParser.ApplyCorrections(board, "A1=A, B2=Ń, C3=Ż?");

        Assert.Equal('A', board[0, 0].Letter);
        Assert.Equal('Ń', board[1, 1].Letter);
        Assert.Equal('Ż', board[2, 2].Letter);
        Assert.True(board[2, 2].IsBlank);
    }

    [Theory]
    [InlineData("P1=A")]
    [InlineData("A16=A")]
    [InlineData("A1=1")]
    [InlineData("A1")]
    public void RejectsInvalidCorrections(string correction)
    {
        Assert.Throws<ArgumentException>(() => BoardCorrectionParser.ApplyCorrections(EmptyBoard(), correction));
    }

    private static Board EmptyBoard()
    {
        return new Board(new BonusType[Board.Size, Board.Size]);
    }
}
