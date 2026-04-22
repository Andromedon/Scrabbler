using System.Text;
using Scrabbler.App.BoardModel;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Advanced;
using SixLabors.ImageSharp.PixelFormats;

namespace Scrabbler.App.ImageAnalysis;

public sealed class TileLetterRecognizer
{
    private const int MaskSize = 32;
    private const float MinimumConfidence = 0.10f;
    private readonly IReadOnlyDictionary<char, int> _letterScores;
    private readonly LetterSampleLibrary _samples;

    public TileLetterRecognizer(IReadOnlyDictionary<char, int> letterScores, string samplesDirectory)
    {
        _letterScores = letterScores;
        _samples = LetterSampleLibrary.Load(samplesDirectory, letterScores);
    }

    public LetterRecognitionResult Recognize(Image<Rgba32> image, Rectangle cellBounds)
    {
        var recognitionBounds = Inset(cellBounds, 0.035);
        var shapeMask = ExtractShapeMask(image, recognitionBounds);
        var tileMask = ExtractLetterMask(image, recognitionBounds);
        if (shapeMask is null || tileMask is null)
        {
            return new LetterRecognitionResult(null, 0);
        }

        var scoreDigit = RecognizeScoreDigit(image, recognitionBounds);
        var candidates = _samples.Samples
            .Select(sample => new LetterCandidate(
                sample.Letter,
                Similarity(shapeMask, sample.ShapeMask) * 0.70 + Similarity(tileMask, sample.TileMask) * 0.30))
            .OrderByDescending(candidate => candidate.Score)
            .ThenBy(candidate => candidate.Letter)
            .ToArray();

        if (candidates.Length == 0)
        {
            return new LetterRecognitionResult(null, 0);
        }

        var selected = SelectCandidate(candidates, scoreDigit);
        var confidence = CalculateConfidence(selected.Score, selected.SecondScore, scoreDigit, selected.Letter);
        return confidence < MinimumConfidence
            ? new LetterRecognitionResult(null, confidence)
            : new LetterRecognitionResult(selected.Letter, confidence);
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

    private SelectedLetter SelectCandidate(IReadOnlyList<LetterCandidate> candidates, DigitRecognitionResult scoreDigit)
    {
        if (scoreDigit.IsReliable && scoreDigit.Digit is not null)
        {
            if (_letterScores[candidates[0].Letter] == scoreDigit.Digit.Value)
            {
                return new SelectedLetter(
                    candidates[0].Letter,
                    candidates[0].Score,
                    candidates.ElementAtOrDefault(1)?.Score ?? 0);
            }

            var matchingScore = candidates
                .Where(candidate => _letterScores[candidate.Letter] == scoreDigit.Digit.Value)
                .OrderByDescending(candidate => candidate.Score)
                .ThenBy(candidate => candidate.Letter)
                .ToArray();

            if (matchingScore.Length > 0)
            {
                var closeEnough = scoreDigit.Confidence >= 0.45 || scoreDigit.Digit == 1;
                if (closeEnough && matchingScore[0].Score >= candidates[0].Score * 0.90)
                {
                    return new SelectedLetter(
                        matchingScore[0].Letter,
                        matchingScore[0].Score,
                        matchingScore.ElementAtOrDefault(1)?.Score ?? 0);
                }
            }
        }

        return new SelectedLetter(
            candidates[0].Letter,
            candidates[0].Score,
            candidates.ElementAtOrDefault(1)?.Score ?? 0);
    }

    private float CalculateConfidence(double score, double secondScore, DigitRecognitionResult scoreDigit, char letter)
    {
        var margin = Math.Max(0, score - secondScore);
        var confidence = score * 0.75 + margin * 0.9;
        if (scoreDigit.IsReliable && scoreDigit.Digit == _letterScores[letter])
        {
            confidence += 0.12;
        }

        return (float)Math.Clamp(confidence, 0, 1);
    }

    private static bool[,]? ExtractLetterMask(Image<Rgba32> image, Rectangle bounds)
    {
        var mask = ExtractTileMask(image, bounds);
        var ink = 0;
        for (var y = 0; y < MaskSize; y++)
        {
            for (var x = 0; x < MaskSize; x++)
            {
                if (mask[y, x])
                {
                    ink++;
                }
            }
        }

        if (ink < 12)
        {
            return null;
        }

        return mask;
    }

    private static bool[,]? ExtractShapeMask(Image<Rgba32> image, Rectangle bounds)
    {
        var pixels = ExtractForegroundPixels(image, bounds, includeLight: true);
        RemoveScoreDigitComponents(pixels);
        var component = MainGlyphComponents(pixels);
        if (component.Count < 12)
        {
            return null;
        }

        return NormalizeComponent(component);
    }

    private static bool[,] ExtractTileMask(Image<Rgba32> image, Rectangle bounds)
    {
        var mask = new bool[MaskSize, MaskSize];
        for (var y = 0; y < MaskSize; y++)
        {
            var sourceY = bounds.Top + Math.Min(bounds.Height - 1, (int)((y + 0.5) * bounds.Height / MaskSize));
            if (sourceY < 0 || sourceY >= image.Height)
            {
                continue;
            }

            var row = image.DangerousGetPixelRowMemory(sourceY).Span;
            for (var x = 0; x < MaskSize; x++)
            {
                var sourceX = bounds.Left + Math.Min(bounds.Width - 1, (int)((x + 0.5) * bounds.Width / MaskSize));
                if (sourceX < 0 || sourceX >= image.Width)
                {
                    continue;
                }

                var pixel = row[sourceX];
                if (IsRedBadgePixel(pixel))
                {
                    continue;
                }

                var isDark = IsDarkGlyphPixel(pixel);
                var isLightGlyph = pixel.R > 235
                    && pixel.G > 235
                    && pixel.B > 235
                    && IsOrangeLike(GetLocalBackground(image, sourceX, sourceY, bounds));
                mask[y, x] = isDark || isLightGlyph;
            }
        }

        return mask;
    }

    private DigitRecognitionResult RecognizeScoreDigit(Image<Rgba32> image, Rectangle cellBounds)
    {
        var scoreBounds = GetScoreBounds(cellBounds);
        var glyph = ExtractScoreMask(image, scoreBounds);
        if (glyph is null)
        {
            return DigitRecognitionResult.None;
        }

        var shapeDigit = TryRecognizeDigitByShape(glyph);
        if (shapeDigit is 1)
        {
            return new DigitRecognitionResult(shapeDigit.Value, 0.35, true);
        }

        var bestDigit = 0;
        var bestScore = 0.0;
        var secondScore = 0.0;
        foreach (var sample in _samples.DigitSamples)
        {
            var score = Similarity(glyph, sample.Mask);
            if (score > bestScore)
            {
                secondScore = bestScore;
                bestScore = score;
                bestDigit = sample.Digit;
            }
            else if (score > secondScore)
            {
                secondScore = score;
            }
        }

        var confidence = Math.Clamp(bestScore * 0.8 + Math.Max(0, bestScore - secondScore) * 1.1, 0, 1);
        return confidence >= 0.25
            ? new DigitRecognitionResult(bestDigit, confidence, true)
            : DigitRecognitionResult.None;
    }

    private static int? TryRecognizeDigitByShape(bool[,] glyph)
    {
        var points = GlyphPoints(glyph);
        if (points.Count == 0)
        {
            return null;
        }

        var width = points.Max(point => point.X) - points.Min(point => point.X) + 1;
        var height = points.Max(point => point.Y) - points.Min(point => point.Y) + 1;
        return width <= 12 && height >= 18 ? 1 : null;
    }

    private static Rectangle GetScoreBounds(Rectangle cellBounds)
    {
        return new Rectangle(
            cellBounds.Left + (int)(cellBounds.Width * 0.55),
            cellBounds.Top,
            Math.Max(1, (int)(cellBounds.Width * 0.40)),
            Math.Max(1, (int)(cellBounds.Height * 0.32)));
    }

    private static bool[,]? ExtractScoreMask(Image<Rgba32> image, Rectangle scoreBounds)
    {
        var pixels = ExtractForegroundPixels(image, scoreBounds, includeLight: false);
        var component = ScoreDigitComponent(pixels);
        return component.Count < 3 ? null : NormalizeComponent(component);
    }

    private static bool[,] ExtractForegroundPixels(Image<Rgba32> image, Rectangle bounds, bool includeLight)
    {
        var pixels = new bool[bounds.Height, bounds.Width];
        for (var y = 0; y < bounds.Height; y++)
        {
            var sourceY = bounds.Top + y;
            if (sourceY < 0 || sourceY >= image.Height)
            {
                continue;
            }

            var rowSpan = image.DangerousGetPixelRowMemory(sourceY).Span;
            for (var x = 0; x < bounds.Width; x++)
            {
                var sourceX = bounds.Left + x;
                if (sourceX < 0 || sourceX >= image.Width)
                {
                    continue;
                }

                var pixel = rowSpan[sourceX];
                if (IsRedBadgePixel(pixel))
                {
                    continue;
                }

                var isDark = IsDarkGlyphPixel(pixel);
                var isLightGlyph = includeLight
                    && pixel.R > 235
                    && pixel.G > 235
                    && pixel.B > 235
                    && IsOrangeLike(GetLocalBackground(image, sourceX, sourceY, bounds));
                pixels[y, x] = isDark || isLightGlyph;
            }
        }

        return pixels;
    }

    private static Rgba32 GetLocalBackground(Image<Rgba32> image, int x, int y, Rectangle bounds)
    {
        var radius = Math.Max(2, Math.Min(bounds.Width, bounds.Height) / 8);
        var orange = new List<Rgba32>();
        var left = Math.Max(0, bounds.Left);
        var right = Math.Min(image.Width, bounds.Right);
        var top = Math.Max(0, bounds.Top);
        var bottom = Math.Min(image.Height, bounds.Bottom);
        for (var yy = Math.Max(top, y - radius); yy < Math.Min(bottom, y + radius + 1); yy++)
        {
            var row = image.DangerousGetPixelRowMemory(yy).Span;
            for (var xx = Math.Max(left, x - radius); xx < Math.Min(right, x + radius + 1); xx++)
            {
                var pixel = row[xx];
                if (IsOrangeLike(pixel))
                {
                    orange.Add(pixel);
                }
            }
        }

        return orange.Count == 0 ? default : orange[0];
    }

    internal static bool IsRedBadgePixel(Rgba32 pixel)
    {
        return pixel.R > 180 && pixel.G < 95 && pixel.B < 95 && pixel.R > pixel.G * 1.8;
    }

    private static bool IsOrangeLike(Rgba32 pixel)
    {
        return pixel.R > 190 && pixel.G is >= 120 and <= 210 && pixel.B < 130;
    }

    private static bool IsDarkGlyphPixel(Rgba32 pixel)
    {
        var max = Math.Max(pixel.R, Math.Max(pixel.G, pixel.B));
        var min = Math.Min(pixel.R, Math.Min(pixel.G, pixel.B));
        return max < 190 && max - min < 90;
    }

    private static void RemoveScoreDigitComponents(bool[,] pixels)
    {
        var height = pixels.GetLength(0);
        var width = pixels.GetLength(1);
        foreach (var component in ConnectedComponents(pixels))
        {
            var minX = component.Min(point => point.X);
            var maxX = component.Max(point => point.X);
            var minY = component.Min(point => point.Y);
            var maxY = component.Max(point => point.Y);
            var componentWidth = maxX - minX + 1;
            var componentHeight = maxY - minY + 1;
            var centerX = component.Average(point => point.X);
            var centerY = component.Average(point => point.Y);

            var inScoreArea = centerX >= width * 0.55 && centerY <= height * 0.35;
            var digitSized = componentWidth <= width * 0.28 && componentHeight <= height * 0.30;
            if (!inScoreArea || !digitSized)
            {
                continue;
            }

            foreach (var point in component)
            {
                pixels[point.Y, point.X] = false;
            }
        }
    }

    private static List<Point> ScoreDigitComponent(bool[,] pixels)
    {
        var height = pixels.GetLength(0);
        var width = pixels.GetLength(1);
        return ConnectedComponents(pixels)
            .Where(component => component.Count >= 3)
            .Select(component => new
            {
                Component = component,
                MinX = component.Min(point => point.X),
                MaxX = component.Max(point => point.X),
                MinY = component.Min(point => point.Y),
                MaxY = component.Max(point => point.Y),
                CenterX = component.Average(point => point.X),
                CenterY = component.Average(point => point.Y)
            })
            .Where(candidate =>
            {
                var componentWidth = candidate.MaxX - candidate.MinX + 1;
                var componentHeight = candidate.MaxY - candidate.MinY + 1;
                return candidate.CenterX >= width * 0.25
                    && candidate.CenterY <= height * 0.90
                    && componentWidth <= width * 0.75
                    && componentHeight <= height * 0.90;
            })
            .OrderByDescending(candidate => candidate.CenterX)
            .ThenBy(candidate => candidate.CenterY)
            .ThenByDescending(candidate => candidate.Component.Count)
            .Select(candidate => candidate.Component)
            .FirstOrDefault() ?? new List<Point>();
    }

    private static List<Point> MainGlyphComponents(bool[,] pixels, bool includeScoreLikeMarks = false)
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
            var componentCenterX = component.Average(point => point.X);
            var overlapsGlyph = componentMaxX >= minX - 4
                && componentMinX <= maxX + 4
                && componentCenterX >= minX - 4
                && componentCenterX <= maxX + 4;
            var sitsAboveGlyph = componentMaxY <= minY + height * 0.38;

            if (overlapsGlyph && sitsAboveGlyph)
            {
                points.AddRange(component);
                continue;
            }

            if (includeScoreLikeMarks)
            {
                var componentMinY = component.Min(point => point.Y);
                var scoreComponentCenterX = component.Average(point => point.X);
                var scoreLike = scoreComponentCenterX > maxX
                    && componentMinY <= minY + height * 0.40
                    && component.Count <= main.Count * 0.35;
                if (scoreLike)
                {
                    points.AddRange(component);
                }
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

                components.Add(FloodFill(pixels, visited, x, y));
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
        var scale = Math.Min((MaskSize - 4) / (double)sourceWidth, (MaskSize - 4) / (double)sourceHeight);
        var targetWidth = Math.Max(1, (int)Math.Round(sourceWidth * scale));
        var targetHeight = Math.Max(1, (int)Math.Round(sourceHeight * scale));
        var offsetX = (MaskSize - targetWidth) / 2;
        var offsetY = (MaskSize - targetHeight) / 2;
        var normalized = new bool[MaskSize, MaskSize];

        foreach (var point in component)
        {
            var x = offsetX + (int)Math.Round((point.X - minX) * scale);
            var y = offsetY + (int)Math.Round((point.Y - minY) * scale);
            if (x >= 0 && y >= 0 && x < MaskSize && y < MaskSize)
            {
                normalized[y, x] = true;
            }
        }

        return normalized;
    }

    private static List<Point> GlyphPoints(bool[,] glyph)
    {
        var points = new List<Point>();
        for (var y = 0; y < MaskSize; y++)
        {
            for (var x = 0; x < MaskSize; x++)
            {
                if (glyph[y, x])
                {
                    points.Add(new Point(x, y));
                }
            }
        }

        return points;
    }

    private static double Similarity(bool[,] glyph, bool[,] template)
    {
        var intersection = 0;
        var glyphPixels = 0;
        var templatePixels = 0;
        for (var y = 0; y < MaskSize; y++)
        {
            for (var x = 0; x < MaskSize; x++)
            {
                if (glyph[y, x])
                {
                    glyphPixels++;
                }

                if (template[y, x])
                {
                    templatePixels++;
                }

                if (glyph[y, x] && template[y, x])
                {
                    intersection++;
                }
            }
        }

        return glyphPixels == 0 || templatePixels == 0
            ? 0
            : intersection / Math.Sqrt(glyphPixels * templatePixels);
    }

    private static readonly (int Dx, int Dy)[] Directions =
    {
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1)
    };

