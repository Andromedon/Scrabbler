using Scrabbler.Data;
using Scrabbler.Domain.BoardModel;

namespace Scrabbler.ImageAnalysis;

public sealed class DictionaryBoardRepairer
{
    private const float HighConfidence = 0.82f;
    private readonly IWordDictionary _dictionary;
    private readonly IReadOnlyDictionary<char, int> _letterValues;

    public DictionaryBoardRepairer(IWordDictionary dictionary, IReadOnlyDictionary<char, int> letterValues)
    {
        _dictionary = dictionary;
        _letterValues = letterValues;
    }

    public BoardReadResult Repair(BoardReadResult readResult)
    {
        var board = readResult.Board;
        var cellsByCoordinate = readResult.Cells.ToDictionary(cell => (cell.Row, cell.Column));
        var repairs = new List<BoardRepair>();

        for (var iteration = 0; iteration < 32; iteration++)
        {
            var invalidWords = BoardWordExtractor.ExtractWords(board)
                .Where(word => !_dictionary.Contains(word.Text))
                .ToArray();

            var best = invalidWords
                .Select(word => FindBestRepair(board, word, cellsByCoordinate))
                .Concat(readResult.Cells
                    .Where(cell => cell.IsOccupied && cell.Letter is null && board[cell.Row, cell.Column].Letter is null)
                    .Select(cell => FindBestMissingLetterRepair(board, cell)))
                .Concat(FindBestGapRepairs(board, cellsByCoordinate))
                .Where(candidate => candidate is not null)
                .Select(candidate => candidate!)
                .OrderByDescending(candidate => candidate.InvalidWordReduction)
                .ThenByDescending(candidate => candidate.Score)
                .ToArray();

            if (best.Length == 0)
            {
                break;
            }

            if (best.Length > 1
                && best[0].InvalidWordReduction == best[1].InvalidWordReduction
                && Math.Abs(best[0].Score - best[1].Score) < 0.0001)
            {
                break;
            }

            var selected = best[0];
            if (selected.InvalidWordReduction <= 0)
            {
                break;
            }

            if (selected.Repairs.All(repair => board[repair.Row, repair.Column].Letter == repair.To))
            {
                break;
            }

            board = selected.Board;
            repairs.AddRange(selected.Repairs);
        }

        if (repairs.Count == 0)
        {
            return readResult;
        }

        var updatedCells = readResult.Cells
            .Select(cell =>
            {
                var repair = repairs.LastOrDefault(item => item.Row == cell.Row && item.Column == cell.Column);
                return repair is null
                    ? cell
                    : cell with { Letter = repair.To, Confidence = Math.Max(cell.Confidence, 0.70f) };
            })
            .ToArray();

        return new BoardReadResult(board, updatedCells, repairs);
    }

    private IEnumerable<RepairCandidate?> FindBestGapRepairs(
        Board board,
        IReadOnlyDictionary<(int Row, int Column), CellRead> cellsByCoordinate)
    {
        for (var row = 0; row < Board.Size; row++)
        {
            for (var column = 0; column < Board.Size; column++)
            {
                if (board[row, column].Letter is not null)
                {
                    continue;
                }

                if (!cellsByCoordinate.TryGetValue((row, column), out var cell)
                    || !LooksLikeMissedTile(cell))
                {
                    continue;
                }

                yield return FindBestGapRepair(board, row, column, Direction.Horizontal, cellsByCoordinate);
                yield return FindBestGapRepair(board, row, column, Direction.Vertical, cellsByCoordinate);
            }
        }
    }

