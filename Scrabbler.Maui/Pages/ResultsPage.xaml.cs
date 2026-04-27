using Scrabbler.Maui.ViewModels;

namespace Scrabbler.Maui.Pages;

public partial class ResultsPage : ContentPage
{
    private const int BoardSize = 15;

    public ResultsPage(ResultsViewModel viewModel)
    {
        InitializeComponent();
        BindingContext = viewModel;
        SizeChanged += (_, _) => ResizeBoard();
        CreateBoardDefinitions();
    }

    private void CreateBoardDefinitions()
    {
        PreviewBoardGrid.RowDefinitions.Clear();
        PreviewBoardGrid.ColumnDefinitions.Clear();
        for (var i = 0; i <= BoardSize; i++)
        {
            PreviewBoardGrid.RowDefinitions.Add(new RowDefinition(GridLength.Star));
            PreviewBoardGrid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        }
    }

    private void ResizeBoard()
    {
        if (Width <= 0 || Height <= 0)
        {
            return;
        }

        var availableWidth = Math.Max(220, Width - 32);
        var availableHeight = Math.Max(220, Height * 0.46);
        var side = Math.Floor(Math.Min(availableWidth, availableHeight));
        PreviewBoardHost.WidthRequest = side;
        PreviewBoardHost.HeightRequest = side;
        PreviewBoardGrid.WidthRequest = side;
        PreviewBoardGrid.HeightRequest = side;
    }
}
