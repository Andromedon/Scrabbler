using System.Text;
using Scrabbler.Domain.BoardModel;
using Scrabbler.Data;
using Scrabbler.ImageAnalysis;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Advanced;
using SixLabors.ImageSharp.Drawing;
using SixLabors.ImageSharp.Drawing.Processing;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;
using SixLabors.Fonts;
using Path = System.IO.Path;

namespace Scrabbler.Tests;

public sealed class ImageSharpScreenshotBoardImageReaderTests : IDisposable
{
    private const int Cell = 80;
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"scrabbler-image-{Guid.NewGuid():N}");

    public ImageSharpScreenshotBoardImageReaderTests()
    {
        Directory.CreateDirectory(_directory);
    }

    [Fact]
    public async Task ReadsCleanScreenshotAndReportsOccupiedTileCells()
    {
        var path = Path.Combine(_directory, "board.png");
        var bonuses = EmptyBonuses();
        bonuses[1, 5] = BonusType.DoubleWord;
        bonuses[7, 11] = BonusType.DoubleWord;
        bonuses[11, 7] = BonusType.DoubleWord;
        CreateSyntheticBoard(path);
        var reader = CreateReader(bonuses);

        var result = await reader.ReadAsync(path);

        Assert.False(result.Board.IsEmpty);
        Assert.Equal(BonusType.None, result.Board[7, 7].Bonus);
        Assert.Equal(new[]
        {
            "H3=A",
            "H4=R",
            "H8=B", "I8=L", "J8=A", "K8=T",
            "K9=O",
            "K10=R",
            "E12=K", "F12=O", "G12=T", "I12=A"
        }, OccupiedCells(result));
        Assert.Contains(result.Cells, cell => cell is { Row: 7, Column: 7, IsOccupied: true, Letter: 'B' });
        Assert.Contains(result.Cells, cell => cell is { Row: 1, Column: 5, IsOccupied: false });
        Assert.Contains(result.Cells, cell => cell is { Row: 7, Column: 11, IsOccupied: false });
        Assert.Contains(result.Cells, cell => cell is { Row: 11, Column: 7, IsOccupied: false });
        Assert.Contains(result.Cells, cell => cell is { Row: 11, Column: 8, IsOccupied: true, Letter: 'A' });
    }

    [Fact]
    public async Task ReadsRealBoardScreenshotFixture()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "TestData", "board-blat.jpg");
        var reader = CreateReader(RealBonuses());

        var result = await reader.ReadAsync(path);

        Assert.False(result.Board.IsEmpty);
        Assert.True(result.Cells.Count(cell => cell.IsOccupied) >= 25);
    }

    [Fact]
    public async Task ReadsCurrentBoardScreenshotWithBlatyRegression()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "TestData", "board-current-blaty.jpg");
        var reader = CreateReader(RealBonuses());

        var result = await reader.ReadAsync(path);

        Assert.False(result.Board.IsEmpty);
        Assert.True(result.Cells.Count(cell => cell.IsOccupied) >= 10);
    }

    [Fact]
    public async Task ReadsSampleBoardWithMixedTileColorsAndRedScoreBadge()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "TestData", "board-sample.jpg");
        var reader = CreateReader(RealBonuses());

        var result = await reader.ReadAsync(path);

        Assert.Contains("GROZIMY", BoardLines(result.Board));
        Assert.True(result.Cells.Count(cell => cell.IsOccupied) >= 35);
    }

    [Fact]
    public async Task ReadsCroppedSampleBoardWithMixedTileColorsAndRedScoreBadge()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "TestData", "board-sample-cropped.png");
        var reader = CreateReader(RealBonuses());

        var result = await reader.ReadAsync(path);
        var words = BoardLines(result.Board);

        Assert.Contains("SWA", words);
        Assert.Contains("GROZIMY", words);
        Assert.Contains("ZAMEK", words);
        Assert.Contains("FAJNY", words);
        Assert.Contains("SŁAWNY", words);
        Assert.Contains("MOPS", words);
        Assert.Contains("GLEBY", words);
        Assert.True(result.Cells.Count(cell => cell.IsOccupied) >= 35);
    }

    [Fact]
    public async Task IgnoresRedScoreBadgeWhenDetectingTiles()
    {
        var path = Path.Combine(_directory, "red-badge-board.png");
        CreateSyntheticBoard(path, includeRedBadge: true);
        var reader = CreateReader(EmptyBonuses());

        var result = await reader.ReadAsync(path);

        Assert.DoesNotContain(result.Cells, cell => cell is { Row: 13, Column: 10, IsOccupied: true });
        Assert.Contains(result.Cells, cell => cell is { Row: 7, Column: 7, IsOccupied: true, Letter: 'B' });
    }

    public void Dispose()
    {
        Directory.Delete(_directory, recursive: true);
    }

    private static BonusType[,] EmptyBonuses()
    {
        return new BonusType[Board.Size, Board.Size];
    }

    private static BonusType[,] RealBonuses()
    {
        var path = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.Assets/Data/bonus-layout.json"));
        return BonusLayoutLoader.Load(path);
    }

    private static IReadOnlyDictionary<char, int> RealLetterValues()
    {
        var path = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.Assets/Data/letter-values-pl.json"));
        return LetterValuesLoader.Load(path);
    }

    private static ImageSharpScreenshotBoardImageReader CreateReader(BonusType[,] bonuses)
    {
        return new ImageSharpScreenshotBoardImageReader(bonuses, RealLetterValues(), RealLetterSamplesPath());
    }

    private static string RealLetterSamplesPath()
    {
        return Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.Assets/Data/letters-samples"));
    }

    private static string[] OccupiedCells(BoardReadResult result)
    {
        return result.Cells
            .Where(cell => cell.IsOccupied)
            .Select(cell => $"{(char)('A' + cell.Column)}{cell.Row + 1}={cell.Letter}")
            .ToArray();
    }

    private static string[] BoardLines(Board board)
    {
        var lines = new List<string>();
        for (var row = 0; row < Board.Size; row++)
        {
            lines.Add(new string(Enumerable.Range(0, Board.Size).Select(col => board[row, col].Letter ?? '.').ToArray()));
        }

        for (var col = 0; col < Board.Size; col++)
        {
            lines.Add(new string(Enumerable.Range(0, Board.Size).Select(row => board[row, col].Letter ?? '.').ToArray()));
        }

        return lines.SelectMany(LineWords).ToArray();
    }

    private static IEnumerable<string> LineWords(string line)
    {
        return line.Split('.', StringSplitOptions.RemoveEmptyEntries).Where(word => word.Length > 1);
    }

    private static void CreateSyntheticBoard(string path, bool includeRedBadge = false)
    {
        using var image = new Image<Rgba32>(Board.Size * Cell, Board.Size * Cell, new Rgba32(238, 238, 238));

        DrawTile(image, 7, 2, 'A');
        DrawTile(image, 7, 3, 'R');

        DrawTile(image, 7, 7, 'B');
        DrawTile(image, 8, 7, 'L');
        DrawTile(image, 9, 7, 'A');
        DrawTile(image, 10, 7, 'T');

        DrawTile(image, 10, 8, 'O');
        DrawTile(image, 10, 9, 'R');

        DrawTile(image, 4, 11, 'K');
        DrawTile(image, 5, 11, 'O');
        DrawTile(image, 6, 11, 'T');
        DrawTile(image, 8, 11, 'A');

        DrawBonusLikeSquare(image, 5, 1);
        DrawBonusLikeSquare(image, 11, 7);

        if (includeRedBadge)
        {
            image.Mutate(context => context.Fill(
                Color.Red,
                new EllipsePolygon(10 * Cell + 42, 13 * Cell + 38, 28)));
        }

        image.SaveAsPng(path);
    }

    private static void DrawTile(Image<Rgba32> image, int col, int row, char letter)
    {
        using var tile = Image.Load<Rgba32>(FindSamplePath(letter));
        tile.Mutate(context => context.Resize(Cell, Cell));
        image.Mutate(context => context.DrawImage(tile, new Point(col * Cell, row * Cell), 1f));
    }

    private static string FindSamplePath(char letter)
    {
        return Directory.EnumerateFiles(RealLetterSamplesPath(), "*.png")
            .Single(path => Path.GetFileNameWithoutExtension(path).Normalize(NormalizationForm.FormC) == letter.ToString());
    }

    private static void DrawBonusLikeSquare(Image<Rgba32> image, int col, int row)
    {
        Fill(image, col * Cell, row * Cell, Cell, Cell, new Rgba32(242, 178, 71));
        Fill(image, col * Cell + 24, row * Cell + 24, 32, 32, new Rgba32(255, 255, 255));
    }

    private static void Fill(Image<Rgba32> image, int x, int y, int width, int height, Rgba32 color)
    {
        for (var row = y; row < y + height; row++)
        {
            var span = image.DangerousGetPixelRowMemory(row).Span;
            for (var col = x; col < x + width; col++)
            {
                span[col] = color;
            }
        }
    }
}
