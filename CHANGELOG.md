# Changelog

## 1.0.1 (25 September 2026)

Built and tested on macOS 27.

- Windows are named for the file in them again. On macOS 27 every window stayed "Plain" after its file opened,
  and three things that find windows by name stopped working: a blank window left over after opening a file from
  the Finder was not closed, opening a file that was already open added a second blank window instead of just
  bringing the first one forward, and the Window menu listed every window as "Plain". The window's title is now
  set directly, and a window that has to close itself closes even when macOS 27 ignores the first request.
- `build-app.sh` builds again with the Swift that comes with Xcode 27, which puts the built program in a
  different folder. The script now asks where it is instead of assuming.
- Word, Excel and PowerPoint samples were opened, read and saved on macOS 27 and came back byte for byte. The
  app compiles with no warnings, and all 68 of its checks and the engine's 1,008 pass.

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
