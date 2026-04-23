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
    }

    public string Status
    {
        get => _status;
        private set => SetProperty(ref _status, value);
    }

    public ICommand LoadFromGalleryCommand { get; }

    public ICommand DownloadFromGoogleDriveCommand { get; }

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
            Status = "Loading image...";
            var image = await getImage();
            if (image is null)
            {
                Status = string.Empty;
                return;
            }

            Status = "Reading board...";
            await _workflow.ReadBoardAsync(image.FullName);
            Status = string.Empty;
            await _navigation.PushAsync(_services.GetRequiredService<BoardCorrectionPage>());
        }
        catch (Exception ex)
        {
            Status = ex.Message;
        }
    }

}
