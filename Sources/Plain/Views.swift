//  Plain for Mac — MIT licensed. See LICENSE.
//
//  The three surfaces: a sheet, a document, a deck. Each shows what the engine says is there and hands changes
//  back as edits, which are only written when you save.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// ---------- a spreadsheet ----------

struct SheetView: View {
    @EnvironmentObject var model: PlainModel
    @State private var editing: String?
    @State private var typed = ""
    @State private var selection = Selection()
    @State private var offered: String?

    private var cells: [String: Engine.Screen.Cell] {
        Dictionary(uniqueKeysWithValues: (model.screen?.cells ?? []).map { ($0.reference, $0) })
    }

    /// Far enough to show what is there, with room to type past the end of it.
    private var lastRow: Int { max((model.screen?.cells.map(\.row).max() ?? 0) + 12, 30) }
    private var lastColumn: Int { max((model.screen?.cells.map(\.column).max() ?? 0) + 4, 12) }

    var body: some View {
        grid
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handle(press) }
            .onChange(of: selection) { _, now in model.summarise(now) }
            .onAppear { model.summarise(selection) }
    }

    /// Moving about with the keyboard, which is most of using a spreadsheet.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard editing == nil else { return .ignored }
        let jumping = press.modifiers.contains(.command) || press.modifiers.contains(.control)
        let extending = press.modifiers.contains(.shift)

        func go(_ dx: Int, _ dy: Int) -> KeyPress.Result {
            var column = selection.column, row = selection.row
            if jumping {
                // To the far end of the run of filled cells, or across a gap to the next thing there is.
                (column, row) = jump(from: (column, row), dx: dx, dy: dy)
            } else {
                column = max(1, column + dx)
                row = max(1, row + dy)
            }
            selection.move(to: column, row: row, extending: extending)
            return .handled
        }

        switch press.key {
        case .upArrow: return go(0, -1)
        case .downArrow: return go(0, 1)
        case .leftArrow: return go(-1, 0)
        case .rightArrow: return go(1, 0)
        case .home: selection.move(to: 1, row: 1, extending: extending); return .handled
        case .end:
            let sheet = model.opened?.shape.sheets?.first { $0.name == model.sheet }
            selection.move(to: max(1, sheet?.lastColumn ?? 1), row: max(1, sheet?.lastRow ?? 1), extending: extending)
            return .handled
        case .tab: return go(press.modifiers.contains(.shift) ? -1 : 1, 0)
        case .return:
            begin(at: selection.column, selection.row, with: nil)
            return .handled
        case .delete, .deleteForward:
            model.change(Edit(what: .cell(sheet: model.sheet ?? "", reference: selection.reference, value: "")))
            model.showTyped(reference: selection.reference, value: "")
            return .handled
        default:
            // Typing a character starts editing with it, the way a spreadsheet does.
            let typed = press.characters
            guard !typed.isEmpty, !jumping, typed.first!.isLetter || typed.first!.isNumber
                    || "=+-.'\"".contains(typed.first!) else { return .ignored }
            begin(at: selection.column, selection.row, with: typed)
            return .handled
        }
    }

    /// Where Ctrl with an arrow lands: the end of the run of filled cells, or across a gap to the next one.
    private func jump(from: (Int, Int), dx: Int, dy: Int) -> (Int, Int) {
        let filled = Set((model.screen?.cells ?? []).map { "\($0.column),\($0.row)" })
        func has(_ c: Int, _ r: Int) -> Bool { filled.contains("\(c),\(r)") }

        var (column, row) = from
        let startedFilled = has(column, row)
        var lastFilled = (column, row)

        for _ in 0..<500 {
            let (nc, nr) = (column + dx, row + dy)
            if nc < 1 || nr < 1 { break }
            let next = has(nc, nr)
            (column, row) = (nc, nr)
            if startedFilled {
                if !next { (column, row) = lastFilled; break }
                lastFilled = (column, row)
            } else if next { break }
        }
        return (column, row)
    }

    private func begin(at column: Int, _ row: Int, with seed: String?) {
        let reference = "\(Reference.name(column))\(row)"
        let cell = cells[reference]
        typed = seed ?? cell?.formula.map { "=" + $0 } ?? cell?.raw ?? ""
        offered = nil
        editing = reference
    }

    private var grid: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    Text("").frame(width: 46)
                    ForEach(1...lastColumn, id: \.self) { column in
                        Text(Reference.name(column))
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: width(column), height: 22)
                            .background(Color.secondary.opacity(0.06))
                            .border(Color.secondary.opacity(0.15), width: 0.5)
                    }
                }
                ForEach(1...lastRow, id: \.self) { row in
                    GridRow {
                        Text("\(row)")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 46, height: 22)
                            .background(Color.secondary.opacity(0.06))
                            .border(Color.secondary.opacity(0.15), width: 0.5)
                        ForEach(1...lastColumn, id: \.self) { column in
                            cell(column, row)
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private func width(_ column: Int) -> CGFloat {
        let chars = model.screen?.widths.first { $0.column == column }?.characters ?? 8.43
        return max(46, min(320, CGFloat(chars) * 7 + 10))
    }

    @ViewBuilder
    private func cell(_ column: Int, _ row: Int) -> some View {
        let reference = "\(Reference.name(column))\(row)"
        let cell = cells[reference]
        let isNumber = cell?.kind == "number" || cell?.kind == "formula"

        if editing == reference {
            TextField("", text: $typed, onCommit: { commit(reference) })
                .textFieldStyle(.plain)
                .padding(.horizontal, 4)
                .frame(width: width(column), height: 22)
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.accentColor, width: 1.5)
                .onChange(of: typed) { _, now in
                    // Offer what is already in the column. It is shown beside the cell rather than put into it,
                    // so carrying on typing never has to fight something that was not asked for.
                    offered = model.suggest(column: column, row: row, typed: now)
                }
                .overlay(alignment: .trailing) {
                    if let offered, offered.count > typed.count {
                        Text(offered.dropFirst(typed.count))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                            .allowsHitTesting(false)
                    }
                }
        } else {
            Text(cell?.show ?? "")
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(width: width(column), height: 22, alignment: isNumber ? .trailing : .leading)
                .padding(.horizontal, 4)
                .background(selection.contains(column, row)
                            ? Color.accentColor.opacity(selection.isOne ? 0.16 : 0.10) : Color.clear)
                .border(selection.column == column && selection.row == row
                        ? Color.accentColor : Color.secondary.opacity(0.15),
                        width: selection.column == column && selection.row == row ? 1.5 : 0.5)
                .contentShape(Rectangle())
                .onTapGesture { selection.move(to: column, row: row, extending: false) }
                .onTapGesture(count: 2) {
                    // What is being edited is what the file holds, not what is shown: a formula, or the number
                    // before it was formatted. Editing what is shown would turn 25,000 into words.
                    selection.move(to: column, row: row, extending: false)
                    typed = cell?.formula.map { "=" + $0 } ?? cell?.raw ?? ""
                    editing = reference
                }
                .contextMenu {
                    SheetMenu(selection: $selection, column: column, row: row)
                        .environmentObject(model)
                }
                .help(helpFor(column, row, cell))
        }
    }

    /// What to say about a cell when the pointer rests on it: its formula, and what it will accept.
    private func helpFor(_ column: Int, _ row: Int, _ cell: Engine.Screen.Cell?) -> String {
        var said: [String] = []
        if let formula = cell?.formula { said.append("= " + formula) }
        if let rule = model.ruleAt(column: column, row: row) {
            said.append(rule.allowed.isEmpty
                        ? "This cell takes \(rule.kind)."
                        : "This cell takes one of: " + rule.allowed.joined(separator: ", "))
            if !rule.says.isEmpty { said.append(rule.says) }
        }
        return said.joined(separator: "\n")
    }

    private func commit(_ reference: String) {
        // Enter takes the offer when there is one, the way a spreadsheet does.
        let value = (offered.map { $0.count > typed.count } ?? false) ? offered! : typed
        offered = nil
        model.change(Edit(what: .cell(sheet: model.sheet ?? "", reference: reference, value: value)))
        editing = nil
        // Show it straight away. The file itself is not touched until Save.
        model.showTyped(reference: reference, value: value)
    }
}

