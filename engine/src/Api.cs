using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Plain.Core;

namespace Plain.Engine;

/// <summary>
/// The doorway between the Mac app and the engine.
///
/// Everything crosses as UTF-8 JSON: a handful of functions that take a string and return a string, with no object
/// lifetimes to get wrong across the boundary and nothing that has to be freed in the right order. It is slower
/// than passing structures about and it does not matter, because the expensive part is reading and writing the
/// file, not describing what happened.
///
/// Every call returns JSON with either what was asked for or an "error" the app can show. Nothing throws across
/// the boundary: an exception escaping into Swift would take the whole app down with no message worth reading.
///
/// The caller owns nothing. Each returned string is allocated here and freed by calling plain_free, which the app
/// does immediately after copying the bytes into a Swift String.
/// </summary>
public static class Api
{
    /// <summary>What the engine is, so the app can prove the two halves match.</summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_version")]
    public static nint Version() => Guard(() => Json.Write(j => j
        .Put("version", Build.Version)
        .Put("engine", "Plain.Core")));

    /// <summary>
    /// Make a new empty file. Which kind comes from the name, so there is one place that decides it. The file
    /// exists on disk before anything is typed into it, so there is nothing to lose if the Mac stops.
    /// </summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_new")]
    public static nint New(nint pathUtf8) => Guard(() =>
    {
        var path = Text(pathUtf8);
        var made = PlainFile.Create(path);
        return Json.Write(j => j.Put("path", path).Put("kind", Kind(made.Kind)));
    });

    /// <summary>Open a file and describe it: what kind, what is in it, what is being kept untouched.</summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_open")]
    public static nint Open(nint pathUtf8) => Guard(() =>
    {
        var path = Text(pathUtf8);
        var file = PlainFile.Open(path);
        var counts = file.Counts();

        return Json.Write(j =>
        {
            j.Put("path", path);
            j.Object("shape", shape =>
            {
                shape.Put("kind", Kind(file.Kind));
                if (file.Workbook is { } book)
                    shape.Array("sheets", book.Sheets, (w, s) => w
                        .Put("name", s.Name)
                        .Put("hidden", s.Hidden)
                        .Put("lastColumn", s.Extent.Column)
                        .Put("lastRow", s.Extent.Row)
                        .Put("frozenRows", s.FrozenRows)
                        .Put("frozenColumns", s.FrozenColumns));
                if (file.Document is { } document) shape.Put("blocks", document.Blocks().Count());
                if (file.Deck is { } deck) shape.Put("slides", deck.Slides.Count);
            });
            j.Object("parts", p => p
                .Put("read", counts.Total)
                .Put("edited", counts.Edited)
                .Put("kept", counts.Kept));
        });
    });

    /// <summary>One screen of a sheet, as the app draws it: reference, what to show, and what it really is.</summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_cells")]
    public static nint Cells(nint requestUtf8) => Guard(() =>
    {
        using var request = JsonDocument.Parse(Text(requestUtf8));
        var ask = request.RootElement;
        var file = PlainFile.Open(ask.GetProperty("path").GetString()!);
        var sheet = SheetOf(file, ask);

        int top = Number(ask, "top", 1), left = Number(ask, "left", 1);
        int rows = Math.Clamp(Number(ask, "rows", 60), 1, 500);
        int columns = Math.Clamp(Number(ask, "columns", 30), 1, 200);

        var cells = new List<(CellRef At, Cell What)>();
        for (int r = top; r < top + rows; r++)
            for (int c = left; c < left + columns; c++)
            {
                var at = new CellRef(c, r);
                var cell = sheet.Read(at);
                if (cell.Kind != CellKind.Empty) cells.Add((at, cell));
            }

        var widths = Enumerable.Range(left, columns).Select(c => (Column: c, Chars: sheet.WidthChars(c))).ToList();

        return Json.Write(j =>
        {
            j.Put("sheet", sheet.Name);
            j.Array("cells", cells, (w, x) => w
                .Put("reference", x.At.ToString())
                .Put("column", x.At.Column)
                .Put("row", x.At.Row)
                .Put("show", x.What.Display)
                .Put("raw", x.What.Raw)
                .Put("formula", x.What.Formula)
                .Put("kind", x.What.Kind.ToString().ToLowerInvariant()));
            j.Array("widths", widths, (w, x) => w.Put("column", x.Column).Put("characters", x.Chars));
            j.Array("joined", sheet.Merges, (w, m) => w
                .Put("fromColumn", m.From.Column).Put("fromRow", m.From.Row)
                .Put("toColumn", m.To.Column).Put("toRow", m.To.Row));
        });
    });

