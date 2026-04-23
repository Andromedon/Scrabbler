using System.Windows.Input;
using Scrabbler.Domain.BoardModel;
using Scrabbler.Maui.Services;
using Scrabbler.Solver;

namespace Scrabbler.Maui.ViewModels;

public sealed class ResultsViewModel : ObservableObject
{
    private readonly ScrabblerSession _session;
    private readonly NavigationService _navigation;

    public ResultsViewModel(ScrabblerSession session, NavigationService navigation)
    {
        _session = session;
        _navigation = navigation;
        FinishCommand = new AsyncCommand(FinishAsync);
        ResultsText = FormatMoves(session.Moves);
    }

    public string ResultsText { get; }

    public ICommand FinishCommand { get; }

    private async Task FinishAsync()
    {
        _session.Clear();
        await _navigation.PopToRootAsync();
    }

    private static string FormatMoves(IReadOnlyList<Move> moves)
    {
        if (moves.Count == 0)
        {
            return "No legal move found for this rack and board.";
        }

        return string.Join(Environment.NewLine + Environment.NewLine, moves
            .OrderByDescending(move => move.Score)
            .Select(move =>
            {
                var column = (char)('A' + move.Column);
                var direction = move.Direction == Direction.Horizontal ? "horizontal" : "vertical";
                var placed = string.Join(", ", move.PlacedTiles.Select(tile => $"{(char)('A' + tile.Column)}{tile.Row + 1}={tile.Letter}{(tile.IsBlank ? "?" : "")}"));
                var crosses = move.CrossWords.Count == 0 ? "-" : string.Join(", ", move.CrossWords);
                return $"{move.Score,3}  {move.Word} at {column}{move.Row + 1} {direction}{Environment.NewLine}placed: {placed}{Environment.NewLine}crosses: {crosses}";
            }));
    }
}