enum Reference {
    /// 1 is A, 27 is AA, the way a spreadsheet counts.
    static func name(_ column: Int) -> String {
        var n = column, out = ""
        while n > 0 {
            let r = (n - 1) % 26
            out = String(UnicodeScalar(UInt8(65 + r))) + out
            n = (n - 1) / 26
        }
        return out
    }
}

// ---------- a document ----------

struct DocumentView: View {
    @EnvironmentObject var model: PlainModel
    @State private var texts: [Int: String] = [:]
    @State private var linking: Int?
    @FocusState private var focused: Int?

    /// Runs of text, and the tables between them. A table's cells arrive as blocks that know which table, row and
    /// column they are in; laying them out in a line would turn a table into a list of its cells, which is what
    /// this used to do.
    private enum Piece: Identifiable {
        case block(Engine.Document.Block)
        case table(number: Int, rows: [[Engine.Document.Block]])

        var id: String {
            switch self {
            case let .block(b): return "b\(b.index)"
            case let .table(number, _): return "t\(number)"
            }
        }
    }

    private var pieces: [Piece] {
        var out: [Piece] = []
        var table: (number: Int, rows: [Int: [Engine.Document.Block]])?

        func flush() {
            guard let t = table else { return }
            out.append(.table(number: t.number, rows: t.rows.keys.sorted().map { t.rows[$0]! }))
            table = nil
        }

        for block in model.document?.blocks ?? [] {
            if block.table >= 0 {
                if table?.number != block.table { flush(); table = (block.table, [:]) }
                table!.rows[block.row, default: []].append(block)
            } else {
                flush()
                out.append(.block(block))
            }
        }
        flush()
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(pieces) { piece in
                    switch piece {
                    case let .block(block):
                        field(block)
                    case let .table(_, rows):
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                GridRow {
                                    ForEach(row, id: \.index) { field($0) }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: Binding(get: { linking != nil }, set: { if !$0 { linking = nil } })) {
            linkAsker
        }
        .onAppear {
            // A document with nothing in it is a document somebody is about to type into, so put the caret there
            // rather than making them find the one place it goes.
            let blocks = model.document?.blocks ?? []
            if blocks.count == 1, blocks[0].text.isEmpty { focused = 0 }
        }
    }

    /// A new paragraph, and the caret in it.
    private func addParagraph(after index: Int) {
        model.perform("paragraph", ["how": "add", "at": index])
        texts = [:]
        // The engine has renumbered everything; the new one is the next along.
        focused = index + 1
    }

    /// How tall a line of this kind is, so an empty one still occupies the space it will need.
    private func lineHeight(for kind: String) -> CGFloat {
        switch kind {
        case "Heading1": return 28
        case "Heading2": return 22
        case "Heading3": return 20
        default: return 19
        }
    }

    @ViewBuilder
    private func field(_ block: Engine.Document.Block) -> some View {
        // An empty paragraph in a plain text field has no size and no background, so there is nothing on screen
        // to aim at: a new document looked like a blank page with nothing to click. It gets a line's height and
        // the full width, so every paragraph is somewhere you can put the caret whether or not it has words yet.
        TextField(block.index == 0 ? "Type here" : "", text: Binding(
            get: { texts[block.index] ?? block.text },
            set: { value in
                // SwiftUI writes the binding back when the field takes focus, so without this a document said it
                // had an unsaved change the moment it was opened.
                guard value != (texts[block.index] ?? block.text) else { return }
                texts[block.index] = value
                model.change(Edit(what: .block(index: block.index, text: value)))
            }
        ), axis: .vertical)
        .textFieldStyle(.plain)
        .focused($focused, equals: block.index)
        .frame(minHeight: lineHeight(for: block.kind), alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focused = block.index }
        .font(font(for: block.kind))
        .padding(.leading, block.kind == "ListItem" ? 22 : 0)
        .padding(.top, block.kind.hasPrefix("Heading") ? 12 : 0)
        .help(block.lossless ? "" : "This paragraph has formatting inside it that retyping would flatten.")
        .onSubmit {
            // Return makes a new paragraph after this one, the way a word processor does. It writes the file,
            // because the numbering of every paragraph after it changes and carrying on with the old numbering
            // is how a tool ends up editing the wrong one.
            addParagraph(after: block.index)
        }
        .contextMenu {
            Button("Add a paragraph below") { addParagraph(after: block.index) }
            Button("Take this paragraph out") {
                model.perform("paragraph", ["how": "remove", "at": block.index])
                texts = [:]
            }
            Divider()
            Button("Put a link on this paragraph…") { linking = block.index }
            Button("Take the link off") { model.perform("link", ["how": "off", "block": block.index]) }
            Divider()
            Button("Add a row below, in its table") {
                model.perform("tablerow", ["how": "add", "table": block.table, "row": block.row])
            }
            .disabled(block.table < 0)
            Button("Take this table row out") {
                model.perform("tablerow", ["how": "remove", "table": block.table, "row": block.row])
            }
            .disabled(block.table < 0)
        }
    }

    /// Asking where a link should go. Only ordinary web and mail addresses; the engine refuses anything else.
    @ViewBuilder
    var linkAsker: some View {
        if let block = linking {
            LinkAsk(block: block, close: { linking = nil }).environmentObject(model)
        }
    }

    private func font(for kind: String) -> Font {
        switch kind {
        case "Heading1": return .system(size: 21, weight: .semibold)
        case "Heading2": return .system(size: 16, weight: .semibold)
        case "Heading3": return .system(size: 14, weight: .semibold)
        default: return .system(size: 13.5)
        }
    }
}

// ---------- a presentation ----------

struct DeckView: View {
    @EnvironmentObject var model: PlainModel
    @State private var notes: [Int: String] = [:]

    var body: some View {
        HSplitView {
            List(model.deck?.slides ?? [], id: \.number, selection: $model.shownSlide) { slide in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slide \(slide.number)").font(.caption).foregroundStyle(.secondary)
                    Text(slide.title.isEmpty ? "(no title)" : slide.title).lineLimit(1)
                }
                .tag(slide.number)
            }
            .frame(width: 220)

            if let slide = model.deck?.slides.first(where: { $0.number == model.shownSlide }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(slide.title).font(.system(size: 22, weight: .semibold))
                        ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }

                        Divider().padding(.top, 12)
                        Text("SPEAKER NOTES").font(.caption).bold().foregroundStyle(.secondary)
                        Text("These travel with the deck. Nobody sees them on the slide.")
                            .font(.caption).foregroundStyle(.secondary)

                        TextField("", text: Binding(
                            get: { notes[slide.number] ?? slide.notes },
                            set: { value in
                                notes[slide.number] = value
                                model.change(Edit(what: .notes(slide: slide.number, text: value)))
                            }
                        ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...10)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// ---------- opening and making files ----------

enum Files {
    enum Kind { case spreadsheet, document, presentation

        var suffix: String {
            switch self {
            case .spreadsheet: return "xlsx"
            case .document: return "docx"
            case .presentation: return "pptx"
            }
        }
        var called: String {
            switch self {
            case .spreadsheet: return "Spreadsheet"
            case .document: return "Document"
            case .presentation: return "Presentation"
            }
        }
    }

    static let opens: [UTType] = [
        UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xlsm"),
        UTType(filenameExtension: "docx"), UTType(filenameExtension: "docm"),
        UTType(filenameExtension: "pptx"), UTType(filenameExtension: "pptm"),
    ].compactMap { $0 }

    @MainActor
    static func open(into model: PlainModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = opens
        panel.allowsMultipleSelection = false
        panel.message = "Open a Word, Excel or PowerPoint file"
        if panel.runModal() == .OK, let url = panel.url { model.open(url.path) }
    }

    /// Save a sheet as comma separated values, the raw numbers rather than how they are shown.
    @MainActor
    static func csv(_ model: PlainModel) {
        guard let path = model.path else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ((path as NSString).lastPathComponent as NSString)
            .deletingPathExtension + ".csv"
        if let csv = UTType(filenameExtension: "csv") { panel.allowedContentTypes = [csv] }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            struct Wrote: Decodable { let csv: String }
            let made: Wrote = try Engine.ask("csv", ["path": path, "sheet": model.sheet ?? ""])
            try made.csv.write(to: url, atomically: true, encoding: .utf8)
            model.said = "Wrote \(url.lastPathComponent). Numbers as they are stored, not as they are shown."
        } catch {
            model.failed = error.localizedDescription
        }
    }

    /// Put a picture into a document. Nothing is scaled or re-encoded.
    @MainActor
    static func picture(_ model: PlainModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .bmp]
        panel.message = "Which picture?"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform("picture", ["from": url.path, "cm": 8])
    }

    /// Save the file as a PDF. What Plain shows, not a facsimile of Word's pages, and it says so.
    @MainActor
    static func pdf(_ model: PlainModel) {
        guard let path = model.path else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ((path as NSString).lastPathComponent as NSString)
            .deletingPathExtension + ".pdf"
        if let pdf = UTType(filenameExtension: "pdf") { panel.allowedContentTypes = [pdf] }
        panel.message = "This is the file as Plain shows it, not as Word would lay it out."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform("pdf", ["to": url.path], needsSaveFirst: true)
    }

    /// Save a copy somewhere else, leaving the original where it is.
    @MainActor
    static func saveCopy(_ model: PlainModel) {
        guard let path = model.path else { return }
        let panel = NSSavePanel()
        let name = (path as NSString).lastPathComponent
        panel.nameFieldStringValue = "Copy of " + name
        if let type = UTType(filenameExtension: (name as NSString).pathExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if model.dirty { model.save() }
            try FileManager.default.removeItem(at: url)
        } catch { /* nothing there to remove, which is the usual case */ }
        do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: url)
            model.said = "A copy is at \(url.path). The original is untouched."
        } catch {
            model.failed = error.localizedDescription
        }
    }

    /// A new file is written to disk before anything is typed into it, so there is nothing to lose if the Mac stops.
    @MainActor
    static func new(_ kind: Kind, into model: PlainModel) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Untitled.\(kind.suffix)"
        panel.message = "New \(kind.called.lowercased())"
        if let type = UTType(filenameExtension: kind.suffix) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            _ = try Engine.make(url.path)
            model.open(url.path)
            model.said = "Made \(url.lastPathComponent). It is on disk already, so there is nothing to lose."
        } catch {
            model.failed = error.localizedDescription
        }
    }
}


/// Where a link should go. Plain writes only what it would open itself.
private struct LinkAsk: View {
    @EnvironmentObject var model: PlainModel
    let block: Int
    let close: () -> Void
    @State private var address = "https://"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Put a link on this paragraph").font(.title3).bold()
            Text("Only ordinary web and mail addresses. Plain will not write into a document a link it would "
                 + "refuse to open itself.")
                .font(.callout).foregroundStyle(.secondary)

            TextField("https://", text: $address).textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button("Put it on") {
                    model.perform("link", ["block": block, "address": address])
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(address.count < 8)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
