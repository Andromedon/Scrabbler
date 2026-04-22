using Microsoft.Extensions.Configuration;

namespace Scrabbler.App.Configuration;

public sealed record AppSettings(
    string ContentRoot,
    InputSource InputSource,
    string InputDirectory,
    string GoogleDriveFolderId,
    string GoogleDriveCredentialsPath,
    string GoogleDriveTokenDirectory,
    string GoogleDriveDownloadDirectory,
    string DictionaryPath,
    string LetterValuesPath,
    string LetterSamplesPath,
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
            ParseInputSource(configuration["InputSource"]),
            Resolve(contentRoot, configuration["InputDirectory"], "Input"),
            configuration["GoogleDriveFolderId"] ?? string.Empty,
            Resolve(contentRoot, configuration["GoogleDriveCredentialsPath"], "Secrets/google-drive-client-secret.json"),
            Resolve(contentRoot, configuration["GoogleDriveTokenDirectory"], "Secrets/google-token"),
            Resolve(contentRoot, configuration["GoogleDriveDownloadDirectory"], "Input/Downloaded"),
            Resolve(contentRoot, configuration["DictionaryPath"], "Data/dictionary-pl.txt"),
            Resolve(contentRoot, configuration["LetterValuesPath"], "Data/letter-values-pl.json"),
            Resolve(contentRoot, configuration["LetterSamplesPath"], "Data/letters-samples"),
            Resolve(contentRoot, configuration["BonusLayoutPath"], "Data/bonus-layout.json"));
    }

    private static InputSource ParseInputSource(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return InputSource.Local;
        }

        if (Enum.TryParse<InputSource>(value, ignoreCase: true, out var inputSource))
        {
            return inputSource;
        }

        throw new InvalidOperationException($"Unsupported InputSource '{value}'. Use 'Local' or 'GoogleDrive'.");
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

public enum InputSource
{
    Local,
    GoogleDrive
}
