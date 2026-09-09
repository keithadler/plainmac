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

    private var cells: [String: Engine.Screen.Cell] {
        Dictionary(uniqueKeysWithValues: (model.screen?.cells ?? []).map { ($0.reference, $0) })
    }

    /// Far enough to show what is there, with room to type past the end of it.
    private var lastRow: Int { max((model.screen?.cells.map(\.row).max() ?? 0) + 12, 30) }
    private var lastColumn: Int { max((model.screen?.cells.map(\.column).max() ?? 0) + 4, 12) }

    var body: some View {
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
        } else {
            Text(cell?.show ?? "")
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(width: width(column), height: 22, alignment: isNumber ? .trailing : .leading)
                .padding(.horizontal, 4)
                .border(Color.secondary.opacity(0.15), width: 0.5)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    // What is being edited is what the file holds, not what is shown: a formula, or the number
                    // before it was formatted. Editing what is shown would turn 25,000 into words.
                    typed = cell?.formula ?? cell?.raw ?? ""
                    editing = reference
                }
                .help(cell?.formula.map { "= \($0)" } ?? "")
        }
    }

    private func commit(_ reference: String) {
        model.change(Edit(what: .cell(sheet: model.sheet ?? "", reference: reference, value: typed)))
        editing = nil
        // Show it straight away. The file itself is not touched until Save.
        model.showTyped(reference: reference, value: typed)
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
    }

    @ViewBuilder
    private func field(_ block: Engine.Document.Block) -> some View {
        TextField("", text: Binding(
            get: { texts[block.index] ?? block.text },
            set: { value in
                texts[block.index] = value
                model.change(Edit(what: .block(index: block.index, text: value)))
            }
        ), axis: .vertical)
        .textFieldStyle(.plain)
        .font(font(for: block.kind))
        .padding(.leading, block.kind == "ListItem" ? 22 : 0)
        .padding(.top, block.kind.hasPrefix("Heading") ? 12 : 0)
        .help(block.lossless ? "" : "This paragraph has formatting inside it that retyping would flatten.")
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
    @State private var chosen = 1
    @State private var notes: [Int: String] = [:]

    var body: some View {
        HSplitView {
            List(model.deck?.slides ?? [], id: \.number, selection: $chosen) { slide in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slide \(slide.number)").font(.caption).foregroundStyle(.secondary)
                    Text(slide.title.isEmpty ? "(no title)" : slide.title).lineLimit(1)
                }
                .tag(slide.number)
            }
            .frame(width: 220)

            if let slide = model.deck?.slides.first(where: { $0.number == chosen }) {
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
