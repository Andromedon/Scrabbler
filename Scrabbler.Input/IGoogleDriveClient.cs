namespace Scrabbler.Input;

public interface IGoogleDriveClient
{
    Task<IReadOnlyList<GoogleDriveImageFile>> ListFilesAsync(string folderId, CancellationToken cancellationToken = default);

    Task DownloadFileAsync(string fileId, string destinationPath, CancellationToken cancellationToken = default);
}
