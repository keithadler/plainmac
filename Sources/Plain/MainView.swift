//  Plain for Mac — MIT licensed. See LICENSE.
//
//  What the window shows. One row of controls across the top, the file in the middle, the rail on the right, and
//  a line at the bottom that says what was kept the last time anything was saved.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var model: PlainModel
    @State private var finding = false
    @State private var looking = ""
    @State private var carrying = false
    @State private var tracing: String?
    @State private var replacing = false

    var body: some View {
        VStack(spacing: 0) {
            Controls()
            Divider()

            // A newer version, mentioned once and never insisted on. No dialog, no timer, no nagging.
            if let found = model.newVersion {
                UpdateBar(version: found.version, page: found.page)
                Divider()
            }

            if finding {
                FindBar(looking: $looking, close: { finding = false; looking = "" })
                Divider()
            }

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
        .sheet(isPresented: $carrying) { Carries().environmentObject(model) }
        .sheet(item: Binding(get: { tracing.map(Traced.init) }, set: { tracing = $0?.cell })) { what in
            TracePanel(cell: what.cell).environmentObject(model)
        }
        .sheet(isPresented: $replacing) { ReplacePanel().environmentObject(model) }
        .onReceive(NotificationCenter.default.publisher(for: .plainTrace)) { note in
            tracing = note.object as? String
        }
        .onReceive(NotificationCenter.default.publisher(for: .plainReplace)) { _ in replacing = true }
        .onReceive(NotificationCenter.default.publisher(for: .plainFind)) { _ in finding = true }
        .onReceive(NotificationCenter.default.publisher(for: .plainCarries)) { _ in carrying = true }
        .environment(\.plainLooking, looking)
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
            if !model.stats.isEmpty {
                Text(model.stats)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let opened = model.opened {
                Text(opened.shape.kind.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
    }
}


/// What is being looked for, so every surface can highlight it without being handed a binding.
private struct LookingKey: EnvironmentKey { static let defaultValue = "" }

extension EnvironmentValues {
    var plainLooking: String {
        get { self[LookingKey.self] }
        set { self[LookingKey.self] = newValue }
    }
}

private struct FindBar: View {
    @EnvironmentObject var model: PlainModel
    @Binding var looking: String
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in this file", text: $looking)
                .textFieldStyle(.plain)
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit(close)

            Text(found)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Done") { close() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// How many places hold it. Searching what is on screen rather than the file, because that is what is being
    /// looked at, and it is instant.
    private var found: String {
        guard !looking.isEmpty else { return "" }
        let needle = looking.lowercased()
        var n = 0
        n += (model.screen?.cells ?? []).filter { $0.show.lowercased().contains(needle) }.count
        n += (model.document?.blocks ?? []).filter { $0.text.lowercased().contains(needle) }.count
        n += (model.deck?.slides ?? []).filter {
            $0.title.lowercased().contains(needle) || $0.notes.lowercased().contains(needle)
                || $0.lines.contains { $0.lowercased().contains(needle) }
        }.count
        return n == 0 ? "nothing" : "\(n) found"
    }
}

/// Everything the file would take with it if you sent it, which is the question worth asking before you do.
private struct Carries: View {
    @EnvironmentObject var model: PlainModel
    @Environment(\.dismiss) private var dismiss
    @State private var found: [Engine.Hidden.Finding] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What this file would carry with it")
                .font(.title3).bold()
                .padding(.horizontal, 22).padding(.top, 22)

            Text("Things that travel with the file and are not on the page. Plain can only find what it knows to "
                 + "look for, so this is a list, not a promise that the file is safe.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 12)

            if found.isEmpty {
                Text("Nothing found that is not on the page.")
                    .foregroundStyle(.secondary)
                    .padding(22)
            } else {
                List(Array(found.enumerated()), id: \.offset) { _, finding in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.what)
                            if !finding.removable {
                                Text("Somebody's working, not an accident. Plain leaves this alone.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if finding.count > 1 { Text("\(finding.count)").foregroundStyle(.secondary) }
                    }
                }
                .frame(minHeight: 200)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(22)
        }
        .frame(width: 560)
        .onAppear { found = model.whatItCarries() }
    }
}


/// A cell being traced, so it can be handed to a sheet as an item.
private struct Traced: Identifiable {
    let cell: String
    var id: String { cell }
}

/// What a cell's formula reads, and what reads the cell. The question behind most spreadsheet mistakes.
private struct TracePanel: View {
    @EnvironmentObject var model: PlainModel
    @Environment(\.dismiss) private var dismiss
    let cell: String
    @State private var traced: Engine.Traced?
    @State private var failed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What \(cell) takes part in")
                .font(.title3).bold()
                .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 12)

            if let failed {
                Text(failed).foregroundStyle(.secondary).padding(.horizontal, 22)
            } else if let traced {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(traced.reads.isEmpty
                             ? "\(cell) holds no formula, so it reads nothing."
                             : "\(cell) reads")
                            .font(.callout).bold().padding(.top, 4)
                        ForEach(Array(traced.reads.enumerated()), id: \.offset) { _, t in
                            HStack(alignment: .top) {
                                Text(t.where_).font(.system(.callout, design: .monospaced))
                                Text(t.what).foregroundStyle(.secondary)
                            }
                        }

                        Text(traced.readBy.isEmpty
                             ? "Nothing else reads \(cell)."
                             : "\(cell) is read by")
                            .font(.callout).bold().padding(.top, 14)
                        ForEach(Array(traced.readBy.enumerated()), id: \.offset) { _, t in
                            HStack(alignment: .top) {
                                Text(t.where_).font(.system(.callout, design: .monospaced))
                                Text(t.what).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                }
            } else {
                ProgressView().padding(22)
            }

            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
                .padding(22)
        }
        .frame(width: 620, height: 440)
        .onAppear {
            guard let path = model.path else { return }
            do {
                traced = try Engine.ask("traces", ["path": path, "sheet": model.sheet ?? "", "cell": cell])
            } catch { failed = error.localizedDescription }
        }
    }
}

/// Find and replace across the whole file. It says what it would change before it changes anything.
private struct ReplacePanel: View {
    @EnvironmentObject var model: PlainModel
    @Environment(\.dismiss) private var dismiss
    @State private var find = ""
    @State private var with = ""
    @State private var matchCase = false
    @State private var wholeWord = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find and replace").font(.title3).bold()

            TextField("Find", text: $find).textFieldStyle(.roundedBorder)
            TextField("Replace with", text: $with).textFieldStyle(.roundedBorder)

            Toggle("Match upper and lower case", isOn: $matchCase)
            Toggle("Whole words only", isOn: $wholeWord)

            Text("This changes the file when you do it, and it cannot be undone from here. "
                 + "Everything Plain does not understand is written back untouched either way.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Replace all") {
                    model.perform("replace", [
                        "find": find, "with": with,
                        "matchCase": matchCase, "wholeWord": wholeWord,
                    ])
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(find.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}


/// One line saying there is a newer version. It is the only thing the daily check ever does.
private struct UpdateBar: View {
    @EnvironmentObject var model: PlainModel
    let version: String
    let page: URL

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
            Text("Version \(version) is out. You have \(CLI.version).")
                .font(.callout)
            Spacer()
            Button("See what changed") { NSWorkspace.shared.open(page) }
            Button("Not now") {
                // Not asked about again until there is a version newer than this one.
                Updates.skippedVersion = version
                model.newVersion = nil
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.10))
    }
}
