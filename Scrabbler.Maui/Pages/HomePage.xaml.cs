using Scrabbler.Maui.ViewModels;

namespace Scrabbler.Maui.Pages;

public partial class HomePage : ContentPage
{
    public HomePage(HomeViewModel viewModel)
    {
        InitializeComponent();
        BindingContext = viewModel;
    }
}
