namespace Scrabbler.App.ImageAnalysis;

public interface IGoogleDriveClient
{
    Task<IReadOnlyList<GoogleDriveImageFile>> ListFilesAsync(string folderId, CancellationToken cancellationToken = default);

    Task DownloadFileAsync(string fileId, string destinationPath, CancellationToken cancellationToken = default);
}
