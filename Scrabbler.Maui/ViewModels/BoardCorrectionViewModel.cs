using System.Windows.Input;
using Microsoft.Extensions.DependencyInjection;
using Scrabbler.Maui.Pages;
using Scrabbler.Maui.Services;

namespace Scrabbler.Maui.ViewModels;

public sealed class BoardCorrectionViewModel : ObservableObject
{
    private readonly IServiceProvider _services;
    private readonly ScrabblerSession _session;
    private readonly ScrabblerWorkflowService _workflow;
    private readonly NavigationService _navigation;
    private string _boardText = string.Empty;
    private IReadOnlyList<string> _boardLines = Array.Empty<string>();
    private string _detectedCellsText = string.Empty;
    private string _corrections = string.Empty;
    private string _message = string.Empty;

    public BoardCorrectionViewModel(IServiceProvider services, ScrabblerSession session, ScrabblerWorkflowService workflow, NavigationService navigation)
    {
        _services = services;
        _session = session;
        _workflow = workflow;
        _navigation = navigation;
        ApplyCommand = new Command(Apply);
        ContinueCommand = new AsyncCommand(ContinueAsync);
        Refresh();
    }

    public string BoardText
    {
        get => _boardText;
        private set => SetProperty(ref _boardText, value);
    }

    public IReadOnlyList<string> BoardLines
    {
        get => _boardLines;
        private set => SetProperty(ref _boardLines, value);
    }

    public string DetectedCellsText
    {
        get => _detectedCellsText;
        private set => SetProperty(ref _detectedCellsText, value);
    }

    public string Corrections
    {
        get => _corrections;
        set => SetProperty(ref _corrections, value);
    }

    public string Message
    {
        get => _message;
        private set => SetProperty(ref _message, value);
    }

    public ICommand ApplyCommand { get; }

    public ICommand ContinueCommand { get; }

    private void Apply()
    {
        try
        {
            _workflow.ApplyCorrections(Corrections);
            Corrections = string.Empty;
            Message = "Corrections applied.";
            RefreshBoard();
        }
        catch (ArgumentException ex)
        {
            Message = ex.Message;
        }
        catch (InvalidOperationException ex)
        {
            Message = ex.Message;
        }
    }

    private async Task ContinueAsync()
    {
        if (!string.IsNullOrWhiteSpace(Corrections))
        {
            Apply();
            if (!string.IsNullOrWhiteSpace(Corrections))
            {
                return;
            }
        }

        await _navigation.PushAsync(_services.GetRequiredService<RackInputPage>());
    }

    private void Refresh()
    {
        RefreshBoard();
        var occupied = _session.Cells
            .Where(cell => cell.IsOccupied)
            .Select(cell => $"{(char)('A' + cell.Column)}{cell.Row + 1}={(cell.Letter?.ToString() ?? "?")} ({cell.Confidence:P0})")
            .ToArray();
        var uncertain = _session.Cells
            .Where(cell => cell.IsOccupied && (cell.Letter is null || cell.Confidence < 0.70f))
            .Select(cell => $"{(char)('A' + cell.Column)}{cell.Row + 1}")
            .ToArray();

        DetectedCellsText = occupied.Length == 0
            ? "No occupied tile cells were detected automatically."
            : $"Detected: {string.Join(", ", occupied)}"
                + (uncertain.Length == 0 ? string.Empty : $"{Environment.NewLine}Review: {string.Join(", ", uncertain)}");

        if (!string.IsNullOrWhiteSpace(_session.AssetWarning))
        {
            Message = _session.AssetWarning;
        }

        var boardRead = _session.Performance.BoardRead;
        if (boardRead is not null)
        {
            Message = string.IsNullOrWhiteSpace(Message)
                ? $"Board read: {boardRead.Value.TotalSeconds:0.00}s"
                : $"{Message}{Environment.NewLine}Board read: {boardRead.Value.TotalSeconds:0.00}s";
        }
    }

    private void RefreshBoard()
    {
        BoardText = _session.Board?.Render() ?? string.Empty;
        BoardLines = BoardText
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .ToArray();
    }
}
