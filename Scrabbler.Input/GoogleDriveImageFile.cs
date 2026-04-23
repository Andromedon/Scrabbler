namespace Scrabbler.Input;

public sealed record GoogleDriveImageFile(
    string Id,
    string Name,
    DateTimeOffset ModifiedTime,
    string? MimeType = null);