    private sealed record LetterCandidate(char Letter, double Score);

    private sealed record SelectedLetter(char Letter, double Score, double SecondScore);

    private sealed record DigitRecognitionResult(int? Digit, double Confidence, bool IsReliable)
    {
        public static DigitRecognitionResult None { get; } = new(null, 0, false);
    }

    internal sealed record DigitSample(int Digit, bool[,] Mask);

    public sealed record LetterSample(char Letter, bool[,] ShapeMask, bool[,] TileMask);

    public sealed class LetterSampleLibrary
    {
        private LetterSampleLibrary(IReadOnlyList<LetterSample> samples, IReadOnlyList<DigitSample> digitSamples)
        {
            Samples = samples;
            DigitSamples = digitSamples;
        }

        public IReadOnlyList<LetterSample> Samples { get; }

        internal IReadOnlyList<DigitSample> DigitSamples { get; }

        public static LetterSampleLibrary Load(string samplesDirectory, IReadOnlyDictionary<char, int> letterScores)
        {
            if (!Directory.Exists(samplesDirectory))
            {
                throw new InvalidOperationException($"Letter samples directory does not exist: {samplesDirectory}");
            }

            var samples = Directory.EnumerateFiles(samplesDirectory, "*.png")
                .Select(path => LoadSample(path, letterScores))
                .OrderBy(sample => sample.Letter)
                .ToArray();

            var missing = PolishAlphabet.Letters
                .Where(letter => !samples.Any(sample => sample.Letter == letter))
                .ToArray();
            if (missing.Length > 0)
            {
                throw new InvalidOperationException($"Missing letter sample images for: {string.Join(", ", missing)}");
            }

            var digitSamples = Directory.EnumerateFiles(samplesDirectory, "*.png")
                .Select(path => LoadDigitSample(path, letterScores))
                .Where(sample => sample is not null)
                .Select(sample => sample!)
                .ToArray();

            return new LetterSampleLibrary(samples, digitSamples);
        }

