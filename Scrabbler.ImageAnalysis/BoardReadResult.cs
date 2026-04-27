using Scrabbler.Domain.BoardModel;

namespace Scrabbler.ImageAnalysis;

public sealed record LetterCandidateRead(char Letter, double Score);

public sealed record ScoreDigitRead(int? Digit, double Confidence, bool IsReliable);

public sealed record CellVisualRead(double OrangeRatio, double DarkRatio, double WhiteRatio);

public sealed record CellRead(
    int Row,
    int Column,
    char? Letter,
    float Confidence,
    bool IsOccupied = false,
    IReadOnlyList<LetterCandidateRead>? Candidates = null,
    ScoreDigitRead? ScoreDigit = null,
    CellVisualRead? Visual = null);

public sealed record BoardRepair(int Row, int Column, char? From, char To, string Reason);

public sealed record BoardReadResult(
    Board Board,
    IReadOnlyList<CellRead> Cells,
    IReadOnlyList<BoardRepair>? Repairs = null);
