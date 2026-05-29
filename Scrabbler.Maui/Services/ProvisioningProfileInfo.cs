using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

#if IOS
using Foundation;
#endif

namespace Scrabbler.Maui.Services;

internal static partial class ProvisioningProfileInfo
{
    public static string ExpirationFooterText()
    {
        var expiration = TryGetExpirationDate();
        if (expiration is null)
        {
            return "Provisioning expires: unavailable";
        }

        var utc = expiration.Value.ToUniversalTime();
        return $"Provisioning expires: {utc:yyyy-MM-dd HH:mm 'UTC'}";
    }

    private static DateTimeOffset? TryGetExpirationDate()
    {
        var path = FindEmbeddedProvisioningProfilePath();
        if (path is null || !File.Exists(path))
        {
            return null;
        }

        try
        {
            var bytes = File.ReadAllBytes(path);
            var text = Encoding.UTF8.GetString(bytes);
            var match = ExpirationDateRegex().Match(text);
            if (!match.Success)
            {
                text = Encoding.Latin1.GetString(bytes);
                match = ExpirationDateRegex().Match(text);
            }

            if (!match.Success)
            {
                return null;
            }

            var raw = match.Groups["value"].Value;
            if (DateTimeOffset.TryParse(
                    raw,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                    out var expiration))
            {
                return expiration;
            }
        }
        catch
        {
            return null;
        }

        return null;
    }

    private static string? FindEmbeddedProvisioningProfilePath()
    {
#if IOS
        return NSBundle.MainBundle.PathForResource("embedded", "mobileprovision");
#else
        var path = Path.Combine(AppContext.BaseDirectory, "embedded.mobileprovision");
        return File.Exists(path) ? path : null;
#endif
    }

    [GeneratedRegex("<key>ExpirationDate</key>\\s*<date>(?<value>[^<]+)</date>", RegexOptions.CultureInvariant)]
    private static partial Regex ExpirationDateRegex();
}