    private RepairCandidate? FindBestGapRepair(
        Board board,
        int row,
        int column,
        Direction direction,
        IReadOnlyDictionary<(int Row, int Column), CellRead> cellsByCoordinate)
    {
        var beforeInvalidCount = CountInvalidWords(board);
        var before = direction == Direction.Horizontal
            ? (Row: row, Column: column - 1)
            : (Row: row - 1, Column: column);
        var after = direction == Direction.Horizontal
            ? (Row: row, Column: column + 1)
            : (Row: row + 1, Column: column);
        if (!IsOccupied(board, before.Row, before.Column) || !IsOccupied(board, after.Row, after.Column))
        {
            return null;
        }

        var cells = new List<(int Row, int Column, char? Letter)>();
        var startRow = row;
        var startColumn = column;
        while (true)
        {
            var previous = direction == Direction.Horizontal
                ? (Row: startRow, Column: startColumn - 1)
                : (Row: startRow - 1, Column: startColumn);
            if (!IsOccupied(board, previous.Row, previous.Column))
            {
                break;
            }

            startRow = previous.Row;
            startColumn = previous.Column;
        }

        var currentRow = startRow;
        var currentColumn = startColumn;
        var emptyCount = 0;
        while (Board.IsInside(currentRow, currentColumn))
        {
            var gapLetter = currentRow == row && currentColumn == column
                ? null
                : board[currentRow, currentColumn].Letter;
            if (gapLetter is null && (currentRow != row || currentColumn != column))
            {
                break;
            }

            if (gapLetter is null)
            {
                emptyCount++;
            }

            cells.Add((currentRow, currentColumn, gapLetter));

            if (direction == Direction.Horizontal)
            {
                currentColumn++;
            }
            else
            {
                currentRow++;
            }

            if (emptyCount > 1)
            {
                break;
            }
        }

        if (emptyCount != 1 || cells.Count <= 2 || !_dictionary.WordsByLength.TryGetValue(cells.Count, out var words))
        {
            return null;
        }

        var matches = words
            .Select(word => BuildGapCandidate(board, cells, word, row, column, cellsByCoordinate, beforeInvalidCount))
            .Where(candidate => candidate is not null)
            .Select(candidate => candidate!)
            .OrderByDescending(candidate => candidate.InvalidWordReduction)
            .ThenByDescending(candidate => candidate.Score)
            .Take(2)
            .ToArray();
        if (matches.Length != 1)
        {
            return null;
        }

        return matches[0];
    }

    private RepairCandidate? BuildGapCandidate(
        Board board,
        IReadOnlyList<(int Row, int Column, char? Letter)> cells,
        string word,
        int gapRow,
        int gapColumn,
        IReadOnlyDictionary<(int Row, int Column), CellRead> cellsByCoordinate,
        int beforeInvalidCount)
    {
        if (word.Length != cells.Count)
        {
            return null;
        }

        var repairedBoard = board;
        var repairs = new List<BoardRepair>();
        var score = (double)word.Length;
        for (var i = 0; i < word.Length; i++)
        {
            var cell = cells[i];
            var expected = word[i];
            if (cell.Row == gapRow && cell.Column == gapColumn)
            {
                repairedBoard = repairedBoard.SetCell(cell.Row, cell.Column, expected);
                repairs.Add(new BoardRepair(cell.Row, cell.Column, null, expected, $"dictionary: {word}"));
                score += 0.75;
                continue;
            }

            if (cell.Letter == expected)
            {
                continue;
            }

            if (cell.Letter is null
                || !cellsByCoordinate.TryGetValue((cell.Row, cell.Column), out var read)
                || !CanSubstituteGapNeighbor(read, cell.Letter.Value, expected, out var optionScore))
            {
                return null;
            }

            repairedBoard = repairedBoard.SetCell(cell.Row, cell.Column, expected);
            repairs.Add(new BoardRepair(cell.Row, cell.Column, cell.Letter, expected, $"dictionary: {word}"));
            score += optionScore;
        }

        if (repairs.Count == 0 || repairs.Count(repair => repair.From is not null) > 1)
        {
            return null;
        }

        var affectedWords = repairs
            .SelectMany(repair => BoardWordExtractor.ExtractWordsAt(repairedBoard, repair.Row, repair.Column))
            .Distinct()
            .ToArray();
        if (affectedWords.Length == 0 || affectedWords.Any(affected => !_dictionary.Contains(affected.Text)))
        {
            return null;
        }

        var invalidReduction = beforeInvalidCount - CountInvalidWords(repairedBoard);
        return new RepairCandidate(
            repairedBoard,
            repairs,
            score,
            Math.Max(1, invalidReduction));
    }

    private bool CanSubstituteGapNeighbor(CellRead cell, char currentLetter, char expectedLetter, out double score)
    {
        score = 0;
        if (cell.Confidence >= HighConfidence)
        {
            return false;
        }

        var options = LetterOptions(cell, currentLetter)
            .Where(option => option.Changed && option.Letter == expectedLetter)
            .ToArray();
        if (options.Length == 0)
        {
            return false;
        }

        score = options.Max(option => option.Score);
        return true;
    }

