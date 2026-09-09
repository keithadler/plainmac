//  Plain for Mac — MIT licensed. See LICENSE.
//
//  Everything the app can do to a file beyond typing into it: sorting, filtering, colours, borders, sheets,
//  slides, links, replacing, page setup.
//
//  All of these change the file on disk when they run, unlike typing, which is collected and written on Save.
//  That is because they are structural: sorting rows renumbers everything, taking out a sheet changes what the
//  formulas mean. Doing those to a copy in memory and hoping to replay them later is how a program gets a file
//  wrong. So each one is done by the engine, the file is written once, and the window is built again from what
//  came back. The window says so when it happens.

import Foundation
import SwiftUI

extension PlainModel {

    /// Do something structural, then read the file again, because the numbering of everything may have changed.
    func perform(_ op: String, _ named: [String: Any] = [:], needsSaveFirst: Bool = true) {
        guard let path else { return }

        // Anything typed and not yet written has to go in first, or the operation would work on the older file
        // and the typing would be lost.
        if needsSaveFirst && dirty {
            do { _ = try Engine.save(path: path, edits: edits.map(\.asJSON)) }
            catch { failed = error.localizedDescription; return }
        }

        var request = named
        request["path"] = path
        if request["sheet"] == nil, let sheet { request["sheet"] = sheet }

        do {
            let done = try Engine.run(op, request)
            open(path)      // the shape may be different now; read it again rather than guess
            if let what = done.said { said = what }
        } catch {
            failed = error.localizedDescription
        }
    }

    /// The block of cells an operation should work on, from the selection.
    func block(_ selection: Selection) -> [String: Any] {
        ["left": selection.left, "top": selection.top, "right": selection.right, "bottom": selection.bottom]
    }
}

/// What is selected on a sheet: one cell, or a rectangle of them.
struct Selection: Equatable {
    var anchorColumn = 1, anchorRow = 1
    var column = 1, row = 1

    var left: Int { min(anchorColumn, column) }
    var right: Int { max(anchorColumn, column) }
    var top: Int { min(anchorRow, row) }
    var bottom: Int { max(anchorRow, row) }

    var isOne: Bool { left == right && top == bottom }
    var reference: String { "\(Reference.name(column))\(row)" }

    var described: String {
        isOne ? reference
              : "\(Reference.name(left))\(top):\(Reference.name(right))\(bottom)"
    }

    mutating func move(to column: Int, row: Int, extending: Bool) {
        if !extending { anchorColumn = column; anchorRow = row }
        self.column = column
        self.row = row
    }

    func contains(_ column: Int, _ row: Int) -> Bool {
        column >= left && column <= right && row >= top && row <= bottom
    }
}

/// The colours and weights offered, kept here so the menu and the engine agree about the names.
enum Palette {
    static let fills: [(String, String)] = [
        ("None", ""),
        ("Yellow", "FFF3C4"),
        ("Green", "D7EFD8"),
        ("Blue", "DCEAF7"),
        ("Pink", "F7DFE4"),
        ("Grey", "E8E8E4"),
    ]

    static let inks: [(String, String)] = [
        ("Default", ""),
        ("Red", "B3261E"),
        ("Green", "1E6B34"),
        ("Blue", "1F4E9C"),
        ("Grey", "6B6B66"),
    ]

    static let weights: [(String, String)] = [
        ("Thin", "thin"),
        ("Medium", "medium"),
        ("Thick", "thick"),
        ("Dotted", "dotted"),
        ("Dashed", "dashed"),
        ("Double", "double"),
    ]

    /// The number formats people ask for by name, matching the Windows app's list.
    static let formats: [(String, String)] = [
        ("General", "General"),
        ("Number", "#,##0.00"),
        ("Whole number", "#,##0"),
        ("Money", "#,##0.00"),
        ("Percentage", "0.0%"),
        ("Date", "yyyy-mm-dd"),
        ("Text", "@"),
    ]
}
