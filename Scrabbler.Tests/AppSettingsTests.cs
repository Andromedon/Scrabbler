using Microsoft.Extensions.Configuration;
using Scrabbler.App.Configuration;

namespace Scrabbler.Tests;

public sealed class AppSettingsTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"scrabbler-settings-{Guid.NewGuid():N}");

    public AppSettingsTests()
    {
        Directory.CreateDirectory(Path.Combine(_root, "Scrabbler.ConsoleApp"));
        File.WriteAllText(Path.Combine(_root, "Scrabbler.ConsoleApp", "Scrabbler.App.csproj"), "<Project />");
    }

    [Fact]
    public void RepoRootWorkingDirectoryResolvesToConsoleAppContentRoot()
    {
        var settings = AppSettings.From(EmptyConfiguration(), "/tmp/bin", _root);

        Assert.Equal(Path.Combine(_root, "Scrabbler.ConsoleApp"), settings.ContentRoot);
        Assert.Equal(Path.Combine(_root, "Scrabbler.ConsoleApp", "Input"), settings.InputDirectory);
        Assert.Equal(Path.Combine(_root, "Scrabbler.ConsoleApp", "Data", "dictionary-pl.txt"), settings.DictionaryPath);
    }

    [Fact]
    public void ConsoleAppWorkingDirectoryResolvesToItself()
    {
        var appRoot = Path.Combine(_root, "Scrabbler.ConsoleApp");

        var settings = AppSettings.From(EmptyConfiguration(), "/tmp/bin", appRoot);

        Assert.Equal(appRoot, settings.ContentRoot);
        Assert.Equal(Path.Combine(appRoot, "Data", "letter-values-pl.json"), settings.LetterValuesPath);
    }

    [Fact]
    public void AbsoluteConfigPathsArePreserved()
    {
        var absoluteInput = Path.Combine(_root, "custom-input");
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["InputDirectory"] = absoluteInput
            })
            .Build();

        var settings = AppSettings.From(configuration, "/tmp/bin", _root);

        Assert.Equal(absoluteInput, settings.InputDirectory);
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
