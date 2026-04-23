namespace Scrabbler.Maui.Services;

public interface IPhotoImportService
{
    Task<FileInfo?> PickPhotoAsync(CancellationToken cancellationToken = default);
}
