//  Plain for Mac — MIT licensed. See LICENSE.
//
//  The command-line face. Exit codes: 0 fine, 1 something to look at, 2 problem, 64 usage error.

import Foundation

enum CLI {
    static let usage = """
    plainmac — opens Word, Excel and PowerPoint files and never damages what it does not understand

    USAGE
      plainmac info <file> [--json]              what it is, and what Plain keeps untouched
      plainmac text <file> [--json]              the text, as plain text
      plainmac cells <file> [--sheet <name>] [--json]    every filled cell
      plainmac slides <file> [--json]            the text on each slide, and the notes with it
      plainmac set <file> <ref> <value> [--sheet <name>]  change one cell, then save
      plainmac hidden <file> [--json]            what this file would carry with it if you sent it
      plainmac preserved <file> [--json]         the parts Plain keeps but will not draw
      plainmac roundtrip <file>...               prove that a save changes nothing

      plainmac screenshots <dir> [--announce]    render windows and promo cards from demo data
      plainmac selftest [--filter S] [--list] [--json]
      plainmac help | version

    The promise: open a file, save it without changing anything, and you get the same file back byte for byte.
    `roundtrip` is that claim, checked on your own documents. Everything about the file format is answered by the
    same engine Plain for Windows uses, so both programs agree by construction rather than by intention.

    Nothing here reaches the network. Set PLAINMAC_HOME to keep settings somewhere else (tests do).
    """