    private static bool LooksLikeMissedTile(CellRead cell)
    {
        if (cell.Letter is not null)
        {
            return false;
        }

        if (cell.IsOccupied)
        {
            return true;
        }

        return cell.Visual is { OrangeRatio: >= 0.35 };
    }

    private RepairCandidate? FindBestMissingLetterRepair(Board board, CellRead cell)
    {
        if (cell.Candidates is null || cell.Candidates.Count == 0)
        {
            return null;
        }

        var beforeInvalidCount = CountInvalidWords(board);
        var candidates = new List<RepairCandidate>();
        foreach (var option in MissingLetterOptions(cell).Take(6))
        {
            var repairedBoard = board.SetCell(cell.Row, cell.Column, option.Letter);
            var affectedWords = BoardWordExtractor.ExtractWordsAt(repairedBoard, cell.Row, cell.Column);
            if (affectedWords.Count == 0 || affectedWords.All(word => word.Cells.Count < 3))
            {
                continue;
            }

            if (affectedWords.Any(word => !_dictionary.Contains(word.Text)))
            {
                continue;
            }

            var invalidReduction = beforeInvalidCount - CountInvalidWords(repairedBoard);
            var score = option.Score + affectedWords.Sum(word => word.Text.Length) * 0.03;
            candidates.Add(new RepairCandidate(
                repairedBoard,
                [new BoardRepair(cell.Row, cell.Column, null, option.Letter, "dictionary: missing tile")],
                score,
                Math.Max(1, invalidReduction)));
        }

        return candidates
            .OrderByDescending(candidate => candidate.InvalidWordReduction)
            .ThenByDescending(candidate => candidate.Score)
            .FirstOrDefault();
    }

    private RepairCandidate? FindBestRepair(
        Board board,
        BoardWord invalidWord,
        IReadOnlyDictionary<(int Row, int Column), CellRead> cellsByCoordinate)
    {
        var beforeInvalidCount = CountInvalidWords(board);
        var options = new List<LetterOption[]>();
        foreach (var wordCell in invalidWord.Cells)
        {
            if (!cellsByCoordinate.TryGetValue((wordCell.Row, wordCell.Column), out var cell))
            {
                options.Add([new LetterOption(wordCell.Letter, 1, false)]);
                continue;
            }

            var cellOptions = LetterOptions(cell, wordCell.Letter).ToArray();
            if (cellOptions.Length == 0)
            {
                cellOptions = [new LetterOption(wordCell.Letter, 1, false)];
            }

            options.Add(cellOptions);
        }

        var candidates = new List<RepairCandidate>();
        BuildCandidates(board, invalidWord, options, 0, new LetterOption[invalidWord.Cells.Count], candidates);

        var ranked = candidates
            .Where(candidate => candidate.InvalidWordReduction > 0)
            .OrderByDescending(candidate => candidate.InvalidWordReduction)
            .ThenByDescending(candidate => candidate.Score)
            .ToArray();
        if (ranked.Length > 1
            && ranked[0].InvalidWordReduction == ranked[1].InvalidWordReduction
            && Math.Abs(ranked[0].Score - ranked[1].Score) < 0.0001)
        {
            return null;
        }

        return ranked.FirstOrDefault();

        void BuildCandidates(
            Board candidateBoard,
            BoardWord word,
            IReadOnlyList<LetterOption[]> letterOptions,
            int index,
            LetterOption[] selected,
            List<RepairCandidate> results)
        {
            if (results.Count >= 2048)
            {
                return;
            }

            if (index == letterOptions.Count)
            {
                var changed = new List<BoardRepair>();
                var repairedBoard = candidateBoard;
                var score = 0.0;
                for (var i = 0; i < selected.Length; i++)
                {
                    var option = selected[i];
                    var cell = word.Cells[i];
                    if (!option.Changed)
                    {
                        continue;
                    }

                    repairedBoard = repairedBoard.SetCell(cell.Row, cell.Column, option.Letter);
                    changed.Add(new BoardRepair(cell.Row, cell.Column, cell.Letter, option.Letter, $"dictionary: {word.Text}"));
                    score += option.Score;
                }

                if (changed.Count == 0 || !_dictionary.Contains(WordText(repairedBoard, word)))
                {
                    return;
                }

                var affectedWords = changed
                    .SelectMany(repair => BoardWordExtractor.ExtractWordsAt(repairedBoard, repair.Row, repair.Column))
                    .Distinct()
                    .ToArray();
                if (affectedWords.Any(affected => !_dictionary.Contains(affected.Text)))
                {
                    return;
                }

                var invalidReduction = beforeInvalidCount - CountInvalidWords(repairedBoard);
                results.Add(new RepairCandidate(repairedBoard, changed, score - changed.Count * 0.02, invalidReduction));
                return;
            }

            foreach (var option in letterOptions[index])
            {
                selected[index] = option;
                BuildCandidates(candidateBoard, word, letterOptions, index + 1, selected, results);
            }
        }
    }

