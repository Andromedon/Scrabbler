using Scrabbler.App.BoardModel;
using Scrabbler.App.Data;
using Scrabbler.App.ImageAnalysis;
using SixLabors.Fonts;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Advanced;
using SixLabors.ImageSharp.Drawing.Processing;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace Scrabbler.Tests;

public sealed class TileLetterRecognizerTests
{
    private const int Cell = 80;

    [Theory]
    [MemberData(nameof(PolishLetters))]
    public void RecognizesPolishLettersWithVisibleScoreDigit(char letter)
    {
        using var image = CreateTile(letter);
        var recognizer = new TileLetterRecognizer(RealLetterValues());

        var result = recognizer.Recognize(image, new Rectangle(0, 0, Cell, Cell));

        Assert.Equal(letter, result.Letter);
    }

    [Theory]
    [InlineData('B')]
    [InlineData('D')]
    [InlineData('P')]
    [InlineData('R')]
    [InlineData('J')]
    [InlineData('T')]
    [InlineData('O')]
    [InlineData('Y')]
    public void RecognizesCommonConfusionLettersWithVisibleScoreDigit(char letter)
    {
        using var image = CreateTile(letter);
        var recognizer = new TileLetterRecognizer(RealLetterValues());

        var result = recognizer.Recognize(image, new Rectangle(0, 0, Cell, Cell));

        Assert.Equal(letter, result.Letter);
    }

    [Theory]
    [InlineData('D', 'B')]
    [InlineData('B', 'D')]
    public void ScoreDigitWinsForAmbiguousBAndDShapes(char drawnLetter, char expectedLetter)
    {
        using var image = CreateTile(drawnLetter, expectedLetter);
        var recognizer = new TileLetterRecognizer(RealLetterValues());

        var result = recognizer.Recognize(image, new Rectangle(0, 0, Cell, Cell));

        Assert.Equal(expectedLetter, result.Letter);
    }

    public static IEnumerable<object[]> PolishLetters()
    {
        return PolishAlphabet.Letters.Select(letter => new object[] { letter });
    }

    private static Image<Rgba32> CreateTile(char letter)
    {
        return CreateTile(letter, letter);
    }

    private static Image<Rgba32> CreateTile(char drawnLetter, char scoreLetter)
    {
        var image = new Image<Rgba32>(Cell, Cell, new Rgba32(242, 178, 71));
        var font = ResolveFont(52);
        image.Mutate(context => context.DrawText(new RichTextOptions(font)
        {
            Origin = new PointF(Cell / 2f, Cell / 2f),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        }, drawnLetter.ToString(), Color.White));

        var scoreFont = ResolveFont(18);
        image.Mutate(context => context.DrawText(new RichTextOptions(scoreFont)
        {
            Origin = new PointF(Cell * 0.78f, Cell * 0.18f),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        }, RealLetterValues()[scoreLetter].ToString(), Color.Black));

        return image;
    }

    private static IReadOnlyDictionary<char, int> RealLetterValues()
    {
        var path = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.ConsoleApp/Data/letter-values-pl.json"));
        return LetterValuesLoader.Load(path);
    }

    private static Font ResolveFont(float size)
    {
        var collection = new FontCollection();
        var candidates = new[]
        {
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Verdana Bold.ttf"
        };

        foreach (var path in candidates.Where(File.Exists))
        {
            try
            {
                return collection.Add(path).CreateFont(size, FontStyle.Bold);
            }
            catch
            {
                // Try the next system font.
            }
        }

        return SystemFonts.Families.First().CreateFont(size, FontStyle.Bold);
    }

}
