namespace Scrabbler.Input;

public interface IInputImageProvider
{
    Task<FileInfo?> GetSelectedImageAsync(CancellationToken cancellationToken = default);
}
