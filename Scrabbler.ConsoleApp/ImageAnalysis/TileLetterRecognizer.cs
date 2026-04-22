using Scrabbler.App.BoardModel;
using SixLabors.Fonts;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Advanced;
using SixLabors.ImageSharp.Drawing.Processing;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace Scrabbler.App.ImageAnalysis;

public sealed class TileLetterRecognizer
{
    private const int TemplateSize = 32;
    private const float MinimumConfidence = 0.20f;
    private readonly IReadOnlyDictionary<char, IReadOnlyList<bool[,]>> _templates;

    public TileLetterRecognizer()
    {
        _templates = BuildTemplates();
    }

    public LetterRecognitionResult Recognize(Image<Rgba32> image, Rectangle cellBounds)
    {
        var glyph = ExtractMainGlyph(image, cellBounds);
        if (glyph is null)
        {
            return new LetterRecognitionResult(null, 0);
        }

        var scoreDigit = RecognizeScoreDigit(image, cellBounds);
        var bestLetter = default(char);
        var bestScore = double.NegativeInfinity;
        var secondScore = double.NegativeInfinity;

        foreach (var (letter, templates) in _templates.Where(pair => scoreDigit is null || LetterScores[pair.Key] == scoreDigit.Value))
        {
            var score = templates.Max(template => Similarity(glyph, template));
            if (score > bestScore)
            {
                secondScore = bestScore;
                bestScore = score;
                bestLetter = letter;
            }
            else if (score > secondScore)
            {
                secondScore = score;
            }
        }

        bestLetter = ApplyShapeHeuristics(glyph, bestLetter, scoreDigit);
        var confidence = (float)Math.Clamp(bestScore * 0.8 + Math.Max(0, bestScore - secondScore) * 0.8, 0, 1);
        return confidence < MinimumConfidence
            ? new LetterRecognitionResult(null, confidence)
            : new LetterRecognitionResult(bestLetter, confidence);
    }

    private static char ApplyShapeHeuristics(bool[,] glyph, char bestLetter, int? scoreDigit)
    {
        var top = Density(glyph, 2, 8, 4, 28);
        var middle = Density(glyph, 13, 19, 5, 27);
        var bottom = Density(glyph, 24, 31, 4, 28);
        var lowerRight = Density(glyph, 18, 31, 16, 30);
        var lowerLeft = Density(glyph, 18, 31, 2, 14);
        var left = Density(glyph, 6, 26, 2, 10);
        var right = Density(glyph, 6, 26, 22, 30);

        if (CanUseHeuristicLetter('T', scoreDigit) && bestLetter == 'J' && top > 0.20 && bottom < 0.18)
        {
            return 'T';
        }

        if (CanUseHeuristicLetter('R', scoreDigit) && bestLetter == 'P' && lowerRight > 0.06)
        {
            return 'R';
        }

        if (CanUseHeuristicLetter('D', scoreDigit) && bestLetter == 'B' && middle < 0.12 && bottom < 0.22)
        {
            return 'D';
        }

        if (CanUseHeuristicLetter('O', scoreDigit) && bestLetter == 'D' && Math.Abs(left - right) < 0.10 && middle < 0.10)
        {
            return 'O';
        }

        if (CanUseHeuristicLetter('T', scoreDigit) && bestLetter == 'Y' && lowerLeft < 0.04 && lowerRight < 0.04 && top > 0.18)
        {
            return 'T';
        }

        return bestLetter;
    }

    private static bool CanUseHeuristicLetter(char letter, int? scoreDigit)
    {
        return scoreDigit is null || LetterScores[letter] == scoreDigit.Value;
    }

    private static int? RecognizeScoreDigit(Image<Rgba32> image, Rectangle cellBounds)
    {
        var scoreBounds = new Rectangle(
            cellBounds.Left + (int)(cellBounds.Width * 0.58),
            cellBounds.Top,
            Math.Max(1, (int)(cellBounds.Width * 0.36)),
            Math.Max(1, (int)(cellBounds.Height * 0.34)));
        var pixels = ExtractForegroundPixels(image, scoreBounds, ignoreTopRight: false, includeWhite: false);
        var component = LargestComponent(pixels);
        if (component.Count < 3)
        {
            return null;
        }

        var glyph = NormalizeComponent(component);
        var bestDigit = 0;
        var bestScore = 0.0;
        foreach (var (digit, templates) in DigitTemplates.Value)
        {
            var score = templates.Max(template => Similarity(glyph, template));
            if (score > bestScore)
            {
                bestScore = score;
                bestDigit = digit;
            }
        }

        return bestScore < 0.18 ? null : bestDigit;
    }