        private static LetterSample LoadSample(string path, IReadOnlyDictionary<char, int> letterScores)
        {
            var name = Path.GetFileNameWithoutExtension(path).Normalize(NormalizationForm.FormC);
            if (name.Length != 1 || !PolishAlphabet.IsPolishLetter(name[0]))
            {
                throw new InvalidOperationException($"Letter sample file name must be one Polish letter: {path}");
            }

            var letter = PolishAlphabet.NormalizeLetter(name[0]);
            if (!letterScores.ContainsKey(letter))
            {
                throw new InvalidOperationException($"No configured score exists for letter sample '{letter}'.");
            }

            using var image = Image.Load<Rgba32>(path);
            var bounds = Inset(new Rectangle(0, 0, image.Width, image.Height), 0.035);
            var shapeMask = ExtractShapeMask(image, bounds)
                ?? throw new InvalidOperationException($"Could not extract letter mask from sample: {path}");
            var tileMask = ExtractLetterMask(image, bounds)
                ?? throw new InvalidOperationException($"Could not extract tile mask from sample: {path}");
            return new LetterSample(letter, shapeMask, tileMask);
        }

        private static DigitSample? LoadDigitSample(string path, IReadOnlyDictionary<char, int> letterScores)
        {
            var name = Path.GetFileNameWithoutExtension(path).Normalize(NormalizationForm.FormC);
            if (name.Length != 1 || !PolishAlphabet.IsPolishLetter(name[0]))
            {
                return null;
            }

            var letter = PolishAlphabet.NormalizeLetter(name[0]);
            if (!letterScores.TryGetValue(letter, out var score))
            {
                return null;
            }

            using var image = Image.Load<Rgba32>(path);
            var bounds = GetScoreBounds(Inset(new Rectangle(0, 0, image.Width, image.Height), 0.035));
            var mask = ExtractScoreMask(image, bounds);
            return mask is null ? null : new DigitSample(score, mask);
        }
    }
}

public sealed record LetterRecognitionResult(char? Letter, float Confidence);
