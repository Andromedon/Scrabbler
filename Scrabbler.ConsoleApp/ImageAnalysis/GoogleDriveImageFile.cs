namespace Scrabbler.App.ImageAnalysis;

public sealed record GoogleDriveImageFile(
    string Id,
    string Name,
    DateTimeOffset ModifiedTime,
    string? MimeType = null);
