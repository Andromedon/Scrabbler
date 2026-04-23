using Microsoft.Extensions.Configuration;
using Scrabbler.App.Configuration;

namespace Scrabbler.Tests;

public sealed class AppSettingsTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"scrabbler-settings-{Guid.NewGuid():N}");

    public AppSettingsTests()
    {
        Directory.CreateDirectory(Path.Combine(_root, "Scrabbler.ConsoleApp"));
        Directory.CreateDirectory(Path.Combine(_root, "Scrabbler.Assets"));
        File.WriteAllText(Path.Combine(_root, "Scrabbler.ConsoleApp", "Scrabbler.App.csproj"), "<Project />");
        File.WriteAllText(Path.Combine(_root, "Scrabbler.Assets", "Scrabbler.Assets.csproj"), "<Project />");
    }

    [Fact]
    public void RepoRootWorkingDirectoryResolvesToConsoleAppContentRoot()
    {
        var settings = AppSettings.From(EmptyConfiguration(), "/tmp/bin", _root);

        Assert.Equal(Path.Combine(_root, "Scrabbler.ConsoleApp"), settings.ContentRoot);
        Assert.Equal(Path.Combine(_root, "Scrabbler.Assets"), settings.AssetsRoot);
        Assert.Equal(InputSource.Local, settings.InputSource);
        Assert.Equal(Path.Combine(_root, "Scrabbler.ConsoleApp", "Input"), settings.InputDirectory);
        Assert.Equal(Path.Combine(_root, "Scrabbler.ConsoleApp", "Secrets", "google-drive-client-secret.json"), settings.GoogleDriveCredentialsPath);
        Assert.Equal(Path.Combine(_root, "Scrabbler.ConsoleApp", "Secrets", "google-token"), settings.GoogleDriveTokenDirectory);
        Assert.Equal(Path.Combine(_root, "Scrabbler.ConsoleApp", "Input", "Downloaded"), settings.GoogleDriveDownloadDirectory);
        Assert.Equal(Path.Combine(_root, "Scrabbler.ConsoleApp", "Data", "dictionary-pl.txt"), settings.DictionaryPath);
        Assert.Equal(Path.Combine(_root, "Scrabbler.Assets", "Data", "letter-values-pl.json"), settings.LetterValuesPath);
        Assert.Equal(Path.Combine(_root, "Scrabbler.Assets", "Data", "letters-samples"), settings.LetterSamplesPath);
        Assert.Equal(Path.Combine(_root, "Scrabbler.Assets", "Data", "bonus-layout.json"), settings.BonusLayoutPath);
    }

    [Fact]
    public void ConsoleAppWorkingDirectoryResolvesToItself()
    {
        var appRoot = Path.Combine(_root, "Scrabbler.ConsoleApp");

        var settings = AppSettings.From(EmptyConfiguration(), "/tmp/bin", appRoot);

        Assert.Equal(appRoot, settings.ContentRoot);
        Assert.Equal(Path.Combine(_root, "Scrabbler.Assets"), settings.AssetsRoot);
        Assert.Equal(Path.Combine(_root, "Scrabbler.Assets", "Data", "letter-values-pl.json"), settings.LetterValuesPath);
    }

    [Fact]
    public void AbsoluteConfigPathsArePreserved()
    {
        var absoluteInput = Path.Combine(_root, "custom-input");
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["InputDirectory"] = absoluteInput,
                ["InputSource"] = "GoogleDrive",
                ["GoogleDriveFolderId"] = "folder-123"
            })
            .Build();

        var settings = AppSettings.From(configuration, "/tmp/bin", _root);

        Assert.Equal(InputSource.GoogleDrive, settings.InputSource);
        Assert.Equal(absoluteInput, settings.InputDirectory);
        Assert.Equal("folder-123", settings.GoogleDriveFolderId);
    }

    public void Dispose()
    {
        Directory.Delete(_root, recursive: true);
    }

    private static IConfiguration EmptyConfiguration()
    {
        return new ConfigurationBuilder().Build();
    }
}
