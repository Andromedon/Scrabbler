using Scrabbler.App.BoardModel;
using Scrabbler.App.Data;
using Scrabbler.App.ImageAnalysis;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Advanced;
using SixLabors.ImageSharp.Drawing.Processing;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;
using SixLabors.Fonts;

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
        var reader = new ImageSharpScreenshotBoardImageReader(bonuses, RealLetterValues());

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
        var reader = new ImageSharpScreenshotBoardImageReader(RealBonuses(), RealLetterValues());

        var result = await reader.ReadAsync(path);

        Assert.Equal(new[]
        {
            "M1=T",
            "J2=C", "K2=E", "L2=N", "M2=Ą",
            "J3=Z", "M3=P", "N3=A", "O3=T",
            "H4=S", "J4=I", "N4=B",
            "G5=S", "H5=T", "I5=Y", "J5=P", "K5=A", "N5=A",
            "H6=E", "J6=S", "N6=K",
            "E7=J", "H7=W", "N7=U",
            "D8=R", "E8=O", "F8=D", "G8=N", "H8=Y",
            "E9=D", "F9=Y",
            "F10=B"
        }, OccupiedCells(result));
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
            "../../../../Scrabbler.ConsoleApp/Data/bonus-layout.json"));
        return BonusLayoutLoader.Load(path);
    }

    private static IReadOnlyDictionary<char, int> RealLetterValues()
    {
        var path = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "../../../../Scrabbler.ConsoleApp/Data/letter-values-pl.json"));
        return LetterValuesLoader.Load(path);
    }

    private static string[] OccupiedCells(BoardReadResult result)
    {
        return result.Cells
            .Where(cell => cell.IsOccupied)
            .Select(cell => $"{(char)('A' + cell.Column)}{cell.Row + 1}={cell.Letter}")
            .ToArray();
    }

    private static void CreateSyntheticBoard(string path)
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

        image.SaveAsPng(path);
    }

    private static void DrawTile(Image<Rgba32> image, int col, int row, char letter)
    {
        Fill(image, col * Cell, row * Cell, Cell, Cell, new Rgba32(242, 178, 71));
        var font = SystemFonts.Families.First().CreateFont(52, FontStyle.Bold);
        image.Mutate(context => context.DrawText(new RichTextOptions(font)
        {
            Origin = new PointF(col * Cell + Cell / 2f, row * Cell + Cell / 2f),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        }, letter.ToString(), Color.White));
        var scoreFont = SystemFonts.Families.First().CreateFont(18, FontStyle.Bold);
        image.Mutate(context => context.DrawText(new RichTextOptions(scoreFont)
        {
            Origin = new PointF(col * Cell + Cell * 0.78f, row * Cell + Cell * 0.18f),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        }, RealLetterValues()[letter].ToString(), Color.Black));
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
