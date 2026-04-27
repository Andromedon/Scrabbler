using Scrabbler.Maui.ViewModels;

namespace Scrabbler.Maui.Pages;

public partial class BoardCorrectionPage : ContentPage
{
    private const int BoardSize = 15;

    public BoardCorrectionPage(BoardCorrectionViewModel viewModel)
    {
        InitializeComponent();
        BindingContext = viewModel;
        viewModel.CorrectionInputRequested += OnCorrectionInputRequested;
        SizeChanged += (_, _) => ResizeBoard();
        CreateBoardDefinitions();
    }

    private void OnCorrectionInputRequested()
    {
        Dispatcher.Dispatch(async () =>
        {
            await Task.Delay(50);
            CorrectionsEntry.Focus();
        });
    }

    private void CreateBoardDefinitions()
    {
        BoardGrid.RowDefinitions.Clear();
        BoardGrid.ColumnDefinitions.Clear();
        for (var i = 0; i <= BoardSize; i++)
        {
            BoardGrid.RowDefinitions.Add(new RowDefinition(GridLength.Star));
            BoardGrid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        }
    }

    private void ResizeBoard()
    {
        if (Width <= 0 || Height <= 0)
        {
            return;
        }

        var reservedHeight = 260;
        var availableWidth = Math.Max(220, Width - 32);
        var availableHeight = Math.Max(220, Height - reservedHeight);
        var side = Math.Floor(Math.Min(availableWidth, availableHeight));
        BoardHost.WidthRequest = side;
        BoardHost.HeightRequest = side;
        BoardGrid.WidthRequest = side;
        BoardGrid.HeightRequest = side;
    }
}
