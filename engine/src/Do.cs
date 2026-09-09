using System.Text.Json;
using Plain.Core;

namespace Plain.Engine;

/// <summary>
/// Everything the app can ask the engine to do, behind one door.
///
/// There are about thirty of these. Giving each one its own exported function, its own line in a C header and its
/// own binding on the Swift side would be three places to keep in step for every one, and the boundary is already
/// JSON in and JSON out. So there is one entry point and a switch: adding an operation is one case here and one
/// method on the Swift side, and the header never changes.
///
/// Every operation says what it did in words, because that is what the window puts in its status line, and every
/// refusal says why. The engine refuses a great deal on purpose: sorting rows a formula reads, splitting a column
/// over the top of another one, taking out a sheet something still points at. Those refusals are the product.
/// </summary>
internal static class Do
{
    public static string Run(JsonElement ask)
    {
        var op = ask.GetProperty("op").GetString() ?? "";
        var path = ask.TryGetProperty("path", out var p) ? p.GetString() ?? "" : "";

        // Reading something needs no save; changing something writes once at the end. Which is which is decided
        // here rather than by each operation remembering to do it.
        return op switch
        {
            // ---------- reading ----------
            "traces" => Traces_(path, ask),
            "choices" => Choices_(path, ask),
            "links" => Links_(path),
            "comments" => Comments_(path),
            "changes" => Changes_(path),
            "properties" => Properties_(path),
            "count" => Count_(path),
            "images" => Images_(path),
            "bands" => Bands_(path),
            "described" => Described_(path),
            "search" => Search_(path, ask),
            "folder" => Folder_(ask),
            "compare" => Compare_(ask),
            "csv" => Csv_(path, ask),
            "suggest" => Suggest_(path, ask),
            "summary" => Summary_(path, ask),

            // ---------- changing a sheet ----------
            "sort" => Change(path, f => Sort_(f, ask)),
            "tidy" => Change(path, f => Tidy_(f, ask)),
            "grid" => Change(path, f => GridEdit_(f, ask)),
            "width" => Change(path, f => Width_(f, ask)),
            "height" => Change(path, f => Height_(f, ask)),
            "freeze" => Change(path, f => Freeze_(f, ask)),
            "align" => Change(path, f => Align_(f, ask)),
            "colour" => Change(path, f => Colour_(f, ask)),
            "border" => Change(path, f => Border_(f, ask)),
            "format" => Change(path, f => Format_(f, ask)),
            "weight" => Change(path, f => Weight_(f, ask)),
            "sheet" => Change(path, f => Sheet_(f, ask)),

            // ---------- changing a document or a deck ----------
            "tablerow" => Change(path, f => TableRow_(f, ask)),
            "band" => Change(path, f => Band_(f, ask)),
            "slide" => Change(path, f => Slide_(f, ask)),
            "setnotes" => Change(path, f => SetNotes_(f, ask)),
            "describe" => Change(path, f => Describe_(f, ask)),
            "link" => Change(path, f => Link_(f, ask)),
            "picture" => Change(path, f => Picture_(f, ask)),
            "settle" => Change(path, f => Settle_(f, ask)),
            "removecomments" => Change(path, f => RemoveComments_(f, ask)),

            // ---------- changing the whole file ----------
            "replace" => Change(path, f => Replace_(f, ask)),
            "setproperties" => Change(path, f => SetProperties_(f, ask)),
            "clean" => Change(path, f => Clean_(f, ask)),
            "pdf" => Pdf_(path, ask),

            _ => Json.Write(j => j.Put("error", $"The engine does not know how to \"{op}\".")),
        };
    }

    /// <summary>
    /// Do something that changes the file, then write it once. A refusal writes nothing: the file on disk is
    /// untouched unless the whole operation succeeded.
    /// </summary>
    private static string Change(string path, Func<PlainFile, string?> what)
    {
        var file = PlainFile.Open(path);
        var refused = what(file);
        if (refused is not null) return Json.Write(j => j.Put("error", refused));

        file.Save();
        var counts = file.Counts();
        return Json.Write(j =>
        {
            j.Put("said", Said);
            j.Object("parts", p => p
                .Put("read", counts.Total)
                .Put("rewritten", counts.Edited)
                .Put("kept", counts.Kept));
        });
    }

