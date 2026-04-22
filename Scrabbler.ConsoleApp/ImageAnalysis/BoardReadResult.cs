using Scrabbler.App.BoardModel;

namespace Scrabbler.App.ImageAnalysis;

public sealed record CellRead(int Row, int Column, char? Letter, float Confidence, bool IsOccupied = false);

public sealed record BoardReadResult(Board Board, IReadOnlyList<CellRead> Cells);
