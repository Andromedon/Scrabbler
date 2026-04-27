using System.Windows.Input;
using System.Globalization;
using Microsoft.Extensions.DependencyInjection;
using Scrabbler.Domain.BoardModel;
using Scrabbler.Maui.Pages;
using Scrabbler.Maui.Services;

namespace Scrabbler.Maui.ViewModels;

public sealed record QuickCorrectionItem(string Label, string CorrectionText);

public sealed record BoardCellViewModel(
    int GridRow,
    int GridColumn,
    string Coordinate,
    string Letter,
    string CorrectionPrefix,
    bool IsOccupied,
    bool IsHeader,
    bool IsEnabled,
    string BackgroundColor,
    string TextColor);

public sealed class BoardCorrectionViewModel : ObservableObject
{
    private readonly IServiceProvider _services;
    private readonly ScrabblerSession _session;
    private readonly ScrabblerWorkflowService _workflow;
    private readonly NavigationService _navigation;
    private string _boardText = string.Empty;
    private IReadOnlyList<string> _boardLines = Array.Empty<string>();
    private IReadOnlyList<BoardCellViewModel> _boardCells = Array.Empty<BoardCellViewModel>();
    private string _detectedCellsText = string.Empty;
    private string _reviewCellsText = string.Empty;
    private string _detectedToggleText = "Show detected letters";
    private IReadOnlyList<QuickCorrectionItem> _quickCorrections = Array.Empty<QuickCorrectionItem>();
    private bool _isDetectedCellsExpanded;
    private string _corrections = string.Empty;
    private string _message = string.Empty;

    public BoardCorrectionViewModel(IServiceProvider services, ScrabblerSession session, ScrabblerWorkflowService workflow, NavigationService navigation)
    {
        _services = services;
        _session = session;
        _workflow = workflow;
        _navigation = navigation;
        ApplyCommand = new Command(Apply);
        SelectBoardCellCommand = new Command<string>(SelectBoardCell);
        SelectQuickCorrectionCommand = new Command<string>(SelectQuickCorrection);
        ToggleDetectedCellsCommand = new Command(ToggleDetectedCells);
        ContinueCommand = new AsyncCommand(ContinueAsync);
        Refresh();
    }

    public event Action? CorrectionInputRequested;

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

    public IReadOnlyList<BoardCellViewModel> BoardCells
    {
        get => _boardCells;
        private set => SetProperty(ref _boardCells, value);
    }

    public string DetectedCellsText
    {
        get => _detectedCellsText;
        private set => SetProperty(ref _detectedCellsText, value);
    }

    public string ReviewCellsText
    {
        get => _reviewCellsText;
        private set => SetProperty(ref _reviewCellsText, value);
    }

    public string DetectedToggleText
    {
        get => _detectedToggleText;
        private set => SetProperty(ref _detectedToggleText, value);
    }

    public bool IsDetectedCellsExpanded
    {
        get => _isDetectedCellsExpanded;
        private set => SetProperty(ref _isDetectedCellsExpanded, value);
    }

    public IReadOnlyList<QuickCorrectionItem> QuickCorrections
    {
        get => _quickCorrections;
        private set => SetProperty(ref _quickCorrections, value);
    }

    public string Corrections
    {
        get => _corrections;
        set => SetProperty(ref _corrections, (value ?? string.Empty).ToUpper(new CultureInfo("pl-PL")));
    }

    public string Message
    {
        get => _message;
        private set => SetProperty(ref _message, value);
    }

    public ICommand ApplyCommand { get; }

    public ICommand SelectBoardCellCommand { get; }

    public ICommand SelectQuickCorrectionCommand { get; }

    public ICommand ToggleDetectedCellsCommand { get; }

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

    private void ToggleDetectedCells()
    {
        IsDetectedCellsExpanded = !IsDetectedCellsExpanded;
        DetectedToggleText = IsDetectedCellsExpanded ? "Hide detected letters ▲" : "Show detected letters ▼";
    }

    private void SelectQuickCorrection(string? correction)
    {
        if (string.IsNullOrWhiteSpace(correction))
        {
            return;
        }

        Corrections = string.IsNullOrWhiteSpace(Corrections)
            ? correction
            : $"{Corrections}, {correction}";
        CorrectionInputRequested?.Invoke();
    }

    private void SelectBoardCell(string? correctionPrefix)
    {
        if (string.IsNullOrWhiteSpace(correctionPrefix))
        {
            return;
        }

        Corrections = correctionPrefix;
        CorrectionInputRequested?.Invoke();
    }