    /// <summary>What the last operation did, for the window's status line.</summary>
    [ThreadStatic] private static string? _said;
    private static string Said { get => _said ?? "Done."; set => _said = value; }

    // ---------- helpers ----------

    private static Sheet SheetOf(PlainFile file, JsonElement ask)
    {
        var book = file.Workbook ?? throw new OpcPackage.PackageException("That is not a spreadsheet.");
        if (ask.TryGetProperty("sheet", out var named) && named.GetString() is { Length: > 0 } name)
            return book.Sheets.FirstOrDefault(s => s.Name == name)
                ?? throw new OpcPackage.PackageException($"There is no sheet called {name}.");
        return book.Sheets[0];
    }

    private static string Text(JsonElement o, string name, string fallback = "") =>
        o.TryGetProperty(name, out var v) ? v.GetString() ?? fallback : fallback;

    private static int Number(JsonElement o, string name, int fallback = 0) =>
        o.TryGetProperty(name, out var v) && v.TryGetInt32(out var n) ? n : fallback;

    private static bool Yes(JsonElement o, string name, bool fallback = false) =>
        o.TryGetProperty(name, out var v) && v.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? v.GetBoolean() : fallback;

    private static (int Left, int Top, int Right, int Bottom) Block(JsonElement ask) =>
        (Number(ask, "left", 1), Number(ask, "top", 1), Number(ask, "right", 1), Number(ask, "bottom", 1));

    private static IEnumerable<CellRef> Cells(JsonElement ask)
    {
        var (left, top, right, bottom) = Block(ask);
        for (int r = Math.Min(top, bottom); r <= Math.Max(top, bottom); r++)
            for (int c = Math.Min(left, right); c <= Math.Max(left, right); c++)
                yield return new CellRef(c, r);
    }

    // ---------- reading ----------

    private static string Traces_(string path, JsonElement ask)
    {
        var file = PlainFile.Open(path);
        var book = file.Workbook ?? throw new OpcPackage.PackageException("That is not a spreadsheet.");
        var sheet = SheetOf(file, ask);
        var cell = CellRef.Parse(Text(ask, "cell", "A1"));

        var reads = Traces.Reads(book, sheet, cell).ToList();
        var readBy = Traces.ReadBy(book, sheet, cell).ToList();
        return Json.Write(j =>
        {
            j.Put("cell", cell.ToString());
            j.Array("reads", reads, (w, t) => w.Put("where", t.Where).Put("what", t.What));
            j.Array("readBy", readBy, (w, t) => w.Put("where", t.Where).Put("what", t.What));
        });
    }

    private static string Choices_(string path, JsonElement ask)
    {
        var file = PlainFile.Open(path);
        var book = file.Workbook ?? throw new OpcPackage.PackageException("That is not a spreadsheet.");
        var rules = book.Sheets.SelectMany(s => Choices.On(file.Package, s).Select(r => (Sheet: s.Name, Rule: r))).ToList();
        return Json.Write(j => j.Array("rules", rules, (w, x) =>
        {
            w.Put("sheet", x.Sheet).Put("where", x.Rule.Where).Put("kind", x.Rule.Kind).Put("says", x.Rule.Says);
            w.Strings("allowed", x.Rule.Allowed);
        }));
    }

    private static string Links_(string path)
    {
        var links = Core.Links.All(PlainFile.Open(path)).ToList();
        return Json.Write(j => j.Array("links", links, (w, l) => w
            .Put("text", l.Text).Put("target", l.Target).Put("safe", Core.Links.SafeToOpen(l.Target))));
    }

    private static string Comments_(string path)
    {
        var notes = Annotations.Comments(PlainFile.Open(path)).ToList();
        return Json.Write(j => j.Array("comments", notes, (w, n) => w
            .Put("index", n.Index).Put("who", n.Author).Put("when", n.When)
            .Put("text", n.Text).Put("where", n.Where)));
    }

