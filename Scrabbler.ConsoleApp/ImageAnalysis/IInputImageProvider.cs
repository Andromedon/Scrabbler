namespace Scrabbler.App.ImageAnalysis;

public interface IInputImageProvider
{
    Task<FileInfo?> GetSelectedImageAsync(CancellationToken cancellationToken = default);
}
