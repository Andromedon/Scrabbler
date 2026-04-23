using System.Text.Json;

namespace Scrabbler.Maui.Services;

public sealed class GoogleDriveSettingsProvider : IGoogleDriveSettingsProvider
{
    public async Task<GoogleDriveSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        var folderId = await ReadFolderIdAsync(cancellationToken);
        var oauth = await ReadOAuthSettingsAsync(cancellationToken);
        return new GoogleDriveSettings(folderId, oauth.ClientId, oauth.ClientSecret, oauth.RedirectUri);
    }

    private static async Task<string> ReadFolderIdAsync(CancellationToken cancellationToken)
    {
        try
        {
            await using var stream = await FileSystem.OpenAppPackageFileAsync("google-drive-settings.json");
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
            return document.RootElement.TryGetProperty("GoogleDriveFolderId", out var folder)
                ? folder.GetString() ?? string.Empty
                : string.Empty;
        }
        catch (FileNotFoundException)
        {
            return string.Empty;
        }
    }

    private static async Task<(string ClientId, string? ClientSecret, string RedirectUri)> ReadOAuthSettingsAsync(CancellationToken cancellationToken)
    {
        await using var stream = await FileSystem.OpenAppPackageFileAsync("google-drive-client-secret.json");
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var root = document.RootElement;
        var section = TryGetSection(root, "installed")
            ?? TryGetSection(root, "ios")
            ?? TryGetSection(root, "web")
            ?? root;

        var clientId = section.TryGetProperty("client_id", out var clientIdElement)
            ? clientIdElement.GetString() ?? string.Empty
            : string.Empty;
        if (string.IsNullOrWhiteSpace(clientId))
        {
            throw new InvalidOperationException("Google Drive OAuth client_id is missing.");
        }

        var clientSecret = section.TryGetProperty("client_secret", out var secretElement)
            ? secretElement.GetString()
            : null;
        var redirectUri = ReadRedirectUri(section, clientId);
        return (clientId, clientSecret, redirectUri);
    }

    private static JsonElement? TryGetSection(JsonElement root, string name)
    {
        return root.TryGetProperty(name, out var section) ? section : null;
    }

    private static string ReadRedirectUri(JsonElement section, string clientId)
    {
        if (section.TryGetProperty("redirect_uris", out var uris) && uris.ValueKind == JsonValueKind.Array)
        {
            foreach (var uri in uris.EnumerateArray())
            {
                var value = uri.GetString();
                if (!string.IsNullOrWhiteSpace(value) && !value.StartsWith("http://localhost", StringComparison.OrdinalIgnoreCase))
                {
                    return value;
                }
            }
        }

        return "pl.scrabbler.app:/oauth2redirect";
    }
}