    private IEnumerable<LetterOption> LetterOptions(CellRead cell, char currentLetter)
    {
        yield return new LetterOption(currentLetter, 1, false);

        var candidates = cell.Candidates;
        if (candidates is null || candidates.Count == 0)
        {
            yield break;
        }

        var currentScore = candidates.FirstOrDefault(candidate => candidate.Letter == currentLetter)?.Score
            ?? candidates[0].Score;
        var topScore = Math.Max(currentScore, candidates[0].Score);
        foreach (var candidate in candidates.Take(6))
        {
            if (candidate.Letter == currentLetter)
            {
                continue;
            }

            var scoreMatches = cell.ScoreDigit?.IsReliable == true
                && cell.ScoreDigit.Digit is { } digit
                && _letterValues.TryGetValue(candidate.Letter, out var value)
                && value == digit;
            var currentMatches = cell.ScoreDigit?.IsReliable == true
                && cell.ScoreDigit.Digit is { } currentDigit
                && _letterValues.TryGetValue(currentLetter, out var currentValue)
                && currentValue == currentDigit;

            if (cell.Confidence >= HighConfidence && !scoreMatches && candidate.Score < topScore * 0.95)
            {
                continue;
            }

            var closeEnough = candidate.Score >= topScore * 0.86
                || scoreMatches && candidate.Score >= topScore * 0.70
                || cell.Letter is null && candidate.Score >= topScore * 0.62;
            if (!closeEnough)
            {
                continue;
            }

            var optionScore = candidate.Score;
            if (scoreMatches)
            {
                optionScore += 0.20;
            }

            if (currentMatches)
            {
                optionScore -= 0.08;
            }

            yield return new LetterOption(candidate.Letter, optionScore, true);
        }
    }

    private IEnumerable<LetterOption> MissingLetterOptions(CellRead cell)
    {
        var candidates = cell.Candidates;
        if (candidates is null || candidates.Count == 0)
        {
            yield break;
        }

        var topScore = candidates[0].Score;
        foreach (var candidate in candidates.Take(6))
        {
            if (candidate.Score < topScore * 0.62)
            {
                continue;
            }

            var optionScore = candidate.Score;
            if (cell.ScoreDigit?.IsReliable == true
                && cell.ScoreDigit.Digit is { } digit
                && _letterValues.TryGetValue(candidate.Letter, out var value)
                && value == digit)
            {
                optionScore += 0.20;
            }

            yield return new LetterOption(candidate.Letter, optionScore, true);
        }
    }

    private int CountInvalidWords(Board board)
    {
        return BoardWordExtractor.ExtractWords(board).Count(word => word.Text.Length > 1 && !_dictionary.Contains(word.Text));
    }

    private static bool IsOccupied(Board board, int row, int column)
    {
        return Board.IsInside(row, column) && board[row, column].Letter is not null;
    }

    private static bool MatchesPattern(string word, IReadOnlyList<(int Row, int Column, char? Letter)> cells)
    {
        if (word.Length != cells.Count)
        {
            return false;
        }

        for (var i = 0; i < word.Length; i++)
        {
            if (cells[i].Letter is { } letter && word[i] != letter)
            {
                return false;
            }
        }

        return true;
    }

    private static string WordText(Board board, BoardWord word)
    {
        return new string(word.Cells.Select(cell => board[cell.Row, cell.Column].Letter ?? cell.Letter).ToArray());
    }

    private sealed record RepairCandidate(Board Board, IReadOnlyList<BoardRepair> Repairs, double Score, int InvalidWordReduction);

    private readonly record struct LetterOption(char Letter, double Score, bool Changed);
}
