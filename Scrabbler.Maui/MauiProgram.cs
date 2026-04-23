using Scrabbler.Maui.Pages;
using Scrabbler.Maui.Services;
using Scrabbler.Maui.ViewModels;

namespace Scrabbler.Maui;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder();
        builder.UseMauiApp<App>();

        builder.Services.AddSingleton<ScrabblerSession>();
        builder.Services.AddSingleton<MauiAssetService>();
        builder.Services.AddSingleton<IPhotoImportService, PhotoImportService>();
        builder.Services.AddSingleton<NavigationService>();
        builder.Services.AddSingleton<IGoogleDriveSettingsProvider, GoogleDriveSettingsProvider>();
        builder.Services.AddSingleton<MauiGoogleDriveClient>();
        builder.Services.AddSingleton<ScrabblerWorkflowService>();

        builder.Services.AddTransient<HomeViewModel>();
        builder.Services.AddTransient<BoardCorrectionViewModel>();
        builder.Services.AddTransient<RackInputViewModel>();
        builder.Services.AddTransient<ResultsViewModel>();

        builder.Services.AddTransient<HomePage>();
        builder.Services.AddTransient<BoardCorrectionPage>();
        builder.Services.AddTransient<RackInputPage>();
        builder.Services.AddTransient<ResultsPage>();

        return builder.Build();
    }
}
