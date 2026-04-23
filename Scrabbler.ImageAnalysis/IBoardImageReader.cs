namespace Scrabbler.ImageAnalysis;

public interface IBoardImageReader
{
    Task<BoardReadResult> ReadAsync(string imagePath);
}