    private static double Density(bool[,] glyph, int y1, int y2, int x1, int x2)
    {
        var count = 0;
        var total = 0;
        for (var y = Math.Max(0, y1); y <= Math.Min(TemplateSize - 1, y2); y++)
        {
            for (var x = Math.Max(0, x1); x <= Math.Min(TemplateSize - 1, x2); x++)
            {
                total++;
                if (glyph[y, x])
                {
                    count++;
                }
            }
        }

        return total == 0 ? 0 : count / (double)total;
    }

    private static bool[,]? ExtractMainGlyph(Image<Rgba32> image, Rectangle cellBounds)
    {
        var threshold = ExtractForegroundPixels(image, cellBounds, ignoreTopRight: true, includeWhite: true);
        var component = LargestComponent(threshold);
        if (component.Count < 20)
        {
            return null;
        }

        return NormalizeComponent(component);
    }

    private static bool[,] ExtractForegroundPixels(Image<Rgba32> image, Rectangle cellBounds, bool ignoreTopRight, bool includeWhite)
    {
        var pixels = new bool[cellBounds.Height, cellBounds.Width];
        for (var y = 0; y < cellBounds.Height; y++)
        {
            var sourceY = cellBounds.Top + y;
            var rowSpan = image.DangerousGetPixelRowMemory(sourceY).Span;
            for (var x = 0; x < cellBounds.Width; x++)
            {
                if (ignoreTopRight && x > cellBounds.Width * 0.58 && y < cellBounds.Height * 0.38)
                {
                    continue;
                }

                var pixel = rowSpan[cellBounds.Left + x];
                var isDark = pixel.R < 95 && pixel.G < 95 && pixel.B < 95;
                var isWhite = includeWhite && pixel.R > 235 && pixel.G > 235 && pixel.B > 235;
                pixels[y, x] = isDark || isWhite;
            }
        }

        return pixels;
    }

