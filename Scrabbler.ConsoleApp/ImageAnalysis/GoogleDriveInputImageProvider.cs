using Scrabbler.Input;

namespace Scrabbler.App.ImageAnalysis;

public sealed class GoogleDriveInputImageProvider : IInputImageProvider
{
    private readonly IGoogleDriveClient _client;
    private readonly string _folderId;
    private readonly string _downloadDirectory;

    public GoogleDriveInputImageProvider(IGoogleDriveClient client, string folderId, string downloadDirectory)
    {
        _client = client;
        _folderId = folderId;
        _downloadDirectory = downloadDirectory;
    }

    public async Task<FileInfo?> GetSelectedImageAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_folderId))
        {
            throw new InvalidOperationException("GoogleDriveFolderId is required when InputSource is GoogleDrive.");
        }

        Directory.CreateDirectory(_downloadDirectory);

        var selectedFile = (await _client.ListFilesAsync(_folderId, cancellationToken))
            .Where(file => SupportedImageFiles.IsSupported(file.Name, file.MimeType))
            .OrderByDescending(file => file.ModifiedTime)
            .ThenBy(file => file.Name, StringComparer.OrdinalIgnoreCase)
            .ThenBy(file => file.Id, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();

        if (selectedFile is null)
        {
            return null;
        }

        var destinationPath = Path.Combine(
            _downloadDirectory,
            $"{selectedFile.ModifiedTime.UtcTicks}-{SanitizeFileName(selectedFile.Id)}-{SanitizeFileName(selectedFile.Name)}");

        await _client.DownloadFileAsync(selectedFile.Id, destinationPath, cancellationToken);
        return new FileInfo(destinationPath);
    }

    private static string SanitizeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        return string.Concat(value.Select(character => invalid.Contains(character) ? '_' : character));
    }
}
