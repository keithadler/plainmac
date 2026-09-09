# Changelog

## 1.0.0 — 9 September 2026

First public release.

Opens Word, Excel and PowerPoint files, edits the things people actually change, and writes back every part it
did not edit as the exact bytes it found.

- Spreadsheets: cells, text and formulas across every sheet; sort, de-duplicate and split columns; insert and
  delete rows and columns with every formula in the workbook rewritten to still mean what it meant; colour,
  alignment, wrapping, borders, number formats; column widths and row heights; frozen rows and columns; sheets
  added, renamed, moved and removed; what the selection adds up to, on the status line.
- Documents: headings, paragraphs, lists and tables; page headers and footers; links; comments and tracked
  changes; pictures, with descriptions for people who cannot see them.
- Presentations: the text on every slide, speaker notes, and slides added, removed and reordered.
- All three: undo and redo, find and replace, search a folder, compare two versions, save as PDF with page setup
  or as CSV, document properties, and a list of what a file would carry with it if you sent it.
- Several documents open at once, one window each.
- A command line twin, `plainmac`, with the same forty-two operations for scripts.
- A daily check with GitHub for a newer version, which you can turn off. It is the only network request the app
  makes.

The part that understands the file format is the same engine as Plain for Windows, compiled ahead of time into a
native library. Its own thousand checks run from inside the app: `plainmac selftest`.
