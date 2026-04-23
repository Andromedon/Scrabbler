using System.Windows.Input;
using Microsoft.Extensions.DependencyInjection;
using Scrabbler.Maui.Pages;
using Scrabbler.Maui.Services;

namespace Scrabbler.Maui.ViewModels;

public sealed class RackInputViewModel : ObservableObject
{
    private readonly IServiceProvider _services;
    private readonly ScrabblerWorkflowService _workflow;
    private readonly NavigationService _navigation;
    private string _rackText = string.Empty;
    private string _message = string.Empty;

    public RackInputViewModel(IServiceProvider services, ScrabblerWorkflowService workflow, NavigationService navigation)
    {
        _services = services;
        _workflow = workflow;
        _navigation = navigation;
        SolveCommand = new AsyncCommand(SolveAsync);
    }

    public string RackText
    {
        get => _rackText;
        set => SetProperty(ref _rackText, value);
    }

    public string Message
    {
        get => _message;
        private set => SetProperty(ref _message, value);
    }

    public ICommand SolveCommand { get; }

    private async Task SolveAsync()
    {
        try
        {
            _workflow.Solve(RackText);
            Message = string.Empty;
            await _navigation.PushAsync(_services.GetRequiredService<ResultsPage>());
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
}
