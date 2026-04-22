using System.Text;
using Scrabbler.App.BoardModel;
using Scrabbler.App.Data;
using Scrabbler.App.ImageAnalysis;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace Scrabbler.Tests;

public sealed class TileLetterRecognizerTests
{
    [Fact]
    public void LoadsEveryPolishLetterSample()
    {
        var samples = TileLetterRecognizer.LetterSampleLibrary.Load(RealLetterSamplesPath(), RealLetterValues());

        Assert.Equal(
            PolishAlphabet.Letters.OrderBy(letter => letter).ToArray(),
            samples.Samples.Select(sample => sample.Letter).OrderBy(letter => letter).ToArray());
    }

    [Theory]
    [MemberData(nameof(PolishLetters))]
    public void RecognizesEachProvidedSampleAsItself(char letter)
    {
        var path = FindSamplePath(letter);
        using var image = Image.Load<Rgba32>(path);
        var recognizer = new TileLetterRecognizer(RealLetterValues(), RealLetterSamplesPath());

        var result = recognizer.Recognize(image, new Rectangle(0, 0, image.Width, image.Height));

        Assert.Equal(letter, result.Letter);
    }

    [Fact]
    public void RecognizesGAndDistinguishesNFromHInAllLettersScreenshot()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "TestData", "all-letters-sample.png");
        using var image = Image.Load<Rgba32>(path);
        var recognizer = new TileLetterRecognizer(RealLetterValues(), RealLetterSamplesPath());

        var failures = new List<string>();
        foreach (var (letter, bounds) in AllLettersScreenshotRegressionCells())
        {
            var result = recognizer.Recognize(image, bounds);
            if (result.Letter != letter)
            {
                failures.Add($"{letter} => {result.Letter?.ToString() ?? "null"} ({result.Confidence:0.000})");
            }
        }

        Assert.True(failures.Count == 0, string.Join(", ", failures));
    }

    public static IEnumerable<object[]> PolishLetters()
    {
        return PolishAlphabet.Letters.Select(letter => new object[] { letter });
    }

    private static IEnumerable<(char Letter, Rectangle Bounds)> AllLettersScreenshotRegressionCells()
    {
        const int tile = 36;
        var xs = new[] { 2, 57, 112, 167, 222, 277 };
        var ys = new[] { 1, 45, 89, 133, 177, 221 };
        var cells = new[]
        {
            (Letter: 'G', Row: 1, Col: 3),
            (Letter: 'H', Row: 1, Col: 4),
            (Letter: 'N', Row: 2, Col: 5)
        };

        return cells.Select(cell => (cell.Letter, new Rectangle(xs[cell.Col], ys[cell.Row], tile, tile)));
    }

    private static string FindSamplePath(char letter)
    {
        return Directory.EnumerateFiles(RealLetterSamplesPath(), "*.png")
            .Single(path => Path.GetFileNameWithoutExtension(path).Normalize(NormalizationForm.FormC) == letter.ToString());
    }

    private static IReadOnlyDictionary<char, int> RealLetterValues()
    {
        var path = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.ConsoleApp/Data/letter-values-pl.json"));
        return LetterValuesLoader.Load(path);
    }

    private static string RealLetterSamplesPath()
    {
        return Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.ConsoleApp/Data/letters-samples"));
    }
}