    private static string Changes_(string path)
    {
        var revisions = Annotations.Revisions(PlainFile.Open(path)).ToList();
        return Json.Write(j => j.Array("changes", revisions, (w, r) => w
            .Put("index", r.Index).Put("added", r.Inserted)
            .Put("who", r.Author).Put("when", r.When).Put("text", r.Text)));
    }

    private static string Properties_(string path)
    {
        var props = PlainFile.Open(path).Properties;
        var all = props.All().ToList();
        var revealing = props.Revealing().Select(x => x.Name).ToHashSet();
        return Json.Write(j => j.Array("properties", all, (w, kv) => w
            .Put("name", kv.Name).Put("value", kv.Value).Put("names a person", revealing.Contains(kv.Name))));
    }

    private static string Count_(string path)
    {
        var tally = Counts.Of(PlainFile.Open(path));
        return Json.Write(j => j
            .Put("words", tally.Words).Put("characters", tally.Characters).Put("paragraphs", tally.Paragraphs));
    }

    private static string Images_(string path)
    {
        var pictures = Media.In(PlainFile.Open(path)).ToList();
        return Json.Write(j => j.Array("pictures", pictures, (w, x) => w
            .Put("name", x.Name).Put("kind", x.Kind).Put("bytes", x.Bytes).Put("size", x.Size)));
    }

    private static string Bands_(string path)
    {
        var bands = HeaderFooter.All(PlainFile.Open(path)).ToList();
        return Json.Write(j => j.Array("bands", bands, (w, b) => w
            .Put("part", b.Part).Put("header", b.IsHeader).Put("which", b.Which).Put("text", b.Text)));
    }

    private static string Described_(string path)
    {
        var pictures = Described.Pictures(PlainFile.Open(path)).ToList();
        return Json.Write(j => j.Array("pictures", pictures, (w, x) => w
            .Put("where", x.Where).Put("name", x.Name).Put("text", x.Text)));
    }

    private static string Search_(string path, JsonElement ask)
    {
        var file = PlainFile.Open(path);
        var term = Text(ask, "find");
        if (file.Workbook is { } book)
        {
            var hits = Core.Search.InWorkbook(book, term).ToList();
            return Json.Write(j => j.Array("hits", hits, (w, h) => w
                .Put("sheet", book.Sheets[Math.Clamp(h.Sheet, 0, book.Sheets.Count - 1)].Name)
                .Put("reference", h.Cell.ToString()).Put("show", h.Text)));
        }
        var lines = (file.Document?.PlainText() ?? "").Split('\n');
        var found = lines.Select((line, i) => (Line: line, At: i))
                         .Where(x => Core.Search.Matches(x.Line, term)).ToList();
        return Json.Write(j => j.Array("hits", found, (w, x) => w
            .Put("sheet", "").Put("reference", (x.At + 1).ToString()).Put("show", x.Line.Trim())));
    }

    private static string Folder_(JsonElement ask)
    {
        var report = Core.Folder.Search(Text(ask, "folder"), Text(ask, "find"), Yes(ask, "deep"));
        return Json.Write(j =>
        {
            j.Put("looked", report.Looked);
            j.Array("files", report.Hits.ToList(), (w, f) =>
            {
                w.Put("path", f.Path).Put("hits", f.Count);
                w.Strings("where", f.Places.Take(6).ToList());
            });
        });
    }

    private static string Compare_(JsonElement ask)
    {
        var before = PlainFile.Open(Text(ask, "before"));
        var after = PlainFile.Open(Text(ask, "after"));
        var report = Core.Compare.Between(before, after);
        return Json.Write(j =>
        {
            j.Put("same", report.Same);
            j.Put("note", report.Note);
            j.Array("parts", report.Parts.ToList(), (w, c) => w.Put("name", c.Name).Put("how", c.How));
            j.Array("text", report.Text.ToList(), (w, c) => w
                .Put("where", c.Where).Put("text", c.Text).Put("added", c.Added));
        });
    }

