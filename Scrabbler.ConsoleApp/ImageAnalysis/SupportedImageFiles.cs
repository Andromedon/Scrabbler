namespace Scrabbler.App.ImageAnalysis;

public static class SupportedImageFiles
{
    public static readonly IReadOnlySet<string> Extensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg",
        ".jpeg",
        ".png",
        ".webp",
        ".bmp"
    };

    public static readonly IReadOnlySet<string> MimeTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/bmp",
        "image/x-ms-bmp"
    };

    public static bool HasSupportedExtension(string fileName)
    {
        return Extensions.Contains(Path.GetExtension(fileName));
    }

    public static bool IsSupported(string fileName, string? mimeType)
    {
        return HasSupportedExtension(fileName)
            || (!string.IsNullOrWhiteSpace(mimeType) && MimeTypes.Contains(mimeType));
    }
}
