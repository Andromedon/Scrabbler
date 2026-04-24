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
    private bool _isSolving;

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

    public bool IsSolving
    {
        get => _isSolving;
        private set => SetProperty(ref _isSolving, value);
    }

    public ICommand SolveCommand { get; }

    private async Task SolveAsync()
    {
        try
        {
            IsSolving = true;
            Message = "Solving...";
            await Task.Yield();
            await _workflow.SolveAsync(RackText);
            Message = BuildTimingMessage();
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
        finally
        {
            IsSolving = false;
        }
    }

    private string BuildTimingMessage()
    {
        var session = _services.GetRequiredService<ScrabblerSession>();
        var parts = new List<string>();
        if (session.Performance.AssetPreparation is not null)
        {
            parts.Add($"Assets: {session.Performance.AssetPreparation.Value.TotalSeconds:0.00}s");
        }

        if (session.Performance.ImageImport is not null)
        {
            parts.Add($"Image import: {session.Performance.ImageImport.Value.TotalSeconds:0.00}s");
        }

        if (session.Performance.DictionaryLoad is not null)
        {
            var cacheLabel = session.Performance.DictionaryCacheWarm ? "warm cache" : "cold cache";
            parts.Add($"Dictionary: {session.Performance.DictionaryLoad.Value.TotalSeconds:0.00}s ({cacheLabel})");
        }
        else if (session.Performance.DictionaryReady)
        {
            parts.Add("Dictionary: already loaded");
        }

        if (session.Performance.SolverConstruction is not null)
        {
            parts.Add($"Solver: {session.Performance.SolverConstruction.Value.TotalSeconds:0.00}s");
        }

        if (session.Performance.Solve is not null)
        {
            parts.Add($"Solve: {session.Performance.Solve.Value.TotalSeconds:0.00}s");
        }

        return string.Join(Environment.NewLine, parts);
    }
}
