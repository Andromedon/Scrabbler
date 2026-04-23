using Scrabbler.Domain.BoardModel;

namespace Scrabbler.Solver;

public sealed record Move(
    string Word,
    int Row,
    int Column,
    Direction Direction,
    IReadOnlyList<PlacedTile> PlacedTiles,
    int Score,
    IReadOnlyList<string> CrossWords);
