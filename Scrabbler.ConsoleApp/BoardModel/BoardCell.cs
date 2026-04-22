namespace Scrabbler.App.BoardModel;

public sealed record BoardCell(int Row, int Column, char? Letter, bool IsBlank, BonusType Bonus)
{
    public bool IsEmpty => Letter is null;

    public BoardCell WithLetter(char? letter, bool isBlank = false)
    {
        return this with { Letter = letter, IsBlank = letter is not null && isBlank };
    }
}
