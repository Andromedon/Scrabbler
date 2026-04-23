using Scrabbler.App.Configuration;
using Scrabbler.Input;

namespace Scrabbler.App.ImageAnalysis;

public static class InputImageProviderFactory
{
    public static IInputImageProvider Create(AppSettings settings)
    {
        return settings.InputSource switch
        {
            InputSource.Local => new FixedDirectoryInputImageProvider(settings.InputDirectory),
            InputSource.GoogleDrive => new GoogleDriveInputImageProvider(
                new GoogleDriveApiClient(
                    settings.GoogleDriveCredentialsPath,
                    settings.GoogleDriveTokenDirectory,
                    "Scrabbler"),
                settings.GoogleDriveFolderId,
                settings.GoogleDriveDownloadDirectory),
            _ => throw new InvalidOperationException($"Unsupported input source: {settings.InputSource}")
        };
    }
}
