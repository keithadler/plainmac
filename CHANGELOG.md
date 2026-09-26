# Changelog

## 1.0.1 (25 September 2026)

Built and tested on macOS 27.

- Built with the macOS 27 SDK and Xcode 27, so it draws the current macOS look.
- A window is always named for the file in it. On macOS 27 a file opened while Plain was already running could
  leave its window called "Plain". Then the window could not be found by name: the file showed as "Plain" in the
  Window menu, and asking for it again opened a second, blank window instead of bringing the first one forward.
  The window's title is now set directly, and a window that has to close itself closes even when macOS 27
  ignores the first request.
- Word, Excel and PowerPoint samples were opened, read and saved on macOS 27 and came back byte for byte. The
  app compiles with no warnings, and all 68 of its checks and the engine's 1,008 pass.
- `build-app.sh` works with the Swift that comes with Xcode 27: it asks where the built program is instead of
  assuming the old folder, and it records the SDK the app was built with.

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
