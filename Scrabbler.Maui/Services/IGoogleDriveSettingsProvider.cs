namespace Scrabbler.Maui.Services;

public interface IGoogleDriveSettingsProvider
{
    Task<GoogleDriveSettings> LoadAsync(CancellationToken cancellationToken = default);
}
