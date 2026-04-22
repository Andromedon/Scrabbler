namespace Scrabbler.App.ImageAnalysis;

public interface IBoardImageReader
{
    Task<BoardReadResult> ReadAsync(string imagePath);
}
