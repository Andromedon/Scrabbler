using Scrabbler.Data;
using Scrabbler.Domain.BoardModel;
using Scrabbler.ImageAnalysis;

namespace Scrabbler.Tests;

public sealed class DictionaryBoardRepairerTests
{
    [Fact]
    public void FixesNhWhenDictionaryAndScoreDigitAgree()
    {
        var board = EmptyBoard()
            .SetCell(7, 7, 'N')
            .SetCell(7, 8, 'A')
            .SetCell(7, 9, 'T');
        var result = Result(board, Cell(7, 7, 'N', 0.66f, 3, Candidate('N', 0.80), Candidate('H', 0.76)));
        var repairer = Repairer("HAT");

        var repaired = repairer.Repair(result);

        Assert.Equal('H', repaired.Board[7, 7].Letter);
        Assert.Contains(repaired.Repairs!, repair => repair is { Row: 7, Column: 7, From: 'N', To: 'H' });
    }

    [Fact]
    public void FixesDoAndDbWhenDictionaryAndScoreDigitAgree()
    {
        var board = EmptyBoard()
            .SetCell(7, 7, 'B')
            .SetCell(7, 8, 'O')
            .SetCell(7, 9, 'M');
        var result = Result(board, Cell(7, 7, 'B', 0.62f, 2, Candidate('B', 0.80), Candidate('D', 0.73), Candidate('O', 0.70)));
        var repairer = Repairer("DOM");

        var repaired = repairer.Repair(result);

        Assert.Equal('D', repaired.Board[7, 7].Letter);
    }

    [Fact]
    public void FillsMissingOccupiedCellWhenCandidatesCompleteAWord()
    {
        var board = EmptyBoard()
            .SetCell(7, 7, 'K')
            .SetCell(7, 9, 'T');
        var result = Result(board, Cell(7, 8, null, 0.08f, 1, Candidate('O', 0.82), Candidate('D', 0.65)));
        var repairer = Repairer("KOT");

        var repaired = repairer.Repair(result);

        Assert.Equal('O', repaired.Board[7, 8].Letter);
    }

    [Fact]
    public void FillsSingleUndetectedGapWhenExactlyOneDictionaryWordFits()
    {
        var board = EmptyBoard()
            .SetCell(7, 7, 'Ś')
            .SetCell(7, 9, 'O')
            .SetCell(7, 10, 'D')
            .SetCell(7, 11, 'Y');
        var result = Result(board, new CellRead(
            7,
            8,
            null,
            1,
            false,
            Visual: new CellVisualRead(0.64, 0, 0.24)));
        var repairer = Repairer("ŚRODY");

        var repaired = repairer.Repair(result);

        Assert.Equal('R', repaired.Board[7, 8].Letter);
        Assert.Contains(repaired.Repairs!, repair => repair is { Row: 7, Column: 8, From: null, To: 'R' });
    }

    [Fact]
    public void RefusesAmbiguousRepairs()
    {
        var board = EmptyBoard()
            .SetCell(7, 7, 'C')
            .SetCell(7, 8, 'A')
            .SetCell(7, 9, 'T');
        var result = Result(board, Cell(7, 7, 'C', 0.60f, null, Candidate('C', 0.80), Candidate('B', 0.75), Candidate('D', 0.75)));
        var repairer = Repairer("BAT", "DAT");

        var repaired = repairer.Repair(result);

        Assert.Equal('C', repaired.Board[7, 7].Letter);
        Assert.Null(repaired.Repairs);
    }

    [Fact]
    public void RefusesRepairsThatBreakCrossingWords()
    {
        var board = EmptyBoard()
            .SetCell(7, 7, 'B')
            .SetCell(7, 8, 'O')
            .SetCell(7, 9, 'M')
            .SetCell(6, 7, 'A');
        var result = Result(board, Cell(7, 7, 'B', 0.62f, 2, Candidate('B', 0.80), Candidate('D', 0.74)));
        var repairer = Repairer("DOM", "AB");

        var repaired = repairer.Repair(result);

        Assert.Equal('B', repaired.Board[7, 7].Letter);
        Assert.Null(repaired.Repairs);
    }

    [Fact]
    public void DoesNotOverrideClearHighConfidenceUnrelatedLetter()
    {
        var board = EmptyBoard()
            .SetCell(7, 7, 'B')
            .SetCell(7, 8, 'O')
            .SetCell(7, 9, 'M');
        var result = Result(board, Cell(7, 7, 'B', 0.94f, 3, Candidate('B', 0.92), Candidate('D', 0.70)));
        var repairer = Repairer("DOM");

        var repaired = repairer.Repair(result);

        Assert.Equal('B', repaired.Board[7, 7].Letter);
    }

    private static Board EmptyBoard()
    {
        return new Board(new BonusType[Board.Size, Board.Size]);
    }

    private static BoardReadResult Result(Board board, params CellRead[] reads)
    {
        var cells = new List<CellRead>();
        for (var row = 0; row < Board.Size; row++)
        {
            for (var col = 0; col < Board.Size; col++)
            {
                var configured = reads.FirstOrDefault(cell => cell.Row == row && cell.Column == col);
                var letter = board[row, col].Letter;
                cells.Add(configured ?? new CellRead(
                    row,
                    col,
                    letter,
                    1,
                    letter is not null,
                    Visual: letter is null ? null : new CellVisualRead(0.6, 0.04, 0)));
            }
        }

        return new BoardReadResult(board, cells);
    }

    private static CellRead Cell(int row, int column, char? letter, float confidence, int? scoreDigit, params LetterCandidateRead[] candidates)
    {
        return new CellRead(row, column, letter, confidence, true, candidates, new ScoreDigitRead(scoreDigit, 0.70, scoreDigit is not null));
    }

    private static LetterCandidateRead Candidate(char letter, double score)
    {
        return new LetterCandidateRead(letter, score);
    }

    private static DictionaryBoardRepairer Repairer(params string[] words)
    {
        return new DictionaryBoardRepairer(PolishWordDictionary.FromWords(words), Values());
    }

    private static IReadOnlyDictionary<char, int> Values()
    {
        return new Dictionary<char, int>
        {
            ['A'] = 1,
            ['B'] = 3,
            ['C'] = 2,
            ['D'] = 2,
            ['H'] = 3,
            ['K'] = 2,
            ['M'] = 2,
            ['N'] = 1,
            ['O'] = 1,
            ['R'] = 1,
            ['Ś'] = 5,
            ['T'] = 2
        };
    }
}