    private static List<Point> LargestComponent(bool[,] pixels)
    {
        var height = pixels.GetLength(0);
        var width = pixels.GetLength(1);
        var visited = new bool[height, width];
        var best = new List<Point>();

        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                if (!pixels[y, x] || visited[y, x])
                {
                    continue;
                }

                var component = FloodFill(pixels, visited, x, y);
                if (component.Count > best.Count)
                {
                    best = component;
                }
            }
        }

        return best;
    }

    private static List<Point> FloodFill(bool[,] pixels, bool[,] visited, int startX, int startY)
    {
        var height = pixels.GetLength(0);
        var width = pixels.GetLength(1);
        var queue = new Queue<Point>();
        var component = new List<Point>();
        queue.Enqueue(new Point(startX, startY));
        visited[startY, startX] = true;

        while (queue.Count > 0)
        {
            var point = queue.Dequeue();
            component.Add(point);

            foreach (var (dx, dy) in Directions)
            {
                var x = point.X + dx;
                var y = point.Y + dy;
                if (x < 0 || y < 0 || x >= width || y >= height || visited[y, x] || !pixels[y, x])
                {
                    continue;
                }

                visited[y, x] = true;
                queue.Enqueue(new Point(x, y));
            }
        }

        return component;
    }

    private static bool[,] NormalizeComponent(IReadOnlyList<Point> component)
    {
        var minX = component.Min(point => point.X);
        var maxX = component.Max(point => point.X);
        var minY = component.Min(point => point.Y);
        var maxY = component.Max(point => point.Y);
        var sourceWidth = Math.Max(1, maxX - minX + 1);
        var sourceHeight = Math.Max(1, maxY - minY + 1);
        var scale = Math.Min((TemplateSize - 4) / (double)sourceWidth, (TemplateSize - 4) / (double)sourceHeight);
        var targetWidth = Math.Max(1, (int)Math.Round(sourceWidth * scale));
        var targetHeight = Math.Max(1, (int)Math.Round(sourceHeight * scale));
        var offsetX = (TemplateSize - targetWidth) / 2;
        var offsetY = (TemplateSize - targetHeight) / 2;
        var normalized = new bool[TemplateSize, TemplateSize];

        foreach (var point in component)
        {
            var x = offsetX + (int)Math.Round((point.X - minX) * scale);
            var y = offsetY + (int)Math.Round((point.Y - minY) * scale);
            if (x >= 0 && y >= 0 && x < TemplateSize && y < TemplateSize)
            {
                normalized[y, x] = true;
            }
        }

        return normalized;
    }

    private static double Similarity(bool[,] glyph, bool[,] template)
    {
        var intersection = 0;
        var union = 0;
        for (var y = 0; y < TemplateSize; y++)
        {
            for (var x = 0; x < TemplateSize; x++)
            {
                if (glyph[y, x] && template[y, x])
                {
                    intersection++;
                }

                if (glyph[y, x] || template[y, x])
                {
                    union++;
                }
            }
        }

        return union == 0 ? 0 : intersection / (double)union;
    }

    private static IReadOnlyDictionary<char, IReadOnlyList<bool[,]>> BuildTemplates()
    {
        var fonts = ResolveFonts();
        return PolishAlphabet.Letters.ToDictionary(
            letter => letter,
            letter => (IReadOnlyList<bool[,]>)fonts
                .Select(font => TryRenderTemplate(letter, font))
                .Where(template => template is not null)
                .Select(template => template!)
                .ToArray());
    }

    private static IReadOnlyDictionary<int, IReadOnlyList<bool[,]>> BuildDigitTemplates()
    {
        var fonts = ResolveFonts();
        return Enumerable.Range(1, 9).ToDictionary(
            digit => digit,
            digit => (IReadOnlyList<bool[,]>)fonts
                .Select(font => TryRenderTemplate(digit.ToString()[0], font))
                .Where(template => template is not null)
                .Select(template => template!)
                .ToArray());
    }

    private static IReadOnlyList<Font> ResolveFonts()
    {
        var collection = new FontCollection();
        var fonts = new List<Font>();
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
                var family = collection.Add(path);
                fonts.Add(family.CreateFont(52, FontStyle.Bold));
            }
            catch
            {
                // Try the next system font.
            }
        }

        fonts.AddRange(SystemFonts.Families.Take(8).Select(family => family.CreateFont(52, FontStyle.Bold)));
        return fonts;
    }

    private static bool[,] RenderTemplate(char letter, Font font)
    {
        using var image = new Image<Rgba32>(72, 72, Color.White);
        var text = letter.ToString();
        var options = new RichTextOptions(font)
        {
            Origin = new PointF(36, 36),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        image.Mutate(context => context.DrawText(options, text, Color.Black));
        var pixels = ExtractForegroundPixels(image, new Rectangle(0, 0, image.Width, image.Height), ignoreTopRight: false, includeWhite: false);
        var component = LargestComponent(pixels);
        return NormalizeComponent(component);
    }

    private static bool[,]? TryRenderTemplate(char letter, Font font)
    {
        try
        {
            return RenderTemplate(letter, font);
        }
        catch
        {
            return null;
        }
    }

    private static readonly (int Dx, int Dy)[] Directions =
    {
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1)
    };

    private static readonly Lazy<IReadOnlyDictionary<int, IReadOnlyList<bool[,]>>> DigitTemplates = new(BuildDigitTemplates);

    private static readonly IReadOnlyDictionary<char, int> LetterScores = new Dictionary<char, int>
    {
        ['A'] = 1,
        ['Ą'] = 5,
        ['B'] = 3,
        ['C'] = 2,
        ['Ć'] = 6,
        ['D'] = 2,
        ['E'] = 1,
        ['Ę'] = 5,
        ['F'] = 5,
        ['G'] = 3,
        ['H'] = 3,
        ['I'] = 1,
        ['J'] = 3,
        ['K'] = 2,
        ['L'] = 2,
        ['Ł'] = 3,
        ['M'] = 2,
        ['N'] = 1,
        ['Ń'] = 7,
        ['O'] = 1,
        ['Ó'] = 5,
        ['P'] = 2,
        ['R'] = 1,
        ['S'] = 1,
        ['Ś'] = 5,
        ['T'] = 2,
        ['U'] = 3,
        ['W'] = 1,
        ['Y'] = 2,
        ['Z'] = 1,
        ['Ź'] = 9,
        ['Ż'] = 5
    };
}

public sealed record LetterRecognitionResult(char? Letter, float Confidence);
