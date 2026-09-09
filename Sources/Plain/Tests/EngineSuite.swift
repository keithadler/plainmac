//  Plain for Mac — MIT licensed. See LICENSE.
//
//  What this file checks is the join, not the engine.
//
//  The engine has a thousand checks of its own and runs them from inside this app, so nothing here re-tests what a
//  .docx is. What is new on the Mac, and therefore what can be wrong here, is the boundary: whether a request
//  crosses into native code and comes back as something Swift can read, whether a failure arrives as a sentence
//  instead of taking the process down, and whether the promise still holds when the file is reached this way.

import Foundation

enum EngineSuite {

    static let suite = TestSuite(name: "engine", cases: [

        TestCase(name: "the engine answers at all") { t in
            let v = try Engine.version()
            t.check(!v.version.isEmpty, "it says which version it is")
            t.equal(v.engine, "Plain.Core", "and that it is the same engine as the Windows app")
        },

        TestCase(name: "the engine's own checks pass inside this app") { t in
            let result = try Engine.selfTest()
            t.equal(result.failed, 0, "the engine reports no failures")
            t.check(result.summary.contains("passed"), "and says how many passed: \(result.summary)")
        },

        TestCase(name: "a file that is not there is a sentence, not a crash") { t in
            do {
                _ = try Engine.open("/nowhere/at/all/nothing.docx")
                t.fail("opening a missing file should not have worked")
            } catch {
                let said = error.localizedDescription
                t.check(!said.isEmpty, "it said something")
                t.check(!said.contains("Exception"), "and said it in words, not in type names: \(said)")
            }
        },

        TestCase(name: "something that is not an Office file is refused clearly") { t in
            let dir = TestKit.tempDir()
            let path = dir.appendingPathComponent("notreally.docx").path
            try "this is not a zip at all".write(toFile: path, atomically: true, encoding: .utf8)
            do {
                _ = try Engine.open(path)
                t.fail("a text file pretending to be a document should not have opened")
            } catch {
                t.check(!error.localizedDescription.isEmpty, "it said why: \(error.localizedDescription)")
            }
        },

        TestCase(name: "asking a document for cells is refused, not guessed at") { t in
            guard let path = try? sampleDocument() else { t.skip("could not make a document"); return }
            do {
                _ = try Engine.cells(path: path, sheet: nil, top: 1, left: 1, rows: 10, columns: 10)
                t.fail("a document has no cells and should have said so")
            } catch {
                t.check(error.localizedDescription.lowercased().contains("spreadsheet"),
                        "it said what kind it wanted: \(error.localizedDescription)")
            }
        },

        TestCase(name: "the promise holds through the boundary") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            let trip = try Engine.roundTrip(path)
            t.check(trip.identical, "a file opened and saved unchanged comes back byte for byte")
            t.check(trip.bytes > 0, "and it read something")
        },

        TestCase(name: "a workbook describes itself") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            let opened = try Engine.open(path)
            t.equal(opened.shape.kind, "spreadsheet", "it knows what it is")
            t.check((opened.shape.sheets?.count ?? 0) >= 1, "and how many sheets it has")
            t.check(opened.parts.read > 0, "and how many parts it read")
        },

        TestCase(name: "a cell written comes back with the same value") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            let saved = try Engine.save(path: path, edits: [
                ["what": "cell", "sheet": "", "reference": "B2", "value": "Woodland Ave"]
            ])
            t.equal(saved.changed, 1, "one change was made")