    /// <summary>The text of a document, block by block, with what each block is.</summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_blocks")]
    public static nint Blocks(nint pathUtf8) => Guard(() =>
    {
        var file = PlainFile.Open(Text(pathUtf8));
        if (file.Document is not { } document) throw new OpcPackage.PackageException("That is not a document.");

        var blocks = document.Blocks().ToList();
        return Json.Write(j => j.Array("blocks", blocks, (w, b) => w
            .Put("index", b.Index)
            .Put("kind", b.Kind.ToString())
            .Put("text", b.Text)
            // A block Plain cannot put back exactly as it found it says so, so the app can warn before it is typed in.
            .Put("lossless", b.Lossless)
            .Put("table", b.Table)
            .Put("row", b.Row)
            .Put("column", b.Column)));
    });

    /// <summary>The text on every slide, and the notes that travel with it.</summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_slides")]
    public static nint Slides(nint pathUtf8) => Guard(() =>
    {
        var file = PlainFile.Open(Text(pathUtf8));
        if (file.Deck is not { } deck) throw new OpcPackage.PackageException("That is not a presentation.");

        var notes = Described.Notes(file).ToDictionary(n => n.Slide, n => n.Text);
        var slides = deck.Slides.Select(s => (
            Number: s.Number,
            Title: s.Title(),
            Lines: s.Texts().SelectMany(t => t.Lines).ToList(),
            Notes: notes.TryGetValue(s.Number, out var said) ? said : "")).ToList();

        return Json.Write(j => j.Array("slides", slides, (w, s) =>
        {
            w.Put("number", s.Number).Put("title", s.Title).Put("notes", s.Notes);
            w.Strings("lines", s.Lines);
        }));
    });

    /// <summary>
    /// Make changes and save. Everything the app has changed since the file was opened arrives together, so the
    /// file is read once, changed once and written once, and a save is one action that either happens or does not.
    /// </summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_save")]
    public static nint Save(nint requestUtf8) => Guard(() =>
    {
        using var request = JsonDocument.Parse(Text(requestUtf8));
        var ask = request.RootElement;
        var path = ask.GetProperty("path").GetString()!;
        var file = PlainFile.Open(path);

        int changed = 0;
        if (ask.TryGetProperty("edits", out var edits))
            foreach (var edit in edits.EnumerateArray())
            {
                switch (edit.GetProperty("what").GetString())
                {
                    case "cell":
                    {
                        var sheet = SheetOf(file, edit);
                        sheet.Set(CellRef.Parse(edit.GetProperty("reference").GetString()!),
                                  edit.GetProperty("value").GetString() ?? "");
                        changed++;
                        break;
                    }
                    case "block":
                    {
                        if (file.Document is not { } document) break;
                        document.SetText(edit.GetProperty("index").GetInt32(),
                                         edit.GetProperty("text").GetString() ?? "");
                        changed++;
                        break;
                    }
                    case "notes":
                    {
                        var slide = edit.GetProperty("slide").GetInt32();
                        var note = Described.Notes(file).FirstOrDefault(n => n.Slide == slide);
                        if (note is null) break;
                        Described.WriteNotes(file.Package, note.Part, edit.GetProperty("text").GetString() ?? "");
                        changed++;
                        break;
                    }
                }
            }

        file.Save();
        var counts = file.Counts();
        return Json.Write(j =>
        {
            j.Put("changed", changed);
            j.Object("parts", p => p
                .Put("read", counts.Total)
                .Put("rewritten", counts.Edited)
                .Put("kept", counts.Kept));
        });
    });

    /// <summary>Prove that opening and saving changes nothing. The claim the whole program rests on.</summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_roundtrip")]
    public static nint RoundTrip(nint pathUtf8) => Guard(() =>
    {
        var path = Text(pathUtf8);
        var before = File.ReadAllBytes(path);
        var file = PlainFile.Open(path);
        file.Flush();
        var after = file.Package.ToBytes();
        return Json.Write(j => j
            .Put("identical", before.AsSpan().SequenceEqual(after))
            .Put("bytes", before.LongLength));
    });

