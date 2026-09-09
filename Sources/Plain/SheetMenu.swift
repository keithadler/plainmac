//  Plain for Mac — MIT licensed. See LICENSE.
//
//  What you can do to a sheet, on the right-click menu, which is where the Windows app puts it too.
//
//  Everything here goes to the engine, which refuses a great deal on purpose: it will not sort rows a formula
//  reads, will not split a column over the top of the one beside it, will not take out a sheet something still
//  points at. When it refuses it says why, and that sentence goes straight into the window. The refusals are the
//  product, not an inconvenience to work around.

import SwiftUI

struct SheetMenu: View {
    @EnvironmentObject var model: PlainModel
    @Binding var selection: Selection
    let column: Int
    let row: Int

    private var block: [String: Any] { model.block(selection) }

    var body: some View {
        Section(selection.described) {
            Button("Sort these rows by column \(Reference.name(selection.left))") {
                model.perform("sort", block.merging(["by": selection.left]) { a, _ in a })
            }
            Button("Sort them the other way") {
                model.perform("sort", block.merging(["by": selection.left, "descending": true]) { a, _ in a })
            }
        }

        Menu("Tidy") {
            Button("Take out rows that say the same thing") {
                var ask = block
                // Judging a row by one column and moving only that column would tear the row apart.
                if selection.left == selection.right {
                    ask["left"] = 1
                    ask["right"] = max(1, model.opened?.shape.sheets?.first { $0.name == model.sheet }?.lastColumn ?? 1)
                }
                model.perform("tidy", ask.merging(["how": "dedupe"]) { a, _ in a })
            }
            Button("Split this column at a comma") {
                model.perform("tidy", block.merging(["how": "split", "on": ","]) { a, _ in a })
            }
            Button("Split this column at a space") {
                model.perform("tidy", block.merging(["how": "split", "on": " "]) { a, _ in a })
            }
        }

        Divider()

        Menu("Rows and columns") {
            Button("Insert a row above") { model.perform("grid", ["how": "insertrow", "at": selection.top]) }
            Button("Delete this row") { model.perform("grid", ["how": "deleterow", "at": selection.top]) }
            Divider()
            Button("Insert a column to the left") { model.perform("grid", ["how": "insertcolumn", "at": selection.left]) }
            Button("Delete this column") { model.perform("grid", ["how": "deletecolumn", "at": selection.left]) }
            Divider()
            Button("Fit this column to its contents") { model.perform("width", ["column": selection.left, "fit": true]) }
            Button("Make this row taller") { model.perform("height", ["row": selection.top, "points": 30]) }
            Button("Let this row find its own height") { model.perform("height", ["row": selection.top, "auto": true]) }
        }

        Menu("Keep on screen") {
            Button("Keep the rows above this one") { model.perform("freeze", ["rows": selection.top - 1, "columns": 0]) }
            Button("Keep the columns left of this one") { model.perform("freeze", ["rows": 0, "columns": selection.left - 1]) }
            Button("Keep both") {
                model.perform("freeze", ["rows": selection.top - 1, "columns": selection.left - 1])
            }
            Button("Let it all scroll") { model.perform("freeze", ["rows": 0, "columns": 0]) }
        }

        Divider()

        Menu("How they look") {
            Button("Bold") { model.perform("weight", block.merging(["bold": true]) { a, _ in a }) }
            Button("Not bold") { model.perform("weight", block.merging(["bold": false]) { a, _ in a }) }
            Button("Italic") { model.perform("weight", block.merging(["italic": true]) { a, _ in a }) }
            Divider()
            Button("Left") { model.perform("align", block.merging(["horizontal": "left"]) { a, _ in a }) }
            Button("Centre") { model.perform("align", block.merging(["horizontal": "center"]) { a, _ in a }) }
            Button("Right") { model.perform("align", block.merging(["horizontal": "right"]) { a, _ in a }) }
            Button("Wrap the words") { model.perform("align", block.merging(["wrap": true]) { a, _ in a }) }
            Button("Do not wrap") { model.perform("align", block.merging(["wrap": false]) { a, _ in a }) }
        }

        Menu("Colour") {
            ForEach(Palette.fills, id: \.0) { name, hex in
                Button(name) { model.perform("colour", block.merging(["fill": hex]) { a, _ in a }) }
            }
            Divider()
            ForEach(Palette.inks, id: \.0) { name, hex in
                Button("Words: \(name)") { model.perform("colour", block.merging(["ink": hex]) { a, _ in a }) }
            }
        }

        Menu("Lines round them") {
            ForEach(Palette.weights, id: \.0) { name, code in
                Button(name) { model.perform("border", block.merging(["style": code]) { a, _ in a }) }
            }
            Button("None") { model.perform("border", block.merging(["style": ""]) { a, _ in a }) }
        }

        Menu("Show the numbers as") {
            ForEach(Palette.formats, id: \.0) { name, code in
                Button(name) { model.perform("format", block.merging(["code": code]) { a, _ in a }) }
            }
        }

        Divider()

        Button("What \(selection.reference) reads, and what reads it") {
            NotificationCenter.default.post(name: .plainTrace, object: selection.reference)
        }
    }
}

/// The sheets themselves: adding, renaming, moving, taking out.
struct SheetsMenu: View {
    @EnvironmentObject var model: PlainModel
    @Binding var renaming: Bool

    var body: some View {
        Button("Add a sheet") { model.perform("sheet", ["how": "add", "name": nextName()]) }

        if let sheets = model.opened?.shape.sheets, let current = model.sheet,
           let at = sheets.firstIndex(where: { $0.name == current }) {
            Button("Rename \(current)…") { renaming = true }
            Button("Take \(current) out") { model.perform("sheet", ["how": "remove", "at": at + 1]) }
            Divider()
            Button("Move it first") { model.perform("sheet", ["how": "move", "at": at + 1, "to": 1]) }
            Button("Move it last") { model.perform("sheet", ["how": "move", "at": at + 1, "to": sheets.count]) }
        }
    }

    /// A name nothing else has, so adding a sheet never fails for the reason nobody cares about.
    private func nextName() -> String {
        let taken = Set(model.opened?.shape.sheets?.map(\.name) ?? [])
        var n = taken.count + 1
        while taken.contains("Sheet\(n)") { n += 1 }
        return "Sheet\(n)"
    }
}
