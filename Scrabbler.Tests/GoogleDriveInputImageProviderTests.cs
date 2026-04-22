using Microsoft.Extensions.Configuration;
using Scrabbler.App.Configuration;
using Scrabbler.App.ImageAnalysis;

namespace Scrabbler.Tests;

public sealed class GoogleDriveInputImageProviderTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"scrabbler-drive-{Guid.NewGuid():N}");

    public GoogleDriveInputImageProviderTests()
    {
        Directory.CreateDirectory(_directory);
    }

    [Fact]
    public async Task SelectsNewestSupportedImageAndDownloadsIt()
    {
        var client = new FakeGoogleDriveClient(new[]
        {
            new GoogleDriveImageFile("old", "old.png", DateTimeOffset.UtcNow.AddMinutes(-10)),
            new GoogleDriveImageFile("new", "new.jpg", DateTimeOffset.UtcNow),
            new GoogleDriveImageFile("ignored", "notes.txt", DateTimeOffset.UtcNow.AddHours(1))
        });
        var provider = new GoogleDriveInputImageProvider(client, "folder-id", _directory);

        var image = await provider.GetSelectedImageAsync();

        Assert.NotNull(image);
        Assert.Contains("new", image!.Name, StringComparison.Ordinal);
        Assert.Equal("new", client.DownloadedFileId);
        Assert.True(File.Exists(image.FullName));
    }

    [Fact]
    public async Task UsesStableTieBreakForSameModifiedTime()
    {
        var modified = DateTimeOffset.UtcNow;
        var client = new FakeGoogleDriveClient(new[]
        {
            new GoogleDriveImageFile("id-b", "same.png", modified),
            new GoogleDriveImageFile("id-a", "same.png", modified)
        });
        var provider = new GoogleDriveInputImageProvider(client, "folder-id", _directory);

        await provider.GetSelectedImageAsync();

        Assert.Equal("id-a", client.DownloadedFileId);
    }

    [Fact]
    public async Task ReturnsNullWhenFolderHasNoSupportedImages()
    {
        var client = new FakeGoogleDriveClient(new[]
        {
            new GoogleDriveImageFile("notes", "notes.txt", DateTimeOffset.UtcNow)
        });
        var provider = new GoogleDriveInputImageProvider(client, "folder-id", _directory);

        Assert.Null(await provider.GetSelectedImageAsync());
        Assert.Null(client.DownloadedFileId);
    }

    [Fact]
    public async Task SupportsDriveImageMimeTypesWithoutKnownExtension()
    {
        var client = new FakeGoogleDriveClient(new[]
        {
            new GoogleDriveImageFile("image", "drive-export", DateTimeOffset.UtcNow, "image/png")
        });
        var provider = new GoogleDriveInputImageProvider(client, "folder-id", _directory);

        await provider.GetSelectedImageAsync();

        Assert.Equal("image", client.DownloadedFileId);
    }

    [Fact]
    public async Task MissingFolderIdReportsClearError()
    {
        var provider = new GoogleDriveInputImageProvider(new FakeGoogleDriveClient(Array.Empty<GoogleDriveImageFile>()), "", _directory);

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() => provider.GetSelectedImageAsync());

        Assert.Contains("GoogleDriveFolderId", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void FactoryUsesLocalProviderByDefault()
    {
        var settings = AppSettings.From(new ConfigurationBuilder().Build(), "/tmp/bin", Directory.GetCurrentDirectory());

        Assert.IsType<FixedDirectoryInputImageProvider>(InputImageProviderFactory.Create(settings));
    }

    [Fact]
    public void FactoryUsesGoogleDriveProviderWhenConfigured()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["InputSource"] = "GoogleDrive",
                ["GoogleDriveFolderId"] = "folder-id"
            })
            .Build();
        var settings = AppSettings.From(configuration, "/tmp/bin", Directory.GetCurrentDirectory());

        Assert.IsType<GoogleDriveInputImageProvider>(InputImageProviderFactory.Create(settings));
    }

    public void Dispose()
    {
        Directory.Delete(_directory, recursive: true);
    }

    private sealed class FakeGoogleDriveClient : IGoogleDriveClient
    {
        private readonly IReadOnlyList<GoogleDriveImageFile> _files;

        public FakeGoogleDriveClient(IReadOnlyList<GoogleDriveImageFile> files)
        {
            _files = files;
        }

        public string? DownloadedFileId { get; private set; }

        public Task<IReadOnlyList<GoogleDriveImageFile>> ListFilesAsync(string folderId, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(_files);
        }

        public Task DownloadFileAsync(string fileId, string destinationPath, CancellationToken cancellationToken = default)
        {
            DownloadedFileId = fileId;
            File.WriteAllText(destinationPath, fileId);
            return Task.CompletedTask;
        }
    }
}
