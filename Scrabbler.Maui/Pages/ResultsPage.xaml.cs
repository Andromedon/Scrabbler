using Scrabbler.Maui.ViewModels;

namespace Scrabbler.Maui.Pages;

public partial class ResultsPage : ContentPage
{
    public ResultsPage(ResultsViewModel viewModel)
    {
        InitializeComponent();
        BindingContext = viewModel;
    }
}
