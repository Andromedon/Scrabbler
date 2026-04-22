using Scrabbler.App.ImageAnalysis;

namespace Scrabbler.Tests;

public sealed class FixedDirectoryInputImageProviderTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"scrabbler-tests-{Guid.NewGuid():N}");

    public FixedDirectoryInputImageProviderTests()
    {
        Directory.CreateDirectory(_directory);
    }

    [Fact]
    public async Task ReturnsNullWhenDirectoryHasNoImages()
    {
        File.WriteAllText(Path.Combine(_directory, "notes.txt"), "ignore");

        var provider = new FixedDirectoryInputImageProvider(_directory);

        Assert.Null(await provider.GetSelectedImageAsync());
    }

    [Fact]
    public async Task SelectsNewestSupportedImage()
    {
        var oldImage = Touch("old.png", DateTime.UtcNow.AddMinutes(-10));
        var newImage = Touch("new.jpg", DateTime.UtcNow);
        Touch("ignored.txt", DateTime.UtcNow.AddHours(1));

        var provider = new FixedDirectoryInputImageProvider(_directory);

        Assert.Equal(newImage, (await provider.GetSelectedImageAsync())!.FullName);
        Assert.NotEqual(oldImage, (await provider.GetSelectedImageAsync())!.FullName);
    }

    public void Dispose()
    {
        Directory.Delete(_directory, recursive: true);
    }

    private string Touch(string name, DateTime lastWriteUtc)
    {
        var path = Path.Combine(_directory, name);
        File.WriteAllText(path, "");
        File.SetLastWriteTimeUtc(path, lastWriteUtc);
        return path;
    }
}
