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
    static func pointAtFixtures() {
        guard ProcessInfo.processInfo.environment["PLAIN_FIXTURES"] == nil else { return }

        var here = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0..<8 {
            here.deleteLastPathComponent()
            let candidate = here.appendingPathComponent("tests/fixtures")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("sheet.xlsx").path) {
                setenv("PLAIN_FIXTURES", candidate.path, 1)
                return
            }
        }
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
        let sheet: String
        let cells: [Cell]
        let widths: [Width]
        let joined: [Join]

        struct Cell: Decodable {
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
