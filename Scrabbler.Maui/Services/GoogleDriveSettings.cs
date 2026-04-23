namespace Scrabbler.Maui.Services;

public sealed record GoogleDriveSettings(string FolderId, string ClientId, string? ClientSecret, string RedirectUri);
