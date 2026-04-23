using Scrabbler.Maui.ViewModels;

namespace Scrabbler.Maui.Pages;

public partial class RackInputPage : ContentPage
{
    public RackInputPage(RackInputViewModel viewModel)
    {
        InitializeComponent();
        BindingContext = viewModel;
    }
}
