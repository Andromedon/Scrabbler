using System.Text;
using Scrabbler.Domain.BoardModel;
using Scrabbler.Data;
using Scrabbler.ImageAnalysis;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Advanced;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

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

    [Fact]
    public void UsesScoreDigitToResolveNShapeWithHScore()
    {
        using var image = CreateSampleTileWithDifferentScoreDigit('N', 'H');
        var recognizer = new TileLetterRecognizer(RealLetterValues(), RealLetterSamplesPath());

        var result = recognizer.Recognize(image, new Rectangle(0, 0, image.Width, image.Height));

        Assert.Equal('H', result.Letter);
    }

    [Fact]
    public void UsesScoreDigitToResolveHShapeWithNScore()
    {
        using var image = CreateSampleTileWithDifferentScoreDigit('H', 'N');
        var recognizer = new TileLetterRecognizer(RealLetterValues(), RealLetterSamplesPath());

        var result = recognizer.Recognize(image, new Rectangle(0, 0, image.Width, image.Height));

        Assert.Equal('N', result.Letter);
    }

    [Fact]
    public void RecognizesWhiteGlyphPWithWhiteScoreDigit()
    {
        using var image = CreateWhiteGlyphTile('P');
        var recognizer = new TileLetterRecognizer(RealLetterValues(), RealLetterSamplesPath());

        var result = recognizer.Recognize(image, new Rectangle(0, 0, image.Width, image.Height));

        Assert.Equal('P', result.Letter);
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

    private static Image<Rgba32> CreateSampleTileWithDifferentScoreDigit(char shapeLetter, char scoreLetter)
    {
        using var shape = Image.Load<Rgba32>(FindSamplePath(shapeLetter));
        using var score = Image.Load<Rgba32>(FindSamplePath(scoreLetter));
        score.Mutate(context => context.Resize(shape.Width, shape.Height));
        var image = shape.Clone();
        var bounds = ScoreBounds(Inset(new Rectangle(0, 0, image.Width, image.Height), 0.035));

        for (var y = bounds.Top; y < bounds.Bottom; y++)
        {
            var targetRow = image.DangerousGetPixelRowMemory(y).Span;
            var scoreRow = score.DangerousGetPixelRowMemory(y).Span;
            for (var x = bounds.Left; x < bounds.Right; x++)
            {
                targetRow[x] = scoreRow[x];
            }
        }

        return image;
    }

    private static Image<Rgba32> CreateAllLettersTileWithDifferentScoreDigit(char shapeLetter, char scoreLetter)
    {
        using var source = Image.Load<Rgba32>(Path.Combine(AppContext.BaseDirectory, "TestData", "all-letters-sample.png"));
        var shapeBounds = AllLettersScreenshotCellBounds(shapeLetter);
        var scoreBounds = AllLettersScreenshotCellBounds(scoreLetter);
        var image = new Image<Rgba32>(shapeBounds.Width, shapeBounds.Height, new Rgba32(255, 255, 255));
        CopyPixels(source, shapeBounds, image, new Point(0, 0));
        var bounds = ScoreBounds(Inset(new Rectangle(0, 0, image.Width, image.Height), 0.035));
        var sourceScoreBounds = ScoreBounds(Inset(scoreBounds, 0.035));

        for (var y = 0; y < bounds.Height; y++)
        {
            var targetRow = image.DangerousGetPixelRowMemory(bounds.Top + y).Span;
            var scoreRow = source.DangerousGetPixelRowMemory(sourceScoreBounds.Top + y).Span;
            for (var x = 0; x < bounds.Width; x++)
            {
                targetRow[bounds.Left + x] = scoreRow[sourceScoreBounds.Left + x];
            }
        }

        return image;
    }

    private static Image<Rgba32> CreateWhiteGlyphTile(char letter)
    {
        using var source = Image.Load<Rgba32>(FindSamplePath(letter));
        var image = source.Clone();
        var bounds = Inset(new Rectangle(0, 0, image.Width, image.Height), 0.035);

        for (var y = bounds.Top; y < bounds.Bottom; y++)
        {
            var row = image.DangerousGetPixelRowMemory(y).Span;
            for (var x = bounds.Left; x < bounds.Right; x++)
            {
                if (IsDarkInk(row[x]) && HasOrangeNeighbor(source, x, y, bounds))
                {
                    row[x] = new Rgba32(255, 255, 255);
                }
            }
        }

        return image;
    }

    private static Rectangle AllLettersScreenshotCellBounds(char letter)
    {
        const int tile = 36;
        var xs = new[] { 2, 57, 112, 167, 222, 277 };
        var ys = new[] { 1, 45, 89, 133, 177, 221 };
        var cells = new Dictionary<char, (int Row, int Col)>
        {
            ['G'] = (1, 3),
            ['H'] = (1, 4),
            ['N'] = (2, 5)
        };
        var (row, col) = cells[letter];
        return new Rectangle(xs[col], ys[row], tile, tile);
    }

    private static void CopyPixels(Image<Rgba32> source, Rectangle sourceBounds, Image<Rgba32> target, Point targetPoint)
    {
        for (var y = 0; y < sourceBounds.Height; y++)
        {
            var sourceRow = source.DangerousGetPixelRowMemory(sourceBounds.Top + y).Span;
            var targetRow = target.DangerousGetPixelRowMemory(targetPoint.Y + y).Span;
            for (var x = 0; x < sourceBounds.Width; x++)
            {
                if (sourceBounds.Left + x < 0 || sourceBounds.Left + x >= source.Width)
                {
                    continue;
                }

                targetRow[targetPoint.X + x] = sourceRow[sourceBounds.Left + x];
            }
        }
    }

    private static bool HasOrangeNeighbor(Image<Rgba32> image, int x, int y, Rectangle bounds)
    {
        for (var yy = Math.Max(bounds.Top, y - 2); yy < Math.Min(bounds.Bottom, y + 3); yy++)
        {
            var row = image.DangerousGetPixelRowMemory(yy).Span;
            for (var xx = Math.Max(bounds.Left, x - 2); xx < Math.Min(bounds.Right, x + 3); xx++)
            {
                if (IsOrangeLike(row[xx]))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static bool IsDarkInk(Rgba32 pixel)
    {
        var max = Math.Max(pixel.R, Math.Max(pixel.G, pixel.B));
        var min = Math.Min(pixel.R, Math.Min(pixel.G, pixel.B));
        return max < 190 && max - min < 90;
    }

    private static bool IsOrangeLike(Rgba32 pixel)
    {
        return pixel.R > 190 && pixel.G is >= 120 and <= 210 && pixel.B < 130;
    }

    private static Rectangle Inset(Rectangle bounds, double ratio)
    {
        var dx = Math.Max(1, (int)Math.Round(bounds.Width * ratio));
        var dy = Math.Max(1, (int)Math.Round(bounds.Height * ratio));
        return new Rectangle(
            bounds.Left + dx,
            bounds.Top + dy,
            Math.Max(1, bounds.Width - dx * 2),
            Math.Max(1, bounds.Height - dy * 2));
    }

    private static Rectangle ScoreBounds(Rectangle cellBounds)
    {
        return new Rectangle(
            cellBounds.Left + (int)(cellBounds.Width * 0.55),
            cellBounds.Top,
            Math.Max(1, (int)(cellBounds.Width * 0.40)),
            Math.Max(1, (int)(cellBounds.Height * 0.32)));
    }

    private static IReadOnlyDictionary<char, int> RealLetterValues()
    {
        var path = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.Assets/Data/letter-values-pl.json"));
        return LetterValuesLoader.Load(path);
    }

    private static string RealLetterSamplesPath()
    {
        return Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.Assets/Data/letters-samples"));
    }
}
