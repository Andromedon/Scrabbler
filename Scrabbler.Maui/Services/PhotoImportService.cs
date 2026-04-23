namespace Scrabbler.Maui.Services;

public sealed class PhotoImportService : IPhotoImportService
{
    public async Task<FileInfo?> PickPhotoAsync(CancellationToken cancellationToken = default)
    {
        var photos = await MediaPicker.Default.PickPhotosAsync(new MediaPickerOptions
        {
            Title = "Select board screenshot"
        });
        var photo = photos?.FirstOrDefault();
        if (photo is null)
        {
            return null;
        }

        var extension = Path.GetExtension(photo.FileName);
        var destination = Path.Combine(
            FileSystem.CacheDirectory,
            $"gallery-{DateTimeOffset.UtcNow.UtcTicks}{extension}");

        await using var source = await photo.OpenReadAsync();
        await using var target = File.Create(destination);
        await source.CopyToAsync(target, cancellationToken);
        return new FileInfo(destination);
    }
}
