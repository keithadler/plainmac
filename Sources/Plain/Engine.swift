import Foundation
import CPlainEngine

/// The engine, as the app sees it.
///
/// Plain for Mac does not have its own idea of what a `.docx` is. Everything about the file format is answered by
/// the same engine Plain for Windows uses, compiled to native code and linked in. That is deliberate: the promise
/// the program rests on, that a file you save without changing comes back byte for byte, is not reimplemented here
/// and hoped to match. It is the identical code, guarded by the identical checks, and `Engine.selfTest()` runs them
/// from inside this app.
///
/// Everything crosses as JSON. It is duller and slower than passing structures over the boundary, and the expensive
/// part is reading the file rather than describing it, so dull is the right trade.
enum Engine {

    /// What went wrong, in a sentence someone can act on, which is what the engine sends back.
    struct Failure: LocalizedError {
        let said: String
        var errorDescription: String? { said }
    }

    // ---------- what the app asks ----------

    static func version() throws -> Version { try ask(plain_version()) }

    /// Make a new empty file of the kind the name asks for.
    static func make(_ path: String) throws -> Made {
        try ask(path.withCString { plain_new($0) })
    }

    static func open(_ path: String) throws -> Opened {
        try ask(path.withCString { plain_open($0) })
    }

    static func cells(path: String, sheet: String?, top: Int, left: Int, rows: Int, columns: Int) throws -> Screen {
        var request: [String: Any] = ["path": path, "top": top, "left": left, "rows": rows, "columns": columns]
        if let sheet { request["sheet"] = sheet }
        return try json(request) { plain_cells($0) }
    }

    static func blocks(_ path: String) throws -> Document {
        try ask(path.withCString { plain_blocks($0) })
    }

    static func slides(_ path: String) throws -> Deck {
        try ask(path.withCString { plain_slides($0) })
    }

    /// Everything changed since the file was opened, applied and written in one go.
    static func save(path: String, edits: [[String: Any]]) throws -> Saved {
        try json(["path": path, "edits": edits]) { plain_save($0) }
    }

    /// The claim the whole program rests on, checked on the file in front of you.
    static func roundTrip(_ path: String) throws -> RoundTrip {
        try ask(path.withCString { plain_roundtrip($0) })
    }

    static func hidden(_ path: String) throws -> Hidden {
        try ask(path.withCString { plain_hidden($0) })
    }

    static func preserved(_ path: String) throws -> Preserved {
        try ask(path.withCString { plain_preserved($0) })
    }

    /// Where the checks' fixture files are, when this is a clone rather than an installed app.
    ///
    /// Without this the suites that need a real .docx skip, and a skip prints like a pass: the engine reports
    /// half its checks and says nothing is wrong. Plain for Windows was caught by exactly this.
    /// True when the fixture files were found, so the caller can say which suite was actually run.
    private(set) static var hasFixtures = false