    /// <summary>Everything the file carries that is not on the page, so it can be shown before it is sent.</summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_hidden")]
    public static nint Hidden(nint pathUtf8) => Guard(() =>
    {
        var file = PlainFile.Open(Text(pathUtf8));
        var found = Core.Hidden.Find(file).ToList();
        return Json.Write(j => j.Array("found", found, (w, f) => w
            .Put("kind", f.Kind)
            .Put("what", f.What)
            .Put("count", f.Count)
            .Put("removable", f.CanRemove)));
    });

    /// <summary>The parts Plain keeps but cannot draw, grouped the way the rail shows them.</summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_preserved")]
    public static nint Preserved(nint pathUtf8) => Guard(() =>
    {
        var file = PlainFile.Open(Text(pathUtf8));
        var notes = Core.Preserved.Describe(file.Package, file.ShownParts());
        var rows = Core.Preserved.Summarise(notes).ToList();
        var (kept, bytes) = Core.Preserved.Bookkeeping(notes);

        return Json.Write(j =>
        {
            j.Array("rows", rows, (w, r) => w
                .Put("what", r.What)
                .Put("count", r.Count)
                .Put("bytes", r.Bytes)
                .Put("name", r.Name));
            j.Object("bookkeeping", b => b.Put("count", kept).Put("bytes", bytes));
        });
    });

    /// <summary>The engine's own checks, so the app can prove the engine inside it is sound.</summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_selftest")]
    public static nint SelfTest() => Guard(() =>
    {
        var writer = new StringWriter();
        int failed = Core.Tests.SelfTest.Run(writer);
        var output = writer.ToString();
        var lines = output.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        return Json.Write(j => j
            .Put("failed", failed)
            .Put("summary", lines.Length > 0 ? lines[^1].Trim() : "")
            .Put("output", output));
    });

    /// <summary>Give back a string the engine allocated.</summary>
    [UnmanagedCallersOnly(EntryPoint = "plain_free")]
    public static void Free(nint p) => Marshal.FreeHGlobal(p);

    // ---------- the plumbing ----------

    private static string Text(nint p) => Marshal.PtrToStringUTF8(p) ?? "";

    private static string Kind(FileKind kind) => kind switch
    {
        FileKind.Spreadsheet => "spreadsheet",
        FileKind.Document => "document",
        FileKind.Presentation => "presentation",
        _ => "unknown",
    };

    private static int Number(JsonElement o, string name, int fallback) =>
        o.TryGetProperty(name, out var v) && v.TryGetInt32(out var n) ? n : fallback;

    private static Sheet SheetOf(PlainFile file, JsonElement ask)
    {
        var book = file.Workbook ?? throw new OpcPackage.PackageException("That is not a spreadsheet.");
        if (ask.TryGetProperty("sheet", out var named) && named.GetString() is { Length: > 0 } name)
            return book.Sheets.FirstOrDefault(s => s.Name == name)
                ?? throw new OpcPackage.PackageException($"There is no sheet called {name}.");
        return book.Sheets[0];
    }

    /// <summary>
    /// Run something and give back JSON. Nothing is allowed to throw into Swift: a failure is an answer with an
    /// "error" in it, which the app shows as a sentence, exactly as the Windows app does.
    /// </summary>
    private static nint Guard(Func<string> what)
    {
        try { return Give(what()); }
        catch (OpcPackage.PackageException ex) { return Give(Error(ex.Message)); }
        catch (FileNotFoundException) { return Give(Error("That file is not there any more.")); }
        catch (DirectoryNotFoundException) { return Give(Error("That folder is not there any more.")); }
        catch (UnauthorizedAccessException) { return Give(Error("macOS would not let Plain read that file.")); }
        catch (Exception ex) { return Give(Error(ex.Message.Length > 0 ? ex.Message : ex.GetType().Name)); }
    }

    private static string Error(string said) => Json.Write(j => j.Put("error", said));

    private static nint Give(string json)
    {
        var bytes = Encoding.UTF8.GetBytes(json);
        var buffer = Marshal.AllocHGlobal(bytes.Length + 1);
        Marshal.Copy(bytes, 0, buffer, bytes.Length);
        Marshal.WriteByte(buffer, bytes.Length, 0);
        return buffer;
    }
}

/// <summary>Kept beside the code it describes so the app and the engine cannot disagree about the version.</summary>
internal static class Build
{
    public const string Version = "1.0.0";
}