    private static string Csv_(string path, JsonElement ask)
    {
        var file = PlainFile.Open(path);
        var sheet = SheetOf(file, ask);
        return Json.Write(j => j.Put("csv", Core.Csv.Write(sheet, ',', Yes(ask, "formatted"))));
    }

    /// <summary>
    /// What else is in this column that starts the same way, for offering as you type. A list of clients typed
    /// slightly differently each time is the most common way a spreadsheet quietly goes wrong.
    /// </summary>
    private static string Suggest_(string path, JsonElement ask)
    {
        var file = PlainFile.Open(path);
        var sheet = SheetOf(file, ask);
        var offer = sheet.Suggest(Number(ask, "column", 1), Number(ask, "row", 1), Text(ask, "typed"));
        return Json.Write(j => j.Put("offer", offer));
    }

    /// <summary>
    /// What the selection adds up to: how many numbers, the sum, the average, the lowest and the highest. The
    /// question a spreadsheet is usually opened to answer.
    /// </summary>
    private static string Summary_(string path, JsonElement ask)
    {
        var file = PlainFile.Open(path);
        var sheet = SheetOf(file, ask);
        var (left, top, right, bottom) = Block(ask);

        long size = (long)(right - left + 1) * (bottom - top + 1);
        if (size > 200_000) return Json.Write(j => j.Put("said", ""));

        int numbers = 0, filled = 0;
        double total = 0, low = double.MaxValue, high = double.MinValue;
        for (int r = top; r <= bottom; r++)
            for (int c = left; c <= right; c++)
            {
                var cell = sheet.Read(new CellRef(c, r));
                if (cell.Kind == CellKind.Empty) continue;
                filled++;
                if (!double.TryParse(cell.Raw, System.Globalization.NumberStyles.Float,
                                     System.Globalization.CultureInfo.InvariantCulture, out var value)) continue;
                numbers++;
                total += value;
                low = Math.Min(low, value);
                high = Math.Max(high, value);
            }

        return Json.Write(j =>
        {
            j.Put("filled", filled).Put("numbers", numbers);
            if (numbers > 0)
            {
                j.Put("sum", total).Put("average", total / numbers).Put("lowest", low).Put("highest", high);
            }
        });
    }

    // ---------- changing a sheet ----------

    private static string? Sort_(PlainFile file, JsonElement ask)
    {
        var book = file.Workbook ?? throw new OpcPackage.PackageException("That is not a spreadsheet.");
        var sheet = SheetOf(file, ask);
        var (left, top, right, bottom) = Block(ask);
        var outcome = Core.Sort.Rows(book, sheet, top, bottom, left, right,
                                     Number(ask, "by", left), !Yes(ask, "descending"));
        if (outcome is Core.Sort.Refused refused) return refused.Reason;
        int moved = ((Core.Sort.Sorted)outcome).RowsMoved;
        Said = moved == 0 ? "They were already in that order."
                          : $"Sorted. {moved} row{(moved == 1 ? "" : "s")} moved.";
        return null;
    }

    private static string? Tidy_(PlainFile file, JsonElement ask)
    {
        var book = file.Workbook ?? throw new OpcPackage.PackageException("That is not a spreadsheet.");
        var sheet = SheetOf(file, ask);
        var (left, top, right, bottom) = Block(ask);
        var outcome = Text(ask, "how") == "split"
            ? Core.Tidy.SplitColumn(book, sheet, left, top, bottom, Text(ask, "on", ","))
            : Core.Tidy.RemoveDuplicates(book, sheet, top, bottom, left, right);
        if (outcome is Core.Tidy.Refused refused) return refused.Reason;
        Said = ((Core.Tidy.Done)outcome).What;
        return null;
    }

