# Scrabbler

.NET 10 console helper for finding the best next Polish Scrabble-like move from a 15x15 board screenshot.

## Run

1. Put one board screenshot in `Scrabbler.ConsoleApp/Input/`. Supported extensions are `.jpg`, `.jpeg`, `.png`, `.webp`, and `.bmp`.
2. Copy or download a full UTF-8 Polish dictionary to `Scrabbler.ConsoleApp/Data/dictionary-pl.txt`, one word per line.
3. Run:

```bash
dotnet run --project Scrabbler.ConsoleApp/Scrabbler.App.csproj
```

The app picks the newest image in the fixed input directory, detects likely occupied tile cells, lets you enter/correct letters in the console, asks for rack letters, and prints the highest-scoring legal moves. The first dictionary run builds a processed cache; later runs reuse it when the source file has not changed.

`Scrabbler.ConsoleApp/Data/dictionary-pl.txt` is intentionally ignored by git because full Polish dictionaries can be large. `Scrabbler.Assets/Data/dictionary-pl.sample.txt` is tracked as a tiny template.

## Project Structure

- `Scrabbler.Domain` contains reusable board, rack, alphabet, direction, and bonus-square models.
- `Scrabbler.Solver` contains reusable move-finding and scoring logic.
- `Scrabbler.Data` contains reusable dictionary and JSON layout/value loaders.
- `Scrabbler.ImageAnalysis` contains reusable screenshot-to-board OCR contracts and ImageSharp implementation.
- `Scrabbler.Input` contains reusable input/file type and Google Drive abstractions.
- `Scrabbler.Assets` contains shared JSON configuration data and OCR letter samples.
- `Scrabbler.ConsoleApp` is the current executable host. It keeps console UI, configuration, desktop Google Drive/local input implementations, and local ignored files.

## Google Drive Input

The app can also download the newest board screenshot from a Google Drive folder.

1. In Google Cloud Console, create an OAuth client ID with application type `Desktop app`.
2. Download the client secret JSON and place it at `Scrabbler.ConsoleApp/Secrets/google-drive-client-secret.json`.
3. Open your Drive folder in the browser and copy the folder ID from the URL. In a URL like `https://drive.google.com/drive/folders/abc123`, the folder ID is `abc123`.
4. Configure `Scrabbler.ConsoleApp/appsettings.json`:

```json
{
  "InputSource": "GoogleDrive",
  "GoogleDriveFolderId": "your-folder-id",
  "GoogleDriveCredentialsPath": "Secrets/google-drive-client-secret.json",
  "GoogleDriveTokenDirectory": "Secrets/google-token",
  "GoogleDriveDownloadDirectory": "Input/Downloaded"
}
```

The first Google Drive run opens a browser for Google consent. Later runs reuse the cached token from `Scrabbler.ConsoleApp/Secrets/google-token`. Credentials, tokens, local screenshots, downloaded Drive images, and the full dictionary are ignored by git.

## Corrections

Coordinates use columns `A` through `O` and rows `1` through `15`.

Examples:

```text
H8=Ł
H8=?
H8=.
H8=Ł?, I8=A, J8=.
```

`?` on the rack means a blank tile. In corrections, `Ł?` means the board tile shows `Ł` but scores zero.

## Notes

- Bonus squares are loaded from `Scrabbler.Assets/Data/bonus-layout.json`; bonus labels are not read from the photo.
- The center start square is row 8, column H. It is not a score bonus in this layout, but the solver still requires the first move to cover it.
- Letter values are loaded from `Scrabbler.Assets/Data/letter-values-pl.json`.
- Screenshots are read with a managed ImageSharp reader, so no native OpenCV or Tesseract setup is required.
- Local input screenshots in `Scrabbler.ConsoleApp/Input/` are ignored by git; only `.gitkeep` is tracked.
