using System.Net.Http.Headers;
using System.Text.Json;
using Scrabbler.Input;

namespace Scrabbler.Maui.Services;

public sealed class MauiGoogleDriveClient : IGoogleDriveClient
{
    private const string Scope = "https://www.googleapis.com/auth/drive.readonly";
    private const string RefreshTokenKey = "google-drive-refresh-token";
    private readonly IGoogleDriveSettingsProvider _settingsProvider;
    private readonly HttpClient _httpClient = new();
    private GoogleDriveSettings? _settings;
    private string? _accessToken;

    public MauiGoogleDriveClient(IGoogleDriveSettingsProvider settingsProvider)
    {
        _settingsProvider = settingsProvider;
    }

    public async Task<IReadOnlyList<GoogleDriveImageFile>> ListFilesAsync(string folderId, CancellationToken cancellationToken = default)
    {
        var token = await GetAccessTokenAsync(cancellationToken);
        var files = new List<GoogleDriveImageFile>();
        string? pageToken = null;
        do
        {
            var query = Uri.EscapeDataString($"'{EscapeQueryValue(folderId)}' in parents and trashed = false");
            var url = "https://www.googleapis.com/drive/v3/files"
                + $"?q={query}&fields=nextPageToken,files(id,name,modifiedTime,mimeType)"
                + "&pageSize=1000&orderBy=modifiedTime%20desc,name";
            if (!string.IsNullOrWhiteSpace(pageToken))
            {
                url += $"&pageToken={Uri.EscapeDataString(pageToken)}";
            }

            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var response = await _httpClient.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);

            if (document.RootElement.TryGetProperty("files", out var fileElements))
            {
                foreach (var file in fileElements.EnumerateArray())
                {
                    var id = file.GetProperty("id").GetString();
                    var name = file.GetProperty("name").GetString();
                    if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(name))
                    {
                        continue;
                    }

                    var modified = file.TryGetProperty("modifiedTime", out var modifiedElement)
                        && DateTimeOffset.TryParse(modifiedElement.GetString(), out var parsed)
                            ? parsed
                            : DateTimeOffset.MinValue;
                    var mimeType = file.TryGetProperty("mimeType", out var mimeElement)
                        ? mimeElement.GetString()
                        : null;
                    files.Add(new GoogleDriveImageFile(id, name, modified, mimeType));
                }
            }

            pageToken = document.RootElement.TryGetProperty("nextPageToken", out var nextPageToken)
                ? nextPageToken.GetString()
                : null;
        }
        while (!string.IsNullOrWhiteSpace(pageToken));

        return files;
    }

    public async Task DownloadFileAsync(string fileId, string destinationPath, CancellationToken cancellationToken = default)
    {
        var token = await GetAccessTokenAsync(cancellationToken);
        using var request = new HttpRequestMessage(HttpMethod.Get, $"https://www.googleapis.com/drive/v3/files/{Uri.EscapeDataString(fileId)}?alt=media");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var target = File.Create(destinationPath);
        await source.CopyToAsync(target, cancellationToken);
    }

    public async Task<FileInfo?> DownloadNewestImageAsync(string downloadDirectory, CancellationToken cancellationToken = default)
    {
        var settings = await EnsureSettingsAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(settings.FolderId))
        {
            throw new InvalidOperationException("GoogleDriveFolderId is missing. Add Scrabbler.Maui/Resources/Raw/google-drive-settings.json.");
        }

        var provider = new GoogleDriveInputImageProvider(this, settings.FolderId, downloadDirectory);
        return await provider.GetSelectedImageAsync(cancellationToken);
    }

    private async Task<string> GetAccessTokenAsync(CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(_accessToken))
        {
            return _accessToken;
        }

        var settings = await EnsureSettingsAsync(cancellationToken);
        var refreshToken = await SecureStorage.Default.GetAsync(RefreshTokenKey);
        if (!string.IsNullOrWhiteSpace(refreshToken))
        {
            _accessToken = await RefreshAccessTokenAsync(settings, refreshToken, cancellationToken);
            return _accessToken;
        }

        var authUrl = new Uri("https://accounts.google.com/o/oauth2/v2/auth"
            + $"?client_id={Uri.EscapeDataString(settings.ClientId)}"
            + $"&redirect_uri={Uri.EscapeDataString(settings.RedirectUri)}"
            + "&response_type=code"
            + $"&scope={Uri.EscapeDataString(Scope)}"
            + "&access_type=offline"
            + "&prompt=consent");
        var callback = new Uri(settings.RedirectUri);
        var authResult = await WebAuthenticator.Default.AuthenticateAsync(authUrl, callback);
        var code = authResult.Properties.TryGetValue("code", out var value) ? value : null;
        if (string.IsNullOrWhiteSpace(code))
        {
            throw new InvalidOperationException("Google Drive authorization did not return an authorization code.");
        }

        var token = await ExchangeCodeAsync(settings, code, cancellationToken);
        if (!string.IsNullOrWhiteSpace(token.RefreshToken))
        {
            await SecureStorage.Default.SetAsync(RefreshTokenKey, token.RefreshToken);
        }

        _accessToken = token.AccessToken;
        return _accessToken;
    }

    private async Task<GoogleDriveSettings> EnsureSettingsAsync(CancellationToken cancellationToken)
    {
        _settings ??= await _settingsProvider.LoadAsync(cancellationToken);
        return _settings;
    }

    private async Task<(string AccessToken, string? RefreshToken)> ExchangeCodeAsync(GoogleDriveSettings settings, string code, CancellationToken cancellationToken)
    {
        var values = CreateClientValues(settings);
        values["code"] = code;
        values["redirect_uri"] = settings.RedirectUri;
        values["grant_type"] = "authorization_code";
        return await SendTokenRequestAsync(values, cancellationToken);
    }

    private async Task<string> RefreshAccessTokenAsync(GoogleDriveSettings settings, string refreshToken, CancellationToken cancellationToken)
    {
        var values = CreateClientValues(settings);
        values["refresh_token"] = refreshToken;
        values["grant_type"] = "refresh_token";
        var token = await SendTokenRequestAsync(values, cancellationToken);
        return token.AccessToken;
    }

    private static Dictionary<string, string> CreateClientValues(GoogleDriveSettings settings)
    {
        var values = new Dictionary<string, string>
        {
            ["client_id"] = settings.ClientId
        };
        if (!string.IsNullOrWhiteSpace(settings.ClientSecret))
        {
            values["client_secret"] = settings.ClientSecret;
        }

        return values;
    }

    private async Task<(string AccessToken, string? RefreshToken)> SendTokenRequestAsync(Dictionary<string, string> values, CancellationToken cancellationToken)
    {
        using var response = await _httpClient.PostAsync("https://oauth2.googleapis.com/token", new FormUrlEncodedContent(values), cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var accessToken = document.RootElement.GetProperty("access_token").GetString();
        if (string.IsNullOrWhiteSpace(accessToken))
        {
            throw new InvalidOperationException("Google token response did not include an access token.");
        }

        var refreshToken = document.RootElement.TryGetProperty("refresh_token", out var refresh)
            ? refresh.GetString()
            : null;
        return (accessToken, refreshToken);
    }

    private static string EscapeQueryValue(string value)
    {
        return value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("'", "\\'", StringComparison.Ordinal);
    }
}
