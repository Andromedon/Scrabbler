using System.Text.Json;
using System.Xml.Linq;

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
            try
            {
                await using var stream = await FileSystem.OpenAppPackageFileAsync("console-appsettings.json");
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
    }

    private static async Task<(string ClientId, string? ClientSecret, string RedirectUri)> ReadOAuthSettingsAsync(CancellationToken cancellationToken)
    {
        try
        {
            await using var stream = await FileSystem.OpenAppPackageFileAsync("google-drive-ios-client.plist");
            return await ParseIosOAuthSettingsAsync(stream, cancellationToken);
        }
        catch (FileNotFoundException)
        {
        }

        try
        {
            await using var stream = await FileSystem.OpenAppPackageFileAsync("google-drive-client-secret.json");
            return await ParseOAuthSettingsAsync(stream, cancellationToken);
        }
        catch (FileNotFoundException)
        {
            throw new FileNotFoundException(
                "Google Drive OAuth settings are missing. Add Scrabbler.Maui/Resources/Raw/google-drive-ios-client.plist or google-drive-client-secret.json before building the app.");
        }
    }

    private static async Task<(string ClientId, string? ClientSecret, string RedirectUri)> ParseIosOAuthSettingsAsync(Stream stream, CancellationToken cancellationToken)
    {
        using var reader = new StreamReader(stream);
        var xml = await reader.ReadToEndAsync(cancellationToken);
        var document = XDocument.Parse(xml);
        var dict = document.Root?
            .Element("dict")
            ?.Elements()
            .ToArray() ?? Array.Empty<XElement>();

        string? ValueFor(string key)
        {
            for (var i = 0; i < dict.Length - 1; i++)
            {
                if (dict[i].Name.LocalName == "key" && string.Equals(dict[i].Value, key, StringComparison.Ordinal))
                {
                    return dict[i + 1].Value;
                }
            }

            return null;
        }

        var clientId = ValueFor("CLIENT_ID") ?? string.Empty;
        if (string.IsNullOrWhiteSpace(clientId))
        {
            throw new InvalidOperationException("Google iOS OAuth plist is missing CLIENT_ID.");
        }

        var reversedClientId = ValueFor("REVERSED_CLIENT_ID") ?? string.Empty;
        if (string.IsNullOrWhiteSpace(reversedClientId))
        {
            throw new InvalidOperationException("Google iOS OAuth plist is missing REVERSED_CLIENT_ID.");
        }

        return (clientId, null, $"{reversedClientId}:/oauth2redirect");
    }

    private static async Task<(string ClientId, string? ClientSecret, string RedirectUri)> ParseOAuthSettingsAsync(Stream stream, CancellationToken cancellationToken)
    {
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

        return "com.googleusercontent.apps.11447514840-baio9i12tr0ie8rvr31n2bvpavl8l7kd:/oauth2redirect";
    }
}
