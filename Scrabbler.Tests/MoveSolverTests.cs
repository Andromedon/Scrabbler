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
    public void BundledBonusLayoutScoresFirstMoveCenterDoubleWord()
    {
        var solver = new MoveSolver(PolishWordDictionary.FromWords(["WYLEJĘ"]), LoadBundledLetterValues());
        var board = new Board(LoadBundledBonuses());

        var moves = solver.FindBestMoves(board, Rack.Parse("WYLEJĘ"), 10);

        Assert.Equal(BonusType.DoubleWord, board[7, 7].Bonus);
        Assert.NotEmpty(moves);
        Assert.Contains(
            moves,
            move => move.Score == 28 && move.PlacedTiles.Any(tile => tile is { Row: 7, Column: 7 }));
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

    [Fact]
    public void PlacingAllSevenRackTilesAddsBonus()
    {
        var solver = SolverForWords("KOTARAS");
        var board = EmptyBoardWithCenterDoubleWord();

        var moves = solver.FindBestMoves(board, Rack.Parse("KOTARAS"), 10);

        Assert.All(moves, move => Assert.Equal(43, move.Score));
        Assert.All(moves, move => Assert.Equal(7, move.PlacedTiles.Count));
    }

    [Fact]
    public void PlacingFewerThanSevenRackTilesDoesNotAddBonus()
    {
        var solver = SolverForWords("KOTARA");
        var board = EmptyBoardWithCenterDoubleWord();

        var moves = solver.FindBestMoves(board, Rack.Parse("KOTARA"), 10);

        Assert.All(moves, move => Assert.Equal(16, move.Score));
        Assert.All(moves, move => Assert.Equal(6, move.PlacedTiles.Count));
    }

    [Fact]
    public void BlankTileCountsTowardSevenTileBonus()
    {
        var solver = SolverForWords("KOTARAS");
        var board = EmptyBoardWithCenterDoubleWord();

        var moves = solver.FindBestMoves(board, Rack.Parse("?OTARAS"), 10);

        Assert.All(moves, move => Assert.Equal(39, move.Score));
        Assert.All(moves, move => Assert.Equal(7, move.PlacedTiles.Count));
        Assert.All(moves, move => Assert.Contains(move.PlacedTiles, tile => tile is { Letter: 'K', IsBlank: true }));
    }

    [Fact]
    public void ReturnsOnlyRequestedNumberOfBestMovesInStableOrder()
    {
        var solver = SolverForWords("KOT", "TOK", "OK", "TO");
        var board = EmptyBoardWithCenterDoubleWord();

        var moves = solver.FindBestMoves(board, Rack.Parse("KOT"), 2);

        Assert.Equal(2, moves.Count);
        Assert.True(moves[0].Score >= moves[1].Score);
        Assert.True(string.CompareOrdinal(moves[0].Word, moves[1].Word) <= 0 || moves[0].Score > moves[1].Score);
    }

    [Fact]
    public void RankedMovesStayStableForRepresentativeConnectedBoard()
    {
        var solver = SolverForWords("TOK", "KOT", "OKA", "KOSA", "OSA", "SOK", "TO", "TOS", "SA", "AS");
        var board = EmptyBoardWithCenterDoubleWord()
            .SetCell(7, 7, 'O')
            .SetCell(7, 8, 'K')
            .SetCell(6, 6, 'T')
            .SetCell(8, 6, 'S');

        var moves = solver.FindBestMoves(board, Rack.Parse("TAAS"), 5);

        Assert.Equal(
            [
                "AS@J8:V:2:AJ8,SJ9|6|OKA",
                "SA@J7:V:2:SJ7,AJ8|6|OKA",
                "OKA@H8:H:1:AJ8|4",
                "AS@F9:V:2:AF9,SF10|4|AS",
                "AS@G10:H:2:AG10,SH10|4|SA"
            ],
            moves.Select(DescribeMove).ToArray());
    }

    [Fact]
    public void PremiumCrossWordRankingParityVector()
    {
        var solver = SolverForWords("TOK", "KOT", "OKA", "KOSA", "OSA", "SOK", "TO", "TOS", "SA", "AS");
        var board = ParityBoardWithPremiumCross();

        var moves = solver.FindBestMoves(board, Rack.Parse("TAAS"), 8);

        Assert.Equal(
            [
                "AS@J8:V:2:AJ8,SJ9|12|OKA",
                "SA@J7:V:2:SJ7,AJ8|12|OKA",
                "OKA@H8:H:1:AJ8|8",
                "AS@F9:V:2:AF9,SF10|4|AS",
                "AS@G10:H:2:AG10,SH10|4|SA",
                "SA@F8:V:2:SF8,AF9|4|AS",
                "SA@F10:H:2:SF10,AG10|4|SA",
                "AS@F9:H:1:AF9|2"
            ],
            moves.Select(DescribeMove).ToArray());
    }

    [Fact]
    public void RealBoardShapeRankingParityVector()
    {
        var solver = SolverForWords(
            "STAZIE", "STAZIĘ", "DOZA", "CERO", "DMIJ", "ADWA", "ODA", "OŚ",
            "STA", "TA", "ZA", "ZIE", "RA", "AS", "SA", "SI", "AD", "WA", "DA",
            "WADA", "WAD", "DWA", "DROGA", "ROD", "RÓD", "DOM", "MIJ", "MAJ");
        var board = RealBoardShape7367();

        var moves = solver.FindBestMoves(board, Rack.Parse("STAZIE"), 12);

        Assert.Equal(
            [
                "STAZIE@G9:H:6:SG9,TH9,AI9,ZJ9,IK9,EL9|10|TA",
                "STAZIE@G9:V:6:SG9,TG10,AG11,ZG12,IG13,EG14|10|TA",
                "STAZIE@F7:H:5:SF7,TG7,ZI7,IJ7,EK7|9|SA",
                "STAZIE@H9:H:6:SH9,TI9,AJ9,ZK9,IL9,EM9|9|SA",
                "STAZIE@G10:V:6:SG10,TG11,AG12,ZG13,IG14,EG15|9|SA",
                "STAZIE@I10:V:6:SI10,TI11,AI12,ZI13,II14,EI15|9|AS",
                "STAZIE@H11:H:6:SH11,TI11,AJ11,ZK11,IL11,EM11|9|AS",
                "STA@G9:H:3:SG9,TH9,AI9|7|TA",
                "STA@G9:V:3:SG9,TG10,AG11|7|TA",
                "STA@D4:V:3:SD4,TD5,AD6|6|AS",
                "STA@K4:H:3:SK4,TL4,AM4|6|SA",
                "STA@K6:H:3:SK6,TL6,AM6|6|AS"
            ],
            moves.Select(DescribeMove).ToArray());
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

    private static Board ParityBoardWithPremiumCross()
    {
        var bonuses = new BonusType[Board.Size, Board.Size];
        bonuses[7, 7] = BonusType.DoubleWord;
        bonuses[7, 9] = BonusType.DoubleWord;
        return new Board(bonuses)
            .SetCell(7, 7, 'O')
            .SetCell(7, 8, 'K')
            .SetCell(6, 6, 'T')
            .SetCell(8, 6, 'S');
    }

    private static Board RealBoardShape7367()
    {
        var bonuses = new BonusType[Board.Size, Board.Size];
        bonuses[7, 7] = BonusType.DoubleWord;
        bonuses[0, 8] = BonusType.TripleLetter;
        bonuses[4, 7] = BonusType.DoubleWord;
        bonuses[4, 9] = BonusType.DoubleLetter;
        bonuses[9, 1] = BonusType.TripleWord;

        return new Board(bonuses)
            .SetCell(0, 5, 'C')
            .SetCell(0, 6, 'E')
            .SetCell(0, 7, 'R')
            .SetCell(0, 8, 'O')
            .SetCell(1, 8, 'Ś')
            .SetCell(1, 9, 'R')
            .SetCell(1, 10, 'O')
            .SetCell(1, 11, 'D')
            .SetCell(1, 12, 'Y')
            .SetCell(3, 7, 'A')
            .SetCell(4, 5, 'W')
            .SetCell(4, 7, 'D')
            .SetCell(4, 8, 'O')
            .SetCell(4, 9, 'Z')
            .SetCell(4, 10, 'A')
            .SetCell(5, 4, 'S')
            .SetCell(5, 7, 'W')
            .SetCell(6, 7, 'A')
            .SetCell(7, 5, 'A')
            .SetCell(9, 1, 'D')
            .SetCell(9, 2, 'M')
            .SetCell(9, 3, 'I')
            .SetCell(9, 4, 'J')
            .SetCell(9, 7, 'A');
    }

    private static IReadOnlyDictionary<char, int> Values()
    {
        return new Dictionary<char, int>
        {
            ['A'] = 1,
            ['C'] = 2,
            ['D'] = 2,
            ['E'] = 1,
            ['I'] = 1,
            ['J'] = 3,
            ['K'] = 2,
            ['L'] = 2,
            ['M'] = 2,
            ['O'] = 1,
            ['R'] = 1,
            ['S'] = 1,
            ['T'] = 2,
            ['W'] = 1,
            ['Y'] = 2,
            ['Z'] = 1,
            ['Ę'] = 5,
            ['Ś'] = 5,
            ['Ó'] = 5,
            ['Ż'] = 5
        };
    }

    private static BonusType[,] LoadBundledBonuses()
    {
        var path = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.Assets/Data/bonus-layout.json"));
        return BonusLayoutLoader.Load(path);
    }

    private static IReadOnlyDictionary<char, int> LoadBundledLetterValues()
    {
        var path = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.Assets/Data/letter-values-pl.json"));
        return LetterValuesLoader.Load(path);
    }

    private static string DescribeMove(Move move)
    {
        var direction = move.Direction == Direction.Horizontal ? "H" : "V";
        var placed = string.Join(",", move.PlacedTiles.Select(tile => $"{tile.Letter}{Coordinate(tile.Row, tile.Column)}"));
        var crossWords = move.CrossWords.Count == 0 ? "" : "|" + string.Join(",", move.CrossWords);
        return $"{move.Word}@{Coordinate(move.Row, move.Column)}:{direction}:{move.PlacedTiles.Count}:{placed}|{move.Score}{crossWords}";
    }

    private static string Coordinate(int row, int column)
    {
        return $"{(char)('A' + column)}{row + 1}";
    }
}
