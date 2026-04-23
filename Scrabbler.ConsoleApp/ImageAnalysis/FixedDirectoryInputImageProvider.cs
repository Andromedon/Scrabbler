using Scrabbler.Input;

namespace Scrabbler.App.ImageAnalysis;

public sealed class FixedDirectoryInputImageProvider : IInputImageProvider
{
    private readonly string _directory;

    public FixedDirectoryInputImageProvider(string directory)
    {
        _directory = directory;
    }

    public Task<FileInfo?> GetSelectedImageAsync(CancellationToken cancellationToken = default)
    {
        var directory = new DirectoryInfo(_directory);
        if (!directory.Exists)
        {
            return Task.FromResult<FileInfo?>(null);
        }

        var image = directory
            .EnumerateFiles()
            .Where(file => SupportedImageFiles.HasSupportedExtension(file.Name))
            .OrderByDescending(file => file.LastWriteTimeUtc)
            .ThenBy(file => file.Name, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();

        return Task.FromResult(image);
    }
}