    private static string? GridEdit_(PlainFile file, JsonElement ask)
    {
        var book = file.Workbook ?? throw new OpcPackage.PackageException("That is not a spreadsheet.");
        var sheet = SheetOf(file, ask);
        var edit = Text(ask, "how") switch
        {
            "insertrow" => Core.GridEdit.InsertRow,
            "deleterow" => Core.GridEdit.DeleteRow,
            "insertcolumn" => Core.GridEdit.InsertColumn,
            "deletecolumn" => Core.GridEdit.DeleteColumn,
            _ => (Core.GridEdit?)null,
        } ?? throw new OpcPackage.PackageException("insertrow, deleterow, insertcolumn or deletecolumn.");

        int touched = book.Apply(sheet, edit, Number(ask, "at", 1));
        Said = touched == 0
            ? "Done. No formula had to change."
            : $"Done. {touched} formula{(touched == 1 ? "" : "s")} rewritten so they still mean what they meant.";
        return null;
    }

    private static string? Width_(PlainFile file, JsonElement ask)
    {
        var sheet = SheetOf(file, ask);
        int column = Number(ask, "column", 1);
        double chars = Yes(ask, "fit") ? sheet.WidestChars(column) : Number(ask, "characters", 12);
        sheet.SetWidthChars(column, chars);
        Said = $"Column {CellRef.ColumnName(column)} is now {sheet.WidthChars(column):0.#} characters wide.";
        return null;
    }

    private static string? Height_(PlainFile file, JsonElement ask)
    {
        var sheet = SheetOf(file, ask);
        int row = Number(ask, "row", 1);
        sheet.SetHeightPoints(row, Yes(ask, "auto") ? 0 : Number(ask, "points", 18));
        Said = sheet.HeightPoints(row) == 0
            ? $"Row {row} follows the sheet again."
            : $"Row {row} is now {sheet.HeightPoints(row):0.#} points tall.";
        return null;
    }

    private static string? Freeze_(PlainFile file, JsonElement ask)
    {
        var sheet = SheetOf(file, ask);
        int rows = Number(ask, "rows"), columns = Number(ask, "columns");
        sheet.SetFrozen(columns, rows);
        Said = rows == 0 && columns == 0
            ? "Nothing is held on screen; the sheet scrolls freely."
            : $"{(rows > 0 ? $"{rows} row{(rows == 1 ? "" : "s")}" : "")}"
              + $"{(rows > 0 && columns > 0 ? " and " : "")}"
              + $"{(columns > 0 ? $"{columns} column{(columns == 1 ? "" : "s")}" : "")} stay on screen.";
        return null;
    }

    private static string? Align_(PlainFile file, JsonElement ask)
    {
        var sheet = SheetOf(file, ask);
        var cells = Cells(ask).ToList();
        string? where = ask.TryGetProperty("horizontal", out var h) ? h.GetString() : null;
        bool? wrap = ask.TryGetProperty("wrap", out var w) && w.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? w.GetBoolean() : null;
        sheet.SetAlignment(cells, where, wrap);
        Said = $"{cells.Count} cell{(cells.Count == 1 ? "" : "s")} changed.";
        return null;
    }

    private static string? Colour_(PlainFile file, JsonElement ask)
    {
        var sheet = SheetOf(file, ask);
        var cells = Cells(ask).ToList();
        sheet.SetColours(cells,
            ask.TryGetProperty("fill", out var f) ? f.GetString() : null,
            ask.TryGetProperty("ink", out var i) ? i.GetString() : null);
        Said = $"{cells.Count} cell{(cells.Count == 1 ? "" : "s")} changed.";
        return null;
    }

    private static string? Border_(PlainFile file, JsonElement ask)
    {
        var sheet = SheetOf(file, ask);
        var cells = Cells(ask).ToList();
        var sides = ask.TryGetProperty("sides", out var s) && s.ValueKind == JsonValueKind.Array
            ? s.EnumerateArray().Select(x => x.GetString() ?? "").ToList()
            : new List<string> { "all" };
        sheet.SetBorder(cells, sides, Text(ask, "style", "thin"), Text(ask, "colour", "808080"));
        Said = $"{cells.Count} cell{(cells.Count == 1 ? "" : "s")} changed.";
        return null;
    }

    private static string? Format_(PlainFile file, JsonElement ask)
    {
        var sheet = SheetOf(file, ask);
        var cells = Cells(ask).ToList();
        sheet.SetFormat(cells, Text(ask, "code"));
        Said = $"{cells.Count} cell{(cells.Count == 1 ? "" : "s")} changed.";
        return null;
    }

