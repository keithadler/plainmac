//  Plain for Mac — MIT licensed. See LICENSE.
//
//  The one object the windows watch. It holds the file that is open, what has been changed and not yet saved,
//  and what the engine says about it.
//
//  Nothing here knows what a .docx is. Every question about the file goes to the engine, which is the same code
//  Plain for Windows runs, so there is one answer to "what is in this file" rather than two that have to be kept
//  in step.

import Foundation
import Combine

enum Prefs {
    static var defaults = UserDefaults.standard

    /// Ask GitHub once a day whether there is a newer version. The only network request the app makes.
    static var checkForUpdates: Bool {
        get { defaults.object(forKey: "checkForUpdates") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "checkForUpdates") }
    }

    /// Keep a copy of unsaved work, so a Mac that stops does not take the afternoon with it.
    static var keepUnsaved: Bool {
        get { defaults.object(forKey: "keepUnsaved") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "keepUnsaved") }
    }

    /// Show the rail listing what the file carries that Plain will not draw.
    static var showPreserved: Bool {
        get { defaults.object(forKey: "showPreserved") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showPreserved") }
    }

    static var recent: [String] {
        get { defaults.stringArray(forKey: "recent") ?? [] }
        set { defaults.set(Array(newValue.prefix(10)), forKey: "recent") }
    }
}

/// One change the person made that is not yet in the file.
struct Edit: Equatable {
    enum What: Equatable {
        case cell(sheet: String, reference: String, value: String)
        case block(index: Int, text: String)
        case notes(slide: Int, text: String)
    }
    let what: What

    /// The shape the engine expects. Everything crosses as plain JSON values.
    var asJSON: [String: Any] {
        switch what {
        case let .cell(sheet, reference, value):
            return ["what": "cell", "sheet": sheet, "reference": reference, "value": value]
        case let .block(index, text):
            return ["what": "block", "index": index, "text": text]
        case let .notes(slide, text):
            return ["what": "notes", "slide": slide, "text": text]
        }
    }

    /// Two edits to the same place are one edit; the last one said is what is meant.
    var place: String {
        switch what {
        case let .cell(sheet, reference, _): return "cell:\(sheet):\(reference)"
        case let .block(index, _): return "block:\(index)"
        case let .notes(slide, _): return "notes:\(slide)"
        }
    }
}

@MainActor
final class PlainModel: ObservableObject {
    static let shared = PlainModel()

    @Published var path: String?
    @Published var opened: Engine.Opened?
    @Published var screen: Engine.Screen?
    @Published var document: Engine.Document?
    @Published var deck: Engine.Deck?
    @Published var preserved: Engine.Preserved?

    @Published var sheet: String?
    @Published var said = ""
    @Published var failed: String?

    /// What has been changed and not yet written. Kept in order, one per place.
    @Published private(set) var edits: [Edit] = []

    var dirty: Bool { !edits.isEmpty }
    var name: String { path.map { ($0 as NSString).lastPathComponent } ?? "Plain" }

    // ---------- opening ----------

    func open(_ path: String) {
        do {
            let opened = try Engine.open(path)
            self.path = path
            self.opened = opened
            self.edits = []
            self.failed = nil
            self.sheet = opened.shape.sheets?.first?.name

            switch opened.shape.kind {
            case "spreadsheet": try loadScreen()
            case "document": document = try Engine.blocks(path); screen = nil; deck = nil
            case "presentation": deck = try Engine.slides(path); screen = nil; document = nil
            default: break
            }

            preserved = try? Engine.preserved(path)
            var recent = Prefs.recent.filter { $0 != path }
            recent.insert(path, at: 0)
            Prefs.recent = recent

            let parts = opened.parts
            said = "\(parts.read) parts read, \(parts.kept) kept byte for byte."
        } catch {
            failed = error.localizedDescription
            said = ""
        }
    }

    func show(sheet name: String) {
        sheet = name
        try? loadScreen()
    }

    private func loadScreen() throws {
        guard let path else { return }
        screen = try Engine.cells(path: path, sheet: sheet, top: 1, left: 1, rows: 200, columns: 40)
        document = nil
        deck = nil
    }

    // ---------- changing ----------

    /// Put what was just typed on screen without touching the file. Saving is what touches the file.
    func showTyped(reference: String, value: String) {
        guard let screen else { return }
        var cells = screen.cells.filter { $0.reference != reference }
        if !value.isEmpty {
            let numeric = Double(value) != nil
            let column = cells.first { $0.reference == reference }?.column ?? 0
            let row = cells.first { $0.reference == reference }?.row ?? 0
            cells.append(Engine.Screen.Cell(
                reference: reference, column: column, row: row,
                show: value, raw: value,
                formula: value.hasPrefix("=") ? String(value.dropFirst()) : nil,
                kind: value.hasPrefix("=") ? "formula" : (numeric ? "number" : "text")))
        }
        self.screen = Engine.Screen(sheet: screen.sheet, cells: cells,
                                    widths: screen.widths, joined: screen.joined)
    }

    func change(_ edit: Edit) {
        edits.removeAll { $0.place == edit.place }
        edits.append(edit)
    }

    /// Write everything at once, so a save either happens or does not.
    func save() {
        guard let path else { return }
        do {
            let saved = try Engine.save(path: path, edits: edits.map(\.asJSON))
            edits = []
            said = "Saved. \(saved.parts.rewritten) of \(saved.parts.read) parts rewritten, "
                 + "\(saved.parts.kept) kept byte for byte."
            open(path)
        } catch {
            failed = error.localizedDescription
        }
    }

    /// The promise, checked on the file in front of you.
    func checkPromise() {
        guard let path else { return }
        do {
            let trip = try Engine.roundTrip(path)
            said = trip.identical
                ? "Opened and saved without changing anything: the same file, byte for byte."
                : "This file does not come back byte for byte. That is a bug; please report it."
        } catch {
            failed = error.localizedDescription
        }
    }
}