    static var version: String {
        if Bundle.main.bundleIdentifier == "com.keithadler.plainmac",
           let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app", let b = Bundle(url: url), b.bundleIdentifier == "com.keithadler.plainmac",
               let v = b.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
            url = url.deletingLastPathComponent()
        }
        return "dev"
    }

    @MainActor
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if let h = env["PLAINMAC_HOME"], !h.isEmpty {
            Prefs.defaults = UserDefaults(suiteName: "com.keithadler.plainmac.test")!
        }
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first, !cmd.hasPrefix("-psn") else { return }
        exit(run(cmd, Array(args.dropFirst())))
    }

    static func flag(_ n: String, _ a: [String]) -> Bool { a.contains(n) }
    static func value(_ n: String, _ a: [String]) -> String? {
        guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    /// The words the verb was given, with every switch and every switch's value taken out.
    ///
    /// Plain for Windows had a bug here that put a switch's value into a cell, turning a number into words. The
    /// switches that take a value are named so that cannot happen again.
    static let takesAValue = ["--filter", "--sheet"]
    static func positional(_ a: [String]) -> [String] {
        var out: [String] = []
        var skip = false
        for x in a {
            if skip { skip = false; continue }
            if takesAValue.contains(x) { skip = true; continue }
            if x.hasPrefix("--") { continue }
            out.append(x)
        }
        return out
    }

    static var quiet = false
    static func out(_ s: String) { if !quiet { print(s) } }
    static func err(_ s: String) { if !quiet { fputs(s + "\n", stderr) } }

    static func json(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o),
              let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys])
        else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    @MainActor
    static func run(_ cmd: String, _ args: [String]) -> Int32 {
        let rest = positional(args)
        let wantsJSON = flag("--json", args)

        switch cmd {
        case "help", "--help", "-h":
            out(usage)
            return 0

        case "version", "--version":
            let engine = (try? Engine.version())?.version ?? "unknown"
            out("Plain for Mac \(version)  (engine \(engine))")
            out("Built by Keith Adler. Free, MIT. github.com/keithadler/plainmac")
            return 0

        case "info":
            guard let path = rest.first else { err("info <file>"); return 64 }
            do {
                let o = try Engine.open(path)
                if wantsJSON {
                    out(json(["path": o.path, "kind": o.shape.kind,
                              "parts": ["read": o.parts.read, "edited": o.parts.edited, "kept": o.parts.kept]]))
                } else {
                    out("\((path as NSString).lastPathComponent)  (\(o.shape.kind))")
                    if let sheets = o.shape.sheets {
                        for s in sheets { out("  sheet    \(s.name), used to column \(s.lastColumn) row \(s.lastRow)") }
                    }
                    if let blocks = o.shape.blocks { out("  blocks   \(blocks)") }
                    if let slides = o.shape.slides { out("  slides   \(slides)") }
                    out("  parts    \(o.parts.read) in the file: \(o.parts.kept) kept byte for byte")
                }
                return 0
            } catch { err(error.localizedDescription); return 2 }

        case "text":
            guard let path = rest.first else { err("text <file>"); return 64 }
            do {
                let d = try Engine.blocks(path)
                if wantsJSON { out(json(["blocks": d.blocks.map { ["index": $0.index, "kind": $0.kind, "text": $0.text] }])) }
                else { for b in d.blocks where !b.text.isEmpty { out(b.text) } }
                return 0
            } catch { err(error.localizedDescription); return 2 }

        case "cells":
            guard let path = rest.first else { err("cells <file> [--sheet <name>]"); return 64 }
            do {
                let s = try Engine.cells(path: path, sheet: value("--sheet", args),
                                         top: 1, left: 1, rows: 500, columns: 200)
                if wantsJSON {
                    out(json(["sheet": s.sheet,
                              "cells": s.cells.map { ["reference": $0.reference, "show": $0.show, "raw": $0.raw] }]))
                } else {
                    for c in s.cells { out("\(c.reference)\t\(c.show)") }
                }
                return 0
            } catch { err(error.localizedDescription); return 2 }

        case "slides":
            guard let path = rest.first else { err("slides <file>"); return 64 }
            do {
                let d = try Engine.slides(path)
                if wantsJSON {
                    out(json(["slides": d.slides.map { ["number": $0.number, "title": $0.title,
                                                        "lines": $0.lines, "notes": $0.notes] }]))
                } else {
                    for s in d.slides {
                        out("slide \(s.number): \(s.title)")
                        for line in s.lines where !line.isEmpty { out("    \(line)") }
                        if !s.notes.isEmpty { out("    notes: \(s.notes.replacingOccurrences(of: "\n", with: " / "))") }
                    }
                }
                return 0
            } catch { err(error.localizedDescription); return 2 }

        case "set":
            guard rest.count >= 3 else { err("set <file> <ref> <value> [--sheet <name>]"); return 64 }
            do {
                let edit: [String: Any] = ["what": "cell", "sheet": value("--sheet", args) ?? "",
                                           "reference": rest[1], "value": rest[2]]
                let saved = try Engine.save(path: rest[0], edits: [edit])
                out("saved \((rest[0] as NSString).lastPathComponent): "
                    + "\(saved.parts.rewritten) of \(saved.parts.read) parts rewritten, "
                    + "\(saved.parts.kept) kept byte for byte")
                return 0
            } catch { err(error.localizedDescription); return 2 }

        case "hidden":
            guard let path = rest.first else { err("hidden <file>"); return 64 }
            do {
                let h = try Engine.hidden(path)
                if wantsJSON {
                    out(json(["found": h.found.map { ["kind": $0.kind, "what": $0.what,
                                                      "count": $0.count, "removable": $0.removable] }]))
                } else if h.found.isEmpty {
                    out("Nothing in this file travels with it that is not on the page.")
                    return 0
                } else {
                    for f in h.found { out("\(f.what)\(f.count > 1 ? "  (\(f.count))" : "")") }
                }
                return h.found.isEmpty ? 0 : 1

            } catch { err(error.localizedDescription); return 2 }

        case "preserved":
            guard let path = rest.first else { err("preserved <file>"); return 64 }
            do {
                let p = try Engine.preserved(path)
                if wantsJSON {
                    out(json(["rows": p.rows.map { ["what": $0.what, "count": $0.count, "bytes": $0.bytes] }]))
                } else {
                    for r in p.rows { out("\(r.what)\(r.count > 1 ? "  \(r.count)" : "")") }
                    out("Everything above is written back exactly as it was found.")
                }
                return 0
            } catch { err(error.localizedDescription); return 2 }

        case "roundtrip":
            guard !rest.isEmpty else { err("roundtrip <file>..."); return 64 }
            var worst: Int32 = 0
            for path in rest {
                do {
                    let t = try Engine.roundTrip(path)
                    out("\(t.identical ? "identical" : "CHANGED   ")   \((path as NSString).lastPathComponent)")
                    if !t.identical { worst = max(worst, 1) }
                } catch {
                    err("\((path as NSString).lastPathComponent): \(error.localizedDescription)")
                    worst = 2
                }
            }
            return worst

        case "selftest":
            return selftest(args)

        case "screenshots":
            guard let dir = rest.first else { err("screenshots <dir> [--announce]"); return 64 }
            return Screenshots.render(to: dir, announce: flag("--announce", args))

        default:
            err("plainmac: no such command \"\(cmd)\"")
            err(usage)
            return 64
        }
    }

    /// The app's own checks, and the engine's, because the engine is where the promise lives.
    @MainActor
    static func selftest(_ args: [String]) -> Int32 {
        let mine = Suites.run(filter: value("--filter", args), list: flag("--list", args), json: flag("--json", args))
        if flag("--list", args) { return mine }

        // The engine's fixture-dependent checks skip silently when it cannot find the files, which reads as a
        // pass. Point it at them so the number below is the whole suite and not a fraction of it.
        Engine.pointAtFixtures()

        do {
            let engine = try Engine.selfTest()
            out("engine: \(engine.summary)")

            // A check that skips prints like a check that passed. An installed app has no fixture documents
            // beside it, so about half the engine's suite cannot run, and saying 493 without saying why would
            // read as the whole thing. This is the third time that trap has been walked into.
            if !Engine.hasFixtures {
                out("        That is the part of the suite that needs no documents to work on. "
                    + "The rest runs from a clone of the repository, where the files are.")
            }
            if engine.failed > 0 {
                out(engine.output)
                return 1
            }
        } catch {
            err("the engine could not run its checks: \(error.localizedDescription)")
            return 2
        }
        return mine
    }
}