    private static string? Weight_(PlainFile file, JsonElement ask)
    {
        var sheet = SheetOf(file, ask);
        var cells = Cells(ask).ToList();
        bool? bold = ask.TryGetProperty("bold", out var b) && b.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? b.GetBoolean() : null;
        bool? italic = ask.TryGetProperty("italic", out var i) && i.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? i.GetBoolean() : null;
        sheet.SetWeight(cells, bold, italic);
        Said = $"{cells.Count} cell{(cells.Count == 1 ? "" : "s")} changed.";
        return null;
    }

    private static string? Sheet_(PlainFile file, JsonElement ask)
    {
        var book = file.Workbook ?? throw new OpcPackage.PackageException("That is not a spreadsheet.");
        int at = Number(ask, "at", 1);
        var outcome = Text(ask, "how") switch
        {
            "add" => Sheets.Add(book, Text(ask, "name", "Sheet"), book.Sheets.Count),
            "rename" => Sheets.Rename(book, at - 1, Text(ask, "name")),
            "remove" => Sheets.Remove(book, at - 1),
            "move" => Sheets.Move(book, at, Number(ask, "to", 1)),
            _ => new Sheets.Refused("add, rename, remove or move."),
        };
        if (outcome is Sheets.Refused refused) return refused.Reason;
        Said = ((Sheets.Done)outcome).What;
        return null;
    }

    // ---------- changing a document or a deck ----------

    private static string? TableRow_(PlainFile file, JsonElement ask)
    {
        if (file.Document is not { } document) return "Tables live in a document.";
        var outcome = Text(ask, "how") == "remove"
            ? document.DeleteRow(Number(ask, "table"), Number(ask, "row"))
            : document.InsertRow(Number(ask, "table"), Number(ask, "row"));
        if (outcome is TableRows.Refused refused) return refused.Reason;
        Said = ((TableRows.Done)outcome).What;
        return null;
    }

    private static string? Band_(PlainFile file, JsonElement ask)
    {
        var bands = HeaderFooter.All(file).ToList();
        bool header = Yes(ask, "header", true);
        var band = bands.FirstOrDefault(b => b.IsHeader == header);
        if (band is null) return header ? "This file has no page header." : "This file has no page footer.";
        HeaderFooter.Write(file.Package, band.Part, Text(ask, "text"));
        Said = header ? "The page header now says that." : "The page footer now says that.";
        return null;
    }

    private static string? Slide_(PlainFile file, JsonElement ask)
    {
        if (file.Deck is null) return "That is not a presentation.";
        var outcome = Text(ask, "how") switch
        {
            "add" => Slides.Add(file.Package, Number(ask, "at")),
            "remove" => Slides.Remove(file.Package, Number(ask, "at", 1)),
            "move" => Slides.Move(file.Package, Number(ask, "at", 1), Number(ask, "to", 1)),
            _ => new Slides.Refused("add, remove or move."),
        };
        if (outcome is Slides.Refused refused) return refused.Reason;
        Said = ((Slides.Done)outcome).What;
        return null;
    }

    private static string? SetNotes_(PlainFile file, JsonElement ask)
    {
        var slide = Number(ask, "slide", 1);
        var note = Described.Notes(file).FirstOrDefault(n => n.Slide == slide);
        if (note is null) return $"Slide {slide} has no notes to write into.";
        Described.WriteNotes(file.Package, note.Part, Text(ask, "text"));
        Said = $"The notes on slide {slide} now say that.";
        return null;
    }

    private static string? Describe_(PlainFile file, JsonElement ask)
    {
        int changed = Described.DescribePictures(file, Text(ask, "where"), Text(ask, "name"), Text(ask, "text"));
        Said = $"Described {changed} picture{(changed == 1 ? "" : "s")}.";
        return null;
    }

