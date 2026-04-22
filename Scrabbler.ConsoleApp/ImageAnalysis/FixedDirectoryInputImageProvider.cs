namespace Scrabbler.App.ImageAnalysis;

public sealed class FixedDirectoryInputImageProvider : IInputImageProvider
{
    private static readonly HashSet<string> SupportedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg",
        ".jpeg",
        ".png",
        ".webp",
        ".bmp"
    };

    private readonly string _directory;

    public FixedDirectoryInputImageProvider(string directory)
    {
        _directory = directory;
    }

    public FileInfo? GetSelectedImage()
    {
        var directory = new DirectoryInfo(_directory);
        if (!directory.Exists)
        {
            return null;
        }

        return directory
            .EnumerateFiles()
            .Where(file => SupportedExtensions.Contains(file.Extension))
            .OrderByDescending(file => file.LastWriteTimeUtc)
            .ThenBy(file => file.Name, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
    }
}