    static func pointAtFixtures() {
        if let set = ProcessInfo.processInfo.environment["PLAIN_FIXTURES"] {
            hasFixtures = FileManager.default.fileExists(atPath: set + "/sheet.xlsx")
            return
        }

        var here = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0..<8 {
            here.deleteLastPathComponent()
            let candidate = here.appendingPathComponent("tests/fixtures")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("sheet.xlsx").path) {
                setenv("PLAIN_FIXTURES", candidate.path, 1)
                hasFixtures = true
                return
            }
        }
    }

    /// Everything else the engine can do, behind one door.
    ///
    /// The operations all take a bag of named values and give back either what they found or what they did, so
    /// there is one call here rather than thirty. What each one wants is in the engine's Do.cs.
    @discardableResult
    static func run(_ op: String, _ named: [String: Any] = [:]) throws -> Done {
        var request = named
        request["op"] = op
        return try json(request) { plain_do($0) }
    }

    /// The same, when what comes back is a list rather than a report of what changed.
    static func ask<T: Decodable>(_ op: String, _ named: [String: Any] = [:]) throws -> T {
        var request = named
        request["op"] = op
        return try json(request) { plain_do($0) }
    }

    /// What an operation did, said in words the window can show.
    struct Done: Decodable {
        let said: String?
        let parts: Saved.Parts?
    }

    struct Traced: Decodable {
        let cell: String
        let reads: [Touch]
        let readBy: [Touch]
        struct Touch: Decodable { let where_: String; let what: String
            enum CodingKeys: String, CodingKey { case where_ = "where", what }
        }
    }

    struct Rules: Decodable {
        let rules: [Rule]
        struct Rule: Decodable {
            let sheet: String, kind: String, says: String, allowed: [String]
            let where_: String
            enum CodingKeys: String, CodingKey { case sheet, kind, says, allowed, where_ = "where" }
        }
    }

    struct LinkList: Decodable {
        let links: [Link]
        struct Link: Decodable { let text: String; let target: String; let safe: Bool }
    }

    struct CommentList: Decodable {
        let comments: [Comment]
        struct Comment: Decodable {
            let index: Int, who: String, when: String, text: String
            let where_: String
            enum CodingKeys: String, CodingKey { case index, who, when, text, where_ = "where" }
        }
    }

    struct ChangeList: Decodable {
        let changes: [Change]
        struct Change: Decodable { let index: Int; let added: Bool; let who: String; let when: String; let text: String }
    }

    struct Tally: Decodable { let words: Int; let characters: Int; let paragraphs: Int }

    struct Hits: Decodable {
        let hits: [Hit]
        struct Hit: Decodable { let sheet: String; let reference: String; let show: String }
    }

    /// The engine's own checks, run from inside the app.
    static func selfTest() throws -> SelfTest { try ask(plain_selftest()) }

    // ---------- what comes back ----------

    struct Version: Decodable { let version: String; let engine: String }

    struct Made: Decodable { let path: String; let kind: String }

    struct Opened: Decodable {
        let path: String
        let shape: Shape
        let parts: Parts

        struct Shape: Decodable {
            let kind: String
            let sheets: [Sheet]?
            let blocks: Int?
            let slides: Int?
        }
        struct Sheet: Decodable {
            let name: String
            let hidden: Bool
            let lastColumn: Int
            let lastRow: Int
            let frozenRows: Int
            let frozenColumns: Int
        }
        struct Parts: Decodable { let read: Int; let edited: Int; let kept: Int }
    }

    struct Screen: Decodable {
        init(sheet: String, cells: [Cell], widths: [Width], joined: [Join]) {
            self.sheet = sheet; self.cells = cells; self.widths = widths; self.joined = joined
        }

        let sheet: String
        let cells: [Cell]
        let widths: [Width]
        let joined: [Join]

        struct Cell: Decodable {
            init(reference: String, column: Int, row: Int, show: String, raw: String, formula: String?, kind: String) {
                self.reference = reference; self.column = column; self.row = row
                self.show = show; self.raw = raw; self.formula = formula; self.kind = kind
            }
            let reference: String
            let column: Int
            let row: Int
            let show: String
            let raw: String
            let formula: String?
            let kind: String
        }
        struct Width: Decodable { let column: Int; let characters: Double }
        struct Join: Decodable { let fromColumn: Int; let fromRow: Int; let toColumn: Int; let toRow: Int }
    }

    struct Document: Decodable {
        let blocks: [Block]
        struct Block: Decodable {
            let index: Int
            let kind: String
            let text: String
            let lossless: Bool
            let table: Int
            let row: Int
            let column: Int
        }
    }

    struct Deck: Decodable {
        let slides: [Slide]
        struct Slide: Decodable { let number: Int; let title: String; let lines: [String]; let notes: String }
    }

    struct Saved: Decodable {
        let changed: Int
        let parts: Parts
        struct Parts: Decodable { let read: Int; let rewritten: Int; let kept: Int }
    }

    struct RoundTrip: Decodable { let identical: Bool; let bytes: Int }

    struct Hidden: Decodable {
        let found: [Finding]
        struct Finding: Decodable { let kind: String; let what: String; let count: Int; let removable: Bool }
    }

    struct Preserved: Decodable {
        let rows: [Row]
        let bookkeeping: Bookkeeping
        struct Row: Decodable { let what: String; let count: Int; let bytes: Int; let name: String? }
        struct Bookkeeping: Decodable { let count: Int; let bytes: Int }
    }

    struct SelfTest: Decodable { let failed: Int; let summary: String; let output: String }

    // ---------- the plumbing ----------

    /// Hand a request over as JSON and take the answer back, freeing what the engine allocated either way.
    private static func json<T: Decodable>(_ request: [String: Any],
                                           _ call: (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: request)
        let text = String(decoding: data, as: UTF8.self)
        return try ask(text.withCString { call($0) })
    }

    /// Read the engine's answer, free it, and turn an "error" in it into something thrown.
    private static func ask<T: Decodable>(_ pointer: UnsafeMutablePointer<CChar>?) throws -> T {
        guard let pointer else { throw Failure(said: "The engine did not answer.") }
        defer { plain_free(pointer) }

        let text = String(cString: pointer)
        let data = Data(text.utf8)

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let said = object["error"] as? String {
            throw Failure(said: said)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Failure(said: "The engine said something this version does not understand.") }
    }
}
