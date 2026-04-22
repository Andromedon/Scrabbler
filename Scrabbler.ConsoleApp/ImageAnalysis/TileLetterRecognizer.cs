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
    private const double ReliableDigitConfidence = 0.12;
    private readonly IReadOnlyDictionary<char, IReadOnlyList<bool[,]>> _templates;
    private readonly IReadOnlyDictionary<char, int> _letterScores;

    public TileLetterRecognizer(IReadOnlyDictionary<char, int> letterScores)
    {
        _letterScores = letterScores;
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
        var candidates = ScoreCandidates(glyph);
        var selected = SelectCandidate(candidates, scoreDigit);
        var bestLetter = selected.Letter;
        var bestScore = selected.Score;
        var secondScore = selected.SecondScore;

        bestLetter = ApplyShapeHeuristics(glyph, bestLetter, scoreDigit);
        var confidence = (float)Math.Clamp(bestScore * 0.8 + Math.Max(0, bestScore - secondScore) * 0.8, 0, 1);
        return confidence < MinimumConfidence
            ? new LetterRecognitionResult(null, confidence)
            : new LetterRecognitionResult(bestLetter, confidence);
    }

    private IReadOnlyList<LetterCandidate> ScoreCandidates(bool[,] glyph)
    {
        return _templates
            .Select(pair => new LetterCandidate(
                pair.Key,
                pair.Value.Max(template => Similarity(glyph, template))))
            .OrderByDescending(candidate => candidate.Score)
            .ThenBy(candidate => candidate.Letter)
            .ToArray();
    }

    private SelectedLetter SelectCandidate(IReadOnlyList<LetterCandidate> candidates, DigitRecognitionResult scoreDigit)
    {
        if (scoreDigit.CanConstrain(_letterScores))
        {
            if (TryPromoteByScore(candidates[0].Letter, scoreDigit.Digit!.Value, out var promotedLetter))
            {
                return new SelectedLetter(
                    promotedLetter,
                    candidates[0].Score,
                    candidates.ElementAtOrDefault(1)?.Score ?? double.NegativeInfinity);
            }

            var matching = candidates
                .Where(candidate => _letterScores[candidate.Letter] == scoreDigit.Digit)
                .OrderByDescending(candidate => candidate.Score)
                .ThenBy(candidate => candidate.Letter)
                .ToArray();

            if (matching.Length > 0)
            {
                return new SelectedLetter(
                    matching[0].Letter,
                    matching[0].Score,
                    matching.ElementAtOrDefault(1)?.Score ?? double.NegativeInfinity);
            }
        }

        var penalty = scoreDigit.CanConstrain(_letterScores) ? Math.Min(0.22, scoreDigit.Confidence * 0.35) : 0;
        var scored = candidates
            .Select(candidate => new LetterCandidate(
                candidate.Letter,
                candidate.Score - (scoreDigit.CanConstrain(_letterScores) && _letterScores[candidate.Letter] != scoreDigit.Digit ? penalty : 0)))
            .OrderByDescending(candidate => candidate.Score)
            .ThenBy(candidate => candidate.Letter)
            .ToArray();

        return new SelectedLetter(
            scored[0].Letter,
            scored[0].Score,
            scored.ElementAtOrDefault(1)?.Score ?? double.NegativeInfinity);
    }

    private bool TryPromoteByScore(char letter, int score, out char promotedLetter)
    {
        var promotions = PolishAlphabet.Letters
            .Where(candidate => candidate != letter && _letterScores[candidate] == score)
            .Where(candidate => BaseLetter(candidate) == letter)
            .OrderBy(candidate => candidate)
            .ToArray();
        promotedLetter = promotions.Length == 1 ? promotions[0] : default;

        return promotedLetter != default;
    }

    private static char BaseLetter(char letter)
    {
        return letter switch
        {
            'Ą' => 'A',
            'Ć' => 'C',
            'Ę' => 'E',
            'Ł' => 'L',
            'Ń' => 'N',
            'Ó' => 'O',
            'Ś' => 'S',
            'Ź' => 'Z',
            'Ż' => 'Z',
            _ => letter
        };
    }

    private char ApplyShapeHeuristics(bool[,] glyph, char bestLetter, DigitRecognitionResult scoreDigit)
    {
        if (bestLetter is 'B' or 'D')
        {
            var bOrDDigit = scoreDigit.CanConstrain(_letterScores)
                ? scoreDigit.Digit
                : scoreDigit.WeakTwoOrThreeDigit;

            if (_letterScores['B'] == bOrDDigit)
            {
                return 'B';
            }

            if (_letterScores['D'] == bOrDDigit)
            {
                return 'D';
            }
        }

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

        if (CanUseHeuristicLetter('B', scoreDigit) && bestLetter == 'D' && middle > 0.12 && bottom > 0.20)
        {
            return 'B';
        }

        if (scoreDigit.CanConstrain(_letterScores)
            && scoreDigit.Digit == _letterScores['Ź']
            && _letterScores['Ź'] == _letterScores['Ż']
            && bestLetter is 'Ź' or 'Ż')
        {
            return HasWideTopAccent(glyph) ? 'Ź' : 'Ż';
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

    private static bool HasWideTopAccent(bool[,] glyph)
    {
        var points = new List<Point>();
        for (var y = 0; y < 7; y++)
        {
            for (var x = 0; x < TemplateSize; x++)
            {
                if (glyph[y, x])
                {
                    points.Add(new Point(x, y));
                }
            }
        }

        if (points.Count == 0)
        {
            return false;
        }

        var width = points.Max(point => point.X) - points.Min(point => point.X) + 1;
        var height = points.Max(point => point.Y) - points.Min(point => point.Y) + 1;
        return width >= height * 1.4;
    }

    private bool CanUseHeuristicLetter(char letter, DigitRecognitionResult scoreDigit)
    {
        return scoreDigit.CanConstrain(_letterScores) && _letterScores[letter] == scoreDigit.Digit;
    }

    private static DigitRecognitionResult RecognizeScoreDigit(Image<Rgba32> image, Rectangle cellBounds)
    {
        var scoreBounds = new Rectangle(
            cellBounds.Left + (int)(cellBounds.Width * 0.58),
            cellBounds.Top,
            Math.Max(1, (int)(cellBounds.Width * 0.36)),
            Math.Max(1, (int)(cellBounds.Height * 0.34)));
        var pixels = ExtractForegroundPixels(image, scoreBounds, ignoreTopRight: false, includeWhite: false);
        var component = LargestComponent(pixels);
        if (component.Count == 0)
        {
            return DigitRecognitionResult.None;
        }

        var glyph = NormalizeComponent(component);
        var bestDigit = 0;
        var bestScore = 0.0;
        var secondScore = 0.0;
        foreach (var (digit, templates) in DigitTemplates.Value)
        {
            var score = templates.Max(template => Similarity(glyph, template));
            if (score > bestScore)
            {
                secondScore = bestScore;
                bestScore = score;
                bestDigit = digit;
            }
            else if (score > secondScore)
            {
                secondScore = score;
            }
        }

        var confidence = Math.Clamp(bestScore * 0.8 + Math.Max(0, bestScore - secondScore) * 0.8, 0, 1);
        var twoOrThree = TryRecognizeTwoOrThree(glyph);
        if (bestDigit is 2 or 3 && twoOrThree is not null)
        {
            return new DigitRecognitionResult(twoOrThree.Value, Math.Max(confidence, ReliableDigitConfidence));
        }

        if (bestScore >= 0.18)
        {
            return new DigitRecognitionResult(bestDigit, confidence, twoOrThree);
        }

        return new DigitRecognitionResult(null, 0, twoOrThree);
    }

    private static int? TryRecognizeTwoOrThree(bool[,] glyph)
    {
        var lowerLeft = Density(glyph, 17, 28, 2, 13);
        var lowerRight = Density(glyph, 17, 28, 19, 30);
        var middle = Density(glyph, 12, 19, 5, 27);
        var bottom = Density(glyph, 24, 31, 4, 28);

        if (middle < 0.015 || bottom < 0.03)
        {
            return null;
        }

        if (lowerLeft > lowerRight + 0.01)
        {
            return 2;
        }

        if (lowerRight > lowerLeft + 0.01)
        {
            return 3;
        }

        if (lowerLeft < 0.02 && lowerRight > 0.005)
        {
            return 3;
        }

        return null;
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
        var component = MainGlyphComponents(threshold);
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
                var isDark = pixel.R < 150 && pixel.G < 150 && pixel.B < 150;
                var isWhite = includeWhite && pixel.R > 235 && pixel.G > 235 && pixel.B > 235;
                pixels[y, x] = isDark || isWhite;
            }
        }

        return pixels;
    }

    private static List<Point> LargestComponent(bool[,] pixels)
    {
        return ConnectedComponents(pixels)
            .OrderByDescending(component => component.Count)
            .FirstOrDefault() ?? new List<Point>();
    }

    private static List<Point> MainGlyphComponents(bool[,] pixels)
    {
        var components = ConnectedComponents(pixels)
            .OrderByDescending(component => component.Count)
            .ToArray();
        if (components.Length == 0)
        {
            return new List<Point>();
        }

        var main = components[0];
        var minX = main.Min(point => point.X);
        var maxX = main.Max(point => point.X);
        var minY = main.Min(point => point.Y);
        var maxY = main.Max(point => point.Y);
        var height = Math.Max(1, maxY - minY + 1);
        var points = new List<Point>(main);

        foreach (var component in components.Skip(1))
        {
            if (component.Count < 2)
            {
                continue;
            }

            var componentMinX = component.Min(point => point.X);
            var componentMaxX = component.Max(point => point.X);
            var componentMaxY = component.Max(point => point.Y);
            var overlapsGlyph = componentMaxX >= minX - 8 && componentMinX <= maxX + 8;
            var sitsAboveGlyph = componentMaxY <= minY + height * 0.35;

            if (overlapsGlyph && sitsAboveGlyph)
            {
                points.AddRange(component);
            }
        }

        return points;
    }

    private static List<List<Point>> ConnectedComponents(bool[,] pixels)
    {
        var height = pixels.GetLength(0);
        var width = pixels.GetLength(1);
        var visited = new bool[height, width];
        var components = new List<List<Point>>();

        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                if (!pixels[y, x] || visited[y, x])
                {
                    continue;
                }

                var component = FloodFill(pixels, visited, x, y);
                components.Add(component);
            }
        }

        return components;
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
        var fonts = ResolveFonts(52);
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
        var fonts = ResolveFonts(52);
        return Enumerable.Range(1, 9).ToDictionary(
            digit => digit,
            digit => (IReadOnlyList<bool[,]>)fonts
                .Select(font => TryRenderTemplate(digit.ToString()[0], font))
                .Where(template => template is not null)
                .Select(template => template!)
                .ToArray());
    }

    private static IReadOnlyList<Font> ResolveFonts(float size)
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
                fonts.Add(family.CreateFont(size, FontStyle.Bold));
            }
            catch
            {
                // Try the next system font.
            }
        }

        fonts.AddRange(SystemFonts.Families.Take(8).Select(family => family.CreateFont(size, FontStyle.Bold)));
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
        return NormalizeComponent(MainGlyphComponents(pixels));
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

    private sealed record LetterCandidate(char Letter, double Score);

    private sealed record SelectedLetter(char Letter, double Score, double SecondScore);

    private sealed record DigitRecognitionResult(int? Digit, double Confidence, int? WeakTwoOrThreeDigit = null)
    {
        public static DigitRecognitionResult None { get; } = new(null, 0, null);

        public bool CanConstrain(IReadOnlyDictionary<char, int> letterScores)
        {
            return Digit is not null
            && Confidence >= ReliableDigitConfidence
            && letterScores.Any(pair => pair.Value == Digit.Value);
        }
    }
}

public sealed record LetterRecognitionResult(char? Letter, float Confidence);
