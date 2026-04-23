using Scrabbler.Domain.BoardModel;
using Scrabbler.Data;
using Scrabbler.Solver;

namespace Scrabbler.Tests;

public sealed class MoveSolverTests
{
    [Fact]
    public void FirstMoveMustCoverCenterAndUsesCenterWordBonus()
    {
        var solver = SolverForWords("ALA");
        var board = EmptyBoardWithCenterDoubleWord();

        var moves = solver.FindBestMoves(board, Rack.Parse("ALA"), 10);

        var best = Assert.Single(moves.Select(move => move.Score).Distinct());
        Assert.Equal(8, best);
        var move = moves[0];
        Assert.Equal("ALA", move.Word);
        Assert.Contains(moves, candidate => candidate.PlacedTiles.Any(tile => tile.Row == 7 && tile.Column == 7));
    }

    [Fact]
    public void LaterMoveMustConnectToExistingTiles()
    {
        var solver = SolverForWords("KOT");
        var board = EmptyBoardWithCenterDoubleWord().SetCell(7, 7, 'A');

        var moves = solver.FindBestMoves(board, Rack.Parse("KOT"), 10);

        Assert.Empty(moves);
    }

    [Fact]
    public void ExistingLettersCanBeExtended()
    {
        var solver = SolverForWords("KOTY");
        var board = EmptyBoardWithCenterDoubleWord()
            .SetCell(7, 7, 'O')
            .SetCell(7, 8, 'T');

        var moves = solver.FindBestMoves(board, Rack.Parse("KY"), 10);

        var best = Assert.Single(moves);
        Assert.Equal("KOTY", best.Word);
        Assert.Equal(7, best.Score);
        Assert.Equal(2, best.PlacedTiles.Count);
    }

    [Fact]
    public void InvalidCrossWordRejectsMove()
    {
        var solver = SolverForWords("KOT");
        var board = EmptyBoardWithCenterDoubleWord()
            .SetCell(7, 7, 'O')
            .SetCell(6, 6, 'Z');

        var moves = solver.FindBestMoves(board, Rack.Parse("KT"), 10);

        Assert.Empty(moves);
    }

    [Fact]
    public void ValidCrossWordAddsCrossScore()
    {
        var solver = SolverForWords("KOT", "ZK");
        var board = EmptyBoardWithCenterDoubleWord()
            .SetCell(7, 7, 'O')
            .SetCell(6, 6, 'Z');

        var moves = solver.FindBestMoves(board, Rack.Parse("KT"), 10);

        var best = moves.First(move => move.CrossWords.Contains("ZK"));
        Assert.Equal("KOT", best.Word);
        Assert.Contains("ZK", best.CrossWords);
        Assert.Equal(8, best.Score);
    }

    [Fact]
    public void BlankTileScoresZero()
    {
        var solver = SolverForWords("ŻAR");
        var board = EmptyBoardWithCenterDoubleWord();

        var moves = solver.FindBestMoves(board, Rack.Parse("?AR"), 10);

        var best = moves[0];
        Assert.Equal(4, best.Score);
        Assert.Contains(best.PlacedTiles, tile => tile is { Letter: 'Ż', IsBlank: true });
    }

    private static MoveSolver SolverForWords(params string[] words)
    {
        return new MoveSolver(PolishWordDictionary.FromWords(words), Values());
    }

    private static Board EmptyBoardWithCenterDoubleWord()
    {
        var bonuses = new BonusType[Board.Size, Board.Size];
        bonuses[7, 7] = BonusType.DoubleWord;
        return new Board(bonuses);
    }

    private static IReadOnlyDictionary<char, int> Values()
    {
        return new Dictionary<char, int>
        {
            ['A'] = 1,
            ['K'] = 2,
            ['L'] = 2,
            ['O'] = 1,
            ['R'] = 1,
            ['T'] = 2,
            ['Y'] = 2,
            ['Z'] = 1,
            ['Ż'] = 5
        };
    }
}