            let screen = try Engine.cells(path: path, sheet: nil, top: 1, left: 1, rows: 10, columns: 10)
            let b2 = screen.cells.first { $0.reference == "B2" }
            t.equal(b2?.show, "Woodland Ave", "and it is in the file afterwards")
        },

        TestCase(name: "a number stays a number") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            _ = try Engine.save(path: path, edits: [
                ["what": "cell", "sheet": "", "reference": "C3", "value": "25000"]
            ])
            let screen = try Engine.cells(path: path, sheet: nil, top: 1, left: 1, rows: 10, columns: 10)
            let c3 = screen.cells.first { $0.reference == "C3" }
            t.equal(c3?.raw, "25000", "it was stored as the number, not as words")
            t.check(c3?.kind != "text", "and the file says so: \(c3?.kind ?? "missing")")
        },

        TestCase(name: "saving only rewrites what it had to") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            let saved = try Engine.save(path: path, edits: [
                ["what": "cell", "sheet": "", "reference": "A1", "value": "Pine Street Holdings"]
            ])
            t.check(saved.parts.kept > 0, "some parts were kept byte for byte")
            t.check(saved.parts.rewritten < saved.parts.read, "and not everything was rewritten")
        },

        TestCase(name: "what a file carries can be asked for") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            let hidden = try Engine.hidden(path)
            t.check(hidden.found.count >= 0, "it answers without complaining")
            let preserved = try Engine.preserved(path)
            t.check(preserved.rows.count >= 0, "and so does the list of what it keeps")
        },

        TestCase(name: "many calls in a row do not run the memory down") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            // Every answer is allocated by the engine and freed by the app. If that is wrong, it is wrong
            // repeatedly, and this is where it would show.
            for _ in 0..<200 { _ = try Engine.open(path) }
            let after = try Engine.open(path)
            t.check(after.parts.read > 0, "the two hundred and first call answers like the first")
        },

        TestCase(name: "a change can be taken back") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            let model = PlainModel()
            model.open(path)

            t.check(!model.canUndo, "nothing to undo to begin with")
            model.change(Edit(what: .cell(sheet: "", reference: "A1", value: "first")))
            model.change(Edit(what: .cell(sheet: "", reference: "A1", value: "second")))
            t.equal(model.edits.count, 1, "two changes to one cell are one change to save")
            t.check(model.canUndo, "and there is something to undo")

            model.undo()
            t.equal(model.edits.count, 1, "undoing the second leaves the first")
            if case let .cell(_, _, value) = model.edits.first?.what { t.equal(value, "first", "and it is the first one") }

            model.undo()
            t.check(model.edits.isEmpty, "undoing the first leaves nothing to save")
            t.check(!model.dirty, "so the file has no unsaved changes")
            t.check(!model.canUndo, "and there is nothing left to undo")
        },

        TestCase(name: "undone changes can be done again") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            let model = PlainModel()
            model.open(path)
            model.change(Edit(what: .cell(sheet: "", reference: "B2", value: "Woodland Ave")))
            model.undo()
            t.check(model.canRedo, "there is something to do again")
            model.redo()
            t.equal(model.edits.count, 1, "and doing it again puts it back")
            t.check(!model.canRedo, "with nothing left to redo")
        },

        TestCase(name: "a new change forgets what was undone") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            let model = PlainModel()
            model.open(path)
            model.change(Edit(what: .cell(sheet: "", reference: "C3", value: "one")))
            model.undo()
            model.change(Edit(what: .cell(sheet: "", reference: "D4", value: "two")))
            t.check(!model.canRedo, "redo would put back something that no longer follows")
        },

        TestCase(name: "undoing everything means there is nothing to write") { t in
            guard let path = try? sampleWorkbook() else { t.skip("could not make a workbook"); return }
            let before = try Data(contentsOf: URL(fileURLWithPath: path))

            let model = PlainModel()
            model.open(path)
            model.change(Edit(what: .cell(sheet: "", reference: "A1", value: "typed then taken back")))
            model.undo()
            model.save()

            let after = try Data(contentsOf: URL(fileURLWithPath: path))
            t.check(before == after, "the file on disk is exactly as it was found")
        },
    ])

    // ---------- files to work on ----------

    @MainActor
    private static func sampleWorkbook() throws -> String {
        let dir = TestKit.tempDir()
        let path = dir.appendingPathComponent("sample.xlsx").path
        _ = try Engine.make(path)
        return path
    }

    @MainActor
    private static func sampleDocument() throws -> String {
        let dir = TestKit.tempDir()
        let path = dir.appendingPathComponent("sample.docx").path
        _ = try Engine.make(path)
        return path
    }
}