    private void Refresh()
    {
        RefreshBoard();
        var occupied = _session.Cells
            .Where(cell => cell.IsOccupied)
            .Select(cell => $"{(char)('A' + cell.Column)}{cell.Row + 1}={(cell.Letter?.ToString() ?? "?")} ({cell.Confidence:P0})")
            .ToArray();
        var repairs = _session.Repairs
            .Select(repair => $"{Coordinate(repair.Row, repair.Column)}={(repair.From?.ToString() ?? "?")}→{repair.To}")
            .ToArray();

        DetectedCellsText = occupied.Length == 0
            ? "No occupied tile cells were detected automatically."
            : string.Join(", ", occupied);
        ReviewCellsText = repairs.Length == 0
            ? "Review: none"
            : $"Review: {string.Join(", ", repairs)}";
        QuickCorrections = BuildQuickCorrections();
        DetectedToggleText = IsDetectedCellsExpanded ? "Hide detected letters ▲" : "Show detected letters ▼";

        if (!string.IsNullOrWhiteSpace(_session.AssetWarning))
        {
            Message = _session.AssetWarning;
        }

        if (_session.Repairs.Count > 0)
        {
            var repairMessage = string.Join(", ", _session.Repairs.Select(repair =>
                $"{(char)('A' + repair.Column)}{repair.Row + 1}={(repair.From?.ToString() ?? "?")}→{repair.To}"));
            Message = string.IsNullOrWhiteSpace(Message)
                ? $"OCR repaired: {repairMessage}"
                : $"{Message}{Environment.NewLine}OCR repaired: {repairMessage}";
        }

        var assetPreparation = _session.Performance.AssetPreparation;
        if (assetPreparation is not null)
        {
            Message = string.IsNullOrWhiteSpace(Message)
                ? $"Assets: {assetPreparation.Value.TotalSeconds:0.00}s"
                : $"{Message}{Environment.NewLine}Assets: {assetPreparation.Value.TotalSeconds:0.00}s";
        }

        var imageImport = _session.Performance.ImageImport;
        if (imageImport is not null)
        {
            Message = string.IsNullOrWhiteSpace(Message)
                ? $"Image import: {imageImport.Value.TotalSeconds:0.00}s"
                : $"{Message}{Environment.NewLine}Image import: {imageImport.Value.TotalSeconds:0.00}s";
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
        BoardCells = BuildBoardCells();
    }

    private IReadOnlyList<BoardCellViewModel> BuildBoardCells()
    {
        var board = _session.Board;
        if (board is null)
        {
            return Array.Empty<BoardCellViewModel>();
        }

        var cells = new List<BoardCellViewModel>((Board.Size + 1) * (Board.Size + 1))
        {
            new(0, 0, string.Empty, string.Empty, string.Empty, false, true, false, "#D8D0C1", "#151515")
        };
        for (var column = 0; column < Board.Size; column++)
        {
            cells.Add(new BoardCellViewModel(
                0,
                column + 1,
                string.Empty,
                ((char)('A' + column)).ToString(),
                string.Empty,
                false,
                true,
                false,
                "#D8D0C1",
                "#151515"));
        }

        for (var row = 0; row < Board.Size; row++)
        {
            cells.Add(new BoardCellViewModel(
                row + 1,
                0,
                string.Empty,
                (row + 1).ToString(),
                string.Empty,
                false,
                true,
                false,
                "#D8D0C1",
                "#151515"));

            for (var column = 0; column < Board.Size; column++)
            {
                var coordinate = Coordinate(row, column);
                var letter = board[row, column].Letter?.ToString() ?? string.Empty;
                var isOccupied = !string.IsNullOrEmpty(letter);
                cells.Add(new BoardCellViewModel(
                    row + 1,
                    column + 1,
                    coordinate,
                    letter,
                    $"{coordinate}=",
                    isOccupied,
                    false,
                    true,
                    isOccupied ? "#F2B247" : "#EEECEA",
                    "#151515"));
            }
        }

        return cells;
    }

    private IReadOnlyList<QuickCorrectionItem> BuildQuickCorrections()
    {
        var items = new List<QuickCorrectionItem>();
        foreach (var repair in _session.Repairs)
        {
            var coordinate = Coordinate(repair.Row, repair.Column);
            items.Add(new QuickCorrectionItem(
                $"{coordinate} {(repair.From?.ToString() ?? "?")}→{repair.To}",
                $"{coordinate}={repair.To}"));
        }

        return items;
    }

    private static string Coordinate(int row, int column)
    {
        return $"{(char)('A' + column)}{row + 1}";
    }
}
