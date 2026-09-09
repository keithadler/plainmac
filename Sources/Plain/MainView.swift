//  Plain for Mac — MIT licensed. See LICENSE.
//
//  What the window shows. One row of controls across the top, the file in the middle, the rail on the right, and
//  a line at the bottom that says what was kept the last time anything was saved.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var model: PlainModel

    var body: some View {
        VStack(spacing: 0) {
            Controls()
            Divider()

            if model.path == nil {
                Empty()
            } else {
                HStack(spacing: 0) {
                    Content()
                    if Prefs.showPreserved, let preserved = model.preserved, !preserved.rows.isEmpty {
                        Divider()
                        Rail(preserved: preserved)
                    }
                }
            }

            Divider()
            StatusLine()
        }
        .alert("Plain", isPresented: .constant(model.failed != nil)) {
            Button("All right") { model.failed = nil }
        } message: {
            Text(model.failed ?? "")
        }
    }
}

/// The one row. Everything the app does that is worth a button is here, and nothing else is.
private struct Controls: View {
    @EnvironmentObject var model: PlainModel

    var body: some View {
        HStack(spacing: 8) {
            Menu("New") {
                Button("Spreadsheet") { Files.new(.spreadsheet, into: model) }
                Button("Document") { Files.new(.document, into: model) }
                Button("Presentation") { Files.new(.presentation, into: model) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button("Open") { Files.open(into: model) }
            Button("Save") { model.save() }.disabled(!model.dirty)

            if let opened = model.opened, let sheets = opened.shape.sheets, sheets.count > 1 {
                Divider().frame(height: 16)
                Picker("", selection: Binding(
                    get: { model.sheet ?? sheets[0].name },
                    set: { model.show(sheet: $0) }
                )) {
                    ForEach(sheets, id: \.name) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                .fixedSize()
            }

            Spacer()

            if model.dirty {
                Text("\(model.edits.count) unsaved")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let preserved = model.preserved, !preserved.rows.isEmpty {
                Button {
                    Prefs.showPreserved.toggle()
                    model.objectWillChange.send()
                } label: {
                    Label("Kept \(preserved.rows.reduce(0) { $0 + $1.count })", systemImage: "lock.doc")
                }
                .help("What this file carries that Plain will not draw, and writes back untouched")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct Empty: View {
    @EnvironmentObject var model: PlainModel

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Open a Word, Excel or PowerPoint file, or drop one here.")
                .font(.title3)
            Text("Plain edits the basics and keeps everything else exactly as it found it.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.open(url.path) }
            }
            return true
        }
    }
}

/// Whichever of the three the file is.
private struct Content: View {
    @EnvironmentObject var model: PlainModel

    var body: some View {
        Group {
            if model.screen != nil { SheetView() }
            else if model.document != nil { DocumentView() }
            else if model.deck != nil { DeckView() }
            else { Color.clear }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The rail: what is in the file, being kept, that Plain will not draw. The point of the whole program, made visible.
private struct Rail: View {
    let preserved: Engine.Preserved

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("KEPT, NOT SHOWN")
                .font(.caption).bold()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 2)

            Text("In this file but not drawn. Written back byte for byte when you save.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.bottom, 10)

            List(Array(preserved.rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    // What it is, in words. The part's path is where it lives, which is not what anyone wants
                    // to read down the side of a window.
                    Text(row.what)
                    Spacer()
                    if row.count > 1 {
                        Text("\(row.count)").foregroundStyle(.secondary).font(.callout)
                    }
                }
            }
            .listStyle(.plain)

            if preserved.bookkeeping.count > 0 {
                Text("Everything else in this file is something Plain shows, apart from "
                     + "\(preserved.bookkeeping.count) parts of bookkeeping. Nothing is being held back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
        }
        .frame(width: 280)
    }
}

private struct StatusLine: View {
    @EnvironmentObject var model: PlainModel

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.orange).frame(width: 7, height: 7)
            Text(model.said.isEmpty ? "Nothing open." : model.said)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let opened = model.opened {
                Text(opened.shape.kind.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
    }
}
