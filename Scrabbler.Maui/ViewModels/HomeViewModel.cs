using System.Windows.Input;
using Microsoft.Extensions.DependencyInjection;
using Scrabbler.Maui.Pages;
using Scrabbler.Maui.Services;

namespace Scrabbler.Maui.ViewModels;

public sealed class HomeViewModel : ObservableObject
{
    private readonly IServiceProvider _services;
    private readonly IPhotoImportService _photoImportService;
    private readonly MauiGoogleDriveClient _googleDriveClient;
    private readonly ScrabblerWorkflowService _workflow;
    private readonly NavigationService _navigation;
    private string _status = string.Empty;
    private string _dictionaryStatus = string.Empty;
    private bool _isBusy;

    public HomeViewModel(
        IServiceProvider services,
        IPhotoImportService photoImportService,
        MauiGoogleDriveClient googleDriveClient,
        ScrabblerWorkflowService workflow,
        NavigationService navigation)
    {
        _services = services;
        _photoImportService = photoImportService;
        _googleDriveClient = googleDriveClient;
        _workflow = workflow;
        _navigation = navigation;
        LoadFromGalleryCommand = new AsyncCommand(LoadFromGalleryAsync);
        DownloadFromGoogleDriveCommand = new AsyncCommand(DownloadFromGoogleDriveAsync);
        WarmDictionaryCommand = new AsyncCommand(WarmDictionaryAsync);
        _ = RefreshDictionaryStatusAsync();
    }

    public string Status
    {
        get => _status;
        private set => SetProperty(ref _status, value);
    }

    public string DictionaryStatus
    {
        get => _dictionaryStatus;
        private set => SetProperty(ref _dictionaryStatus, value);
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set => SetProperty(ref _isBusy, value);
    }

    public ICommand LoadFromGalleryCommand { get; }

    public ICommand DownloadFromGoogleDriveCommand { get; }

    public ICommand WarmDictionaryCommand { get; }

    private async Task LoadFromGalleryAsync()
    {
        await RunImageFlowAsync(async () => await _photoImportService.PickPhotoAsync());
    }

    private async Task DownloadFromGoogleDriveAsync()
    {
        await RunImageFlowAsync(async () => await _googleDriveClient.DownloadNewestImageAsync(
            Path.Combine(FileSystem.CacheDirectory, "GoogleDrive")));
    }

    private async Task RunImageFlowAsync(Func<Task<FileInfo?>> getImage)
    {
        try
        {
            IsBusy = true;
            Status = "Loading image...";
            var image = await getImage();
            if (image is null)
            {
                Status = string.Empty;
                return;
            }

            Status = "Reading board...";
            await Task.Yield();
            await _workflow.ReadBoardAsync(image.FullName);
            Status = string.Empty;
            await _navigation.PushAsync(_services.GetRequiredService<BoardCorrectionPage>());
        }
        catch (Exception ex)
        {
            Status = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task WarmDictionaryAsync()
    {
        try
        {
            IsBusy = true;
            Status = "Loading dictionary...";
            await _workflow.WarmDictionaryAsync();
            Status = string.Empty;
            await RefreshDictionaryStatusAsync();
        }
        catch (Exception ex)
        {
            Status = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task RefreshDictionaryStatusAsync()
    {
        var cached = await _workflow.IsDictionaryCachedAsync();
        DictionaryStatus = cached
            ? "Dictionary cache is available."
            : "Dictionary cache is not built yet.";
    }
}
