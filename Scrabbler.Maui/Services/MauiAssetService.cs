using System.Text;
using Scrabbler.Domain.BoardModel;

namespace Scrabbler.Maui.Services;

public sealed class MauiAssetService
{
    private readonly SemaphoreSlim _lock = new(1, 1);
    private bool _initialized;

    public string DataDirectory { get; private set; } = string.Empty;

    public string LetterValuesPath => Path.Combine(DataDirectory, "letter-values-pl.json");

    public string BonusLayoutPath => Path.Combine(DataDirectory, "bonus-layout.json");

    public string LetterSamplesPath => Path.Combine(DataDirectory, "letters-samples");

    public string DictionaryPath => Path.Combine(DataDirectory, "dictionary-pl.txt");

    public string? Warning { get; private set; }

    public async Task EnsureAsync(CancellationToken cancellationToken = default)
    {
        if (_initialized)
        {
            return;
        }

        await _lock.WaitAsync(cancellationToken);
        try
        {
            if (_initialized)
            {
                return;
            }

            DataDirectory = Path.Combine(FileSystem.AppDataDirectory, "Data");
            Directory.CreateDirectory(DataDirectory);
            Directory.CreateDirectory(LetterSamplesPath);

            await CopyPackageFileAsync("Data/letter-values-pl.json", LetterValuesPath, cancellationToken);
            await CopyPackageFileAsync("Data/bonus-layout.json", BonusLayoutPath, cancellationToken);
            foreach (var letter in PolishAlphabet.Letters)
            {
                var fileName = $"{letter}.png".Normalize(NormalizationForm.FormD);
                await CopyPackageFileAsync(
                    $"Data/letters-samples/{fileName}",
                    Path.Combine(LetterSamplesPath, fileName),
                    cancellationToken);
            }

            if (!await TryCopyPackageFileAsync("Data/dictionary-pl.txt", DictionaryPath, cancellationToken))
            {
                await CopyPackageFileAsync("Data/dictionary-pl.sample.txt", DictionaryPath, cancellationToken);
                Warning = "Using the sample dictionary. Add Resources/Raw/Data/dictionary-pl.txt for full mobile solving.";
            }

            _initialized = true;
        }
        finally
        {
            _lock.Release();
        }
    }

    private static async Task CopyPackageFileAsync(string packagePath, string destinationPath, CancellationToken cancellationToken)
    {
        if (!await TryCopyPackageFileAsync(packagePath, destinationPath, cancellationToken))
        {
            throw new FileNotFoundException($"Required app asset was not found: {packagePath}", packagePath);
        }
    }

    private static async Task<bool> TryCopyPackageFileAsync(string packagePath, string destinationPath, CancellationToken cancellationToken)
    {
        try
        {
            if (File.Exists(destinationPath))
            {
                return true;
            }

            await using var source = await FileSystem.OpenAppPackageFileAsync(packagePath);
            Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
            await using var target = File.Create(destinationPath);
            await source.CopyToAsync(target, cancellationToken);
            return true;
        }
        catch (FileNotFoundException)
        {
            return false;
        }
    }
}
