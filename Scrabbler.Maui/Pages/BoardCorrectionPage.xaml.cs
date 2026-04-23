using Scrabbler.Maui.ViewModels;

namespace Scrabbler.Maui.Pages;

public partial class BoardCorrectionPage : ContentPage
{
    public BoardCorrectionPage(BoardCorrectionViewModel viewModel)
    {
        InitializeComponent();
        BindingContext = viewModel;
    }
}
