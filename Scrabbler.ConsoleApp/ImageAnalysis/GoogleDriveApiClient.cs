using Google.Apis.Auth.OAuth2;
using Google.Apis.Drive.v3;
using Google.Apis.Services;
using Google.Apis.Util.Store;
using DriveFile = Google.Apis.Drive.v3.Data.File;

namespace Scrabbler.App.ImageAnalysis;

public sealed class GoogleDriveApiClient : IGoogleDriveClient
{
    private static readonly string[] Scopes = { DriveService.Scope.DriveReadonly };

    private readonly string _credentialsPath;
    private readonly string _tokenDirectory;
    private readonly string _applicationName;
    private DriveService? _driveService;

    public GoogleDriveApiClient(string credentialsPath, string tokenDirectory, string applicationName)
    {
        _credentialsPath = credentialsPath;
        _tokenDirectory = tokenDirectory;
        _applicationName = applicationName;
    }

    public async Task<IReadOnlyList<GoogleDriveImageFile>> ListFilesAsync(string folderId, CancellationToken cancellationToken = default)
    {
        var service = await GetDriveServiceAsync(cancellationToken);
        var files = new List<GoogleDriveImageFile>();
        string? pageToken = null;

        do
        {
            var request = service.Files.List();
            request.Q = $"'{EscapeQueryValue(folderId)}' in parents and trashed = false";
            request.Fields = "nextPageToken, files(id, name, modifiedTime, mimeType)";
            request.PageSize = 1000;
            request.OrderBy = "modifiedTime desc,name";
            request.PageToken = pageToken;

            var response = await request.ExecuteAsync(cancellationToken);
            foreach (var file in response.Files ?? Array.Empty<DriveFile>())
            {
                if (string.IsNullOrWhiteSpace(file.Id) || string.IsNullOrWhiteSpace(file.Name))
                {
                    continue;
                }

                files.Add(new GoogleDriveImageFile(
                    file.Id,
                    file.Name,
                    file.ModifiedTimeDateTimeOffset ?? DateTimeOffset.MinValue,
                    file.MimeType));
            }

            pageToken = response.NextPageToken;
        }
        while (!string.IsNullOrWhiteSpace(pageToken));

        return files;
    }

    public async Task DownloadFileAsync(string fileId, string destinationPath, CancellationToken cancellationToken = default)
    {
        var service = await GetDriveServiceAsync(cancellationToken);
        await using var stream = File.Create(destinationPath);
        var request = service.Files.Get(fileId);
        var result = await request.DownloadAsync(stream, cancellationToken);

        if (result.Exception is not null)
        {
            throw new InvalidOperationException($"Failed to download Google Drive file '{fileId}': {result.Exception.Message}", result.Exception);
        }
    }

    private async Task<DriveService> GetDriveServiceAsync(CancellationToken cancellationToken)
    {
        if (_driveService is not null)
        {
            return _driveService;
        }

        if (!File.Exists(_credentialsPath))
        {
            throw new FileNotFoundException(
                $"Google Drive OAuth client secret file was not found: {_credentialsPath}",
                _credentialsPath);
        }

        Directory.CreateDirectory(_tokenDirectory);
        await using var stream = File.OpenRead(_credentialsPath);
        var secrets = GoogleClientSecrets.FromStream(stream).Secrets;
        var credential = await GoogleWebAuthorizationBroker.AuthorizeAsync(
            secrets,
            Scopes,
            "user",
            cancellationToken,
            new FileDataStore(_tokenDirectory, fullPath: true));

        _driveService = new DriveService(new BaseClientService.Initializer
        {
            HttpClientInitializer = credential,
            ApplicationName = _applicationName
        });

        return _driveService;
    }

    private static string EscapeQueryValue(string value)
    {
        return value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("'", "\\'", StringComparison.Ordinal);
    }
}
