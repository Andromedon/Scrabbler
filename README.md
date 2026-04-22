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

`Scrabbler.ConsoleApp/Data/dictionary-pl.txt` is intentionally ignored by git because full Polish dictionaries can be large. `Scrabbler.ConsoleApp/Data/dictionary-pl.sample.txt` is tracked as a tiny template.

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

- Bonus squares are loaded from `Scrabbler.ConsoleApp/Data/bonus-layout.json`; bonus labels are not read from the photo.
- The center start square is row 8, column H. It is not a score bonus in this layout, but the solver still requires the first move to cover it.
- Letter values are loaded from `Scrabbler.ConsoleApp/Data/letter-values-pl.json`.
- Screenshots are read with a managed ImageSharp reader, so no native OpenCV or Tesseract setup is required.
- Local input screenshots in `Scrabbler.ConsoleApp/Input/` are ignored by git; only `.gitkeep` is tracked.
