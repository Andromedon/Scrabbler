using System.Windows.Input;
using Scrabbler.Domain.BoardModel;
using Scrabbler.Maui.Services;
using Scrabbler.Solver;

namespace Scrabbler.Maui.ViewModels;

public sealed record ResultMoveItem(string Summary, Move Move);

public sealed class ResultsViewModel : ObservableObject
{
    private readonly ScrabblerSession _session;
    private readonly NavigationService _navigation;
    private IReadOnlyList<BoardCellViewModel> _previewBoardCells = Array.Empty<BoardCellViewModel>();
    private ResultMoveItem? _selectedMove;

    public ResultsViewModel(ScrabblerSession session, NavigationService navigation)
    {
        _session = session;
        _navigation = navigation;
        FinishCommand = new AsyncCommand(FinishAsync);
        SelectMoveCommand = new Command<ResultMoveItem>(SelectMove);
        ResultItems = BuildResultItems(session.Moves);
        ResultsText = FormatMoves(session.Moves);
        SelectedMove = ResultItems.FirstOrDefault();
    }

    public string ResultsText { get; }

    public IReadOnlyList<ResultMoveItem> ResultItems { get; }

    public ResultMoveItem? SelectedMove
    {
        get => _selectedMove;
        private set
        {
            if (SetProperty(ref _selectedMove, value))
            {
                PreviewBoardCells = BuildPreviewBoardCells(value?.Move);
            }
        }
    }

    public IReadOnlyList<BoardCellViewModel> PreviewBoardCells
    {
        get => _previewBoardCells;
        private set => SetProperty(ref _previewBoardCells, value);
    }

    public ICommand FinishCommand { get; }

    public ICommand SelectMoveCommand { get; }

    private void SelectMove(ResultMoveItem? item)
    {
        if (item is not null)
        {
            SelectedMove = item;
        }
    }

    private async Task FinishAsync()
    {
        _session.Clear();
        await _navigation.PopToRootAsync();
    }

    private IReadOnlyList<BoardCellViewModel> BuildPreviewBoardCells(Move? move)
    {
        var board = _session.Board;
        if (board is null)
        {
            return Array.Empty<BoardCellViewModel>();
        }

        var placed = move?.PlacedTiles.ToDictionary(tile => (tile.Row, tile.Column)) ?? new Dictionary<(int Row, int Column), PlacedTile>();
        var cells = new List<BoardCellViewModel>((Board.Size + 1) * (Board.Size + 1))
        {
            new(0, 0, string.Empty, string.Empty, string.Empty, false, true, false, "#D8D0C1", "#151515")
        };

        for (var column = 0; column < Board.Size; column++)
        {
            cells.Add(new BoardCellViewModel(0, column + 1, string.Empty, ((char)('A' + column)).ToString(), string.Empty, false, true, false, "#D8D0C1", "#151515"));
        }

        for (var row = 0; row < Board.Size; row++)
        {
            cells.Add(new BoardCellViewModel(row + 1, 0, string.Empty, (row + 1).ToString(), string.Empty, false, true, false, "#D8D0C1", "#151515"));
            for (var column = 0; column < Board.Size; column++)
            {
                var isPlaced = placed.TryGetValue((row, column), out var placedTile);
                var letter = isPlaced
                    ? placedTile!.Letter.ToString()
                    : board[row, column].Letter?.ToString() ?? string.Empty;
                var occupied = !string.IsNullOrEmpty(letter);
                cells.Add(new BoardCellViewModel(
                    row + 1,
                    column + 1,
                    $"{(char)('A' + column)}{row + 1}",
                    letter,
                    string.Empty,
                    occupied,
                    false,
                    false,
                    isPlaced ? "#3FA86B" : occupied ? "#F2B247" : "#EEECEA",
                    "#151515"));
            }
        }

        return cells;
    }

    private static IReadOnlyList<ResultMoveItem> BuildResultItems(IReadOnlyList<Move> moves)
    {
        return moves
            .OrderByDescending(move => move.Score)
            .Select(move => new ResultMoveItem(FormatMove(move), move))
            .ToArray();
    }

    private static string FormatMoves(IReadOnlyList<Move> moves)
    {
        if (moves.Count == 0)
        {
            return "No legal move found for this rack and board.";
        }

        return string.Join(Environment.NewLine + Environment.NewLine, moves
            .OrderByDescending(move => move.Score)
            .Select(FormatMove));
    }

    private static string FormatMove(Move move)
    {
        var column = (char)('A' + move.Column);
        var direction = move.Direction == Direction.Horizontal ? "horizontal" : "vertical";
        var placed = string.Join(", ", move.PlacedTiles.Select(tile => $"{(char)('A' + tile.Column)}{tile.Row + 1}={tile.Letter}{(tile.IsBlank ? "?" : "")}"));
        var crosses = move.CrossWords.Count == 0 ? "-" : string.Join(", ", move.CrossWords);
        return $"{move.Score,3}  {move.Word} at {column}{move.Row + 1} {direction}{Environment.NewLine}placed: {placed}{Environment.NewLine}crosses: {crosses}";
    }
}
