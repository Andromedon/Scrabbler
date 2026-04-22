using Microsoft.Extensions.Configuration;

namespace Scrabbler.App.Configuration;

public sealed record AppSettings(
    string ContentRoot,
    string InputDirectory,
    string DictionaryPath,
    string LetterValuesPath,
    string BonusLayoutPath)
{
    public static AppSettings From(IConfiguration configuration, string baseDirectory, string workingDirectory)
    {
        var contentRoot = FindContentRoot(workingDirectory, baseDirectory);

        static string Resolve(string baseDirectory, string? value, string fallback)
        {
            var path = string.IsNullOrWhiteSpace(value) ? fallback : value;
            return Path.IsPathRooted(path) ? path : Path.GetFullPath(Path.Combine(baseDirectory, path));
        }

        return new AppSettings(
            contentRoot,
            Resolve(contentRoot, configuration["InputDirectory"], "Input"),
            Resolve(contentRoot, configuration["DictionaryPath"], "Data/dictionary-pl.txt"),
            Resolve(contentRoot, configuration["LetterValuesPath"], "Data/letter-values-pl.json"),
            Resolve(contentRoot, configuration["BonusLayoutPath"], "Data/bonus-layout.json"));
    }

    public static string FindContentRoot(string workingDirectory, string baseDirectory)
    {
        if (File.Exists(Path.Combine(workingDirectory, "Scrabbler.App.csproj")))
        {
            return Path.GetFullPath(workingDirectory);
        }

        var childProject = Path.Combine(workingDirectory, "Scrabbler.ConsoleApp", "Scrabbler.App.csproj");
        if (File.Exists(childProject))
        {
            return Path.GetFullPath(Path.Combine(workingDirectory, "Scrabbler.ConsoleApp"));
        }

        var current = new DirectoryInfo(baseDirectory);
        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, "Scrabbler.App.csproj")))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        return Path.GetFullPath(workingDirectory);
    }
}