    private static string? Link_(PlainFile file, JsonElement ask)
    {
        var outcome = Text(ask, "how") == "off"
            ? Insert.Unlink(file, Number(ask, "block"))
            : Insert.Link(file, Number(ask, "block"), Text(ask, "address"));
        if (outcome is Insert.Refused refused) return refused.Reason;
        Said = ((Insert.Done)outcome).What;
        return null;
    }

    private static string? Picture_(PlainFile file, JsonElement ask)
    {
        var outcome = Insert.Picture(file, Text(ask, "from"), Number(ask, "cm", 8));
        if (outcome is Insert.Refused refused) return refused.Reason;
        Said = ((Insert.Done)outcome).What;
        return null;
    }

    private static string? Settle_(PlainFile file, JsonElement ask)
    {
        bool accept = Yes(ask, "accept", true);
        int n = accept ? Annotations.AcceptRevisions(file) : Annotations.RejectRevisions(file);
        Said = $"{(accept ? "Accepted" : "Turned down")} {n} tracked change{(n == 1 ? "" : "s")}.";
        return null;
    }

    private static string? RemoveComments_(PlainFile file, JsonElement ask)
    {
        int n = Annotations.RemoveComments(file);
        Said = $"Took out {n} comment{(n == 1 ? "" : "s")}.";
        return null;
    }

    // ---------- changing the whole file ----------

    private static string? Replace_(PlainFile file, JsonElement ask)
    {
        var options = new Core.Replace.Options(Yes(ask, "matchCase"), Yes(ask, "wholeWord"));
        var find = Text(ask, "find");
        var with = Text(ask, "with");

        if (file.Workbook is { } book)
        {
            Told(Core.Replace.InWorkbook(book, find, with, options), find);
            return null;
        }
        if (file.Document is { } document)
        {
            Told(Core.Replace.InDocument(document, find, with, options), find);
            return null;
        }
        return "Find and replace works on spreadsheets and documents.";

        void Told(Core.Replace.Result result, string looked)
        {
            Said = result.Occurrences == 0
                ? $"\"{looked}\" is not in this file."
                : $"Changed {result.Occurrences} occurrence{(result.Occurrences == 1 ? "" : "s")} "
                  + $"in {result.Cells} place{(result.Cells == 1 ? "" : "s")}.";
        }
    }

    private static string? SetProperties_(PlainFile file, JsonElement ask)
    {
        var props = file.Properties;
        if (Yes(ask, "strip"))
        {
            int n = props.Strip();
            Said = $"Took out {n} propert{(n == 1 ? "y" : "ies")} that name a person.";
            return null;
        }
        var name = Text(ask, "name");
        if (name.Length == 0) return "Say which property to set.";
        props.Set(name, Text(ask, "value"));
        Said = $"{name} is now \"{Text(ask, "value")}\".";
        return null;
    }

    private static string? Clean_(PlainFile file, JsonElement ask)
    {
        var kinds = ask.TryGetProperty("kinds", out var k) && k.ValueKind == JsonValueKind.Array
            ? k.EnumerateArray().Select(x => x.GetString() ?? "").ToList()
            : new List<string>();
        var done = Core.Hidden.Remove(file, kinds).ToList();
        Said = done.Count == 0 ? "Nothing was taken out." : string.Join(" ", done);
        return null;
    }

    private static string Pdf_(string path, JsonElement ask)
    {
        var file = PlainFile.Open(path);
        var setup = new PageSetup
        {
            Paper = Text(ask, "paper", "A4"),
            Landscape = Yes(ask, "landscape"),
            Header = Text(ask, "header"),
            Footer = Text(ask, "footer", "Page {page} of {pages}"),
        }.Sensible();
        var result = PdfExport.Build(file, System.IO.Path.GetFileNameWithoutExtension(path), setup);
        var to = Text(ask, "to");
        if (to.Length == 0) return Json.Write(j => j.Put("error", "Say where the PDF should go."));
        File.WriteAllBytes(to, result.Bytes);
        return Json.Write(j => j.Put("said", $"Wrote {result.Pages} page{(result.Pages == 1 ? "" : "s")} to {to}.")
                                .Put("pages", result.Pages));
    }
}
