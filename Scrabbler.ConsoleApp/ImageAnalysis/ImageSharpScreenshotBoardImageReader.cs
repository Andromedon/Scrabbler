using Scrabbler.App.BoardModel;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Advanced;
using SixLabors.ImageSharp.PixelFormats;

namespace Scrabbler.App.ImageAnalysis;

public sealed class ImageSharpScreenshotBoardImageReader : IBoardImageReader
{
    private readonly BonusType[,] _bonusLayout;
    private readonly IReadOnlyDictionary<char, int> _letterValues;

    public ImageSharpScreenshotBoardImageReader(BonusType[,] bonusLayout, IReadOnlyDictionary<char, int> letterValues)
    {
        _bonusLayout = bonusLayout;
        _letterValues = letterValues;
    }

    public Task<BoardReadResult> ReadAsync(string imagePath)
    {
        return Task.Run(() =>
        {
            using var image = Image.Load<Rgba32>(imagePath);
            if (image.Width < Board.Size || image.Height < Board.Size)
            {
                throw new InvalidOperationException("Image is too small to contain a 15x15 board.");
            }

            var boardBounds = GetCenteredSquare(image.Width, image.Height);
            var cellWidth = boardBounds.Width / (double)Board.Size;
            var cellHeight = boardBounds.Height / (double)Board.Size;
            var board = new Board(_bonusLayout);
            var reads = new List<CellRead>();
            var recognizer = new TileLetterRecognizer(_letterValues);

            for (var row = 0; row < Board.Size; row++)
            {
                for (var col = 0; col < Board.Size; col++)
                {
                    var stats = MeasureCell(image, boardBounds, cellWidth, cellHeight, row, col);
                    var occupied = IsLikelyTile(stats, _bonusLayout[row, col]);
                    char? letter = null;
                    var confidence = occupied ? 0.25f : 1f;
                    if (occupied)
                    {
                        var cellBounds = GetCellBounds(boardBounds, cellWidth, cellHeight, row, col);
                        var recognition = recognizer.Recognize(image, cellBounds);
                        letter = recognition.Letter;
                        confidence = recognition.Confidence;
                        if (letter is not null)
                        {
                            board = board.SetCell(row, col, letter.Value);
                        }
                    }

                    reads.Add(new CellRead(row, col, letter, confidence, occupied));
                }
            }

            return new BoardReadResult(board, reads);
        });
    }

    private static Rectangle GetCenteredSquare(int width, int height)
    {
        var size = Math.Min(width, height);
        return new Rectangle((width - size) / 2, (height - size) / 2, size, size);
    }

    private static CellStats MeasureCell(Image<Rgba32> image, Rectangle boardBounds, double cellWidth, double cellHeight, int row, int col)
    {
        var bounds = GetCellBounds(boardBounds, cellWidth, cellHeight, row, col);
        return MeasureCell(image, bounds);
    }

    private static Rectangle GetCellBounds(Rectangle boardBounds, double cellWidth, double cellHeight, int row, int col)
    {
        var x1 = boardBounds.Left + (int)Math.Round(col * cellWidth);
        var y1 = boardBounds.Top + (int)Math.Round(row * cellHeight);
        var x2 = boardBounds.Left + (int)Math.Round((col + 1) * cellWidth);
        var y2 = boardBounds.Top + (int)Math.Round((row + 1) * cellHeight);
        return new Rectangle(x1, y1, Math.Max(1, x2 - x1), Math.Max(1, y2 - y1));
    }

    private static CellStats MeasureCell(Image<Rgba32> image, Rectangle cellBounds)
    {
        var marginX = Math.Max(2, cellBounds.Width / 8);
        var marginY = Math.Max(2, cellBounds.Height / 8);
        var x1 = cellBounds.Left + marginX;
        var x2 = cellBounds.Right - marginX;
        var y1 = cellBounds.Top + marginY;
        var y2 = cellBounds.Bottom - marginY;

        var total = 0;
        var orange = 0;
        var dark = 0;
        var white = 0;

        for (var y = y1; y < y2; y++)
        {
            var rowSpan = image.DangerousGetPixelRowMemory(y).Span;
            for (var x = x1; x < x2; x++)
            {
                var pixel = rowSpan[x];
                total++;

                if (pixel.R > 210 && pixel.G is >= 130 and <= 210 && pixel.B < 120)
                {
                    orange++;
                }

                if (pixel.R < 80 && pixel.G < 80 && pixel.B < 80)
                {
                    dark++;
                }

                if (pixel.R > 230 && pixel.G > 230 && pixel.B > 230)
                {
                    white++;
                }
            }
        }

        return new CellStats(
            total == 0 ? 0 : orange / (double)total,
            total == 0 ? 0 : dark / (double)total,
            total == 0 ? 0 : white / (double)total);
    }

    private static bool IsLikelyTile(CellStats stats, BonusType bonus)
    {
        if (stats.OrangeRatio < 0.35)
        {
            return false;
        }

        if (stats.DarkRatio > 0.01)
        {
            return true;
        }

        return bonus != BonusType.DoubleWord && stats.WhiteRatio > 0.025;
    }

    private sealed record CellStats(double OrangeRatio, double DarkRatio, double WhiteRatio);
}
