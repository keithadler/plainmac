**[Download Plain-for-Mac-1.0.0.dmg](https://github.com/keithadler/plainmac/releases/download/v1.0.0/Plain-for-Mac-1.0.0.dmg)** — macOS 14 or later, Apple Silicon and Intel.

Open the DMG, drag the app to Applications, open it. The first time, macOS says the app is from an unidentified developer: right-click the app, choose Open, then Open again. That is once. It needs no permissions.

---

Plain opens Word, Excel and PowerPoint files, edits the things people actually change, and writes back every part it did not edit as the exact bytes it found.

Open a file, save it without changing anything, and you get the same file back byte for byte. Check it on your own documents:

```
plainmac roundtrip ~/Documents/*.docx ~/Documents/*.xlsx
```

**What it does.** Cells and formulas across every sheet, with rows and columns inserted and deleted and every formula rewritten so it still means what it meant. Sorting, de-duplicating and splitting columns. Colour, borders, number formats, column widths, frozen rows. Headings, paragraphs, lists and tables, page headers and footers, links, comments and tracked changes. The text on every slide and the speaker notes. Several documents open at once, one window each. Undo and redo, find and replace, a folder searched, two versions compared, PDF with page setup, CSV, and a panel that tells you what a file would carry with it if you sent it.

**What it keeps but does not show.** Charts, pivot tables, macros, SmartArt, embedded objects, slide layouts, masters, themes, footnotes. All of it is in the saved file unchanged, and named in plain words down the side of the window.

**The same engine as [Plain for Windows](https://github.com/keithadler/plainwin).** The part that understands the file format is the same code on both, compiled ahead of time into a native library. Nothing of .NET ships in the app and there is no runtime to install. A bug found on one is fixed for both. The engine's own thousand checks run from inside the app: `plainmac selftest`.

**Honest limits.** No page layout the way Word does it. No shapes, charts or pictures drawn in place. No macro engine — a macro survives the round trip, but Plain will not run it. Never opened in Microsoft Office; checked against the file format, against LibreOffice as an independent reader, and against the byte-for-byte round trip.

Free and MIT licensed. No account, no cloud, no telemetry, no permissions to grant. The only network request is a daily check with GitHub for a newer version, which you can turn off in Settings.

SHA-256 of the DMG: `21854758298b1b30436994dc6467f5d3d298a06e2f4efd42ac385b4845c3cb92`
