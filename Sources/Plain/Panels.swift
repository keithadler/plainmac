//  Plain for Mac — MIT licensed. See LICENSE.
//
//  The panels that show what is in a file besides its words: comments, tracked changes, links, pictures,
//  properties, and what it all adds up to.
//
//  These exist because the engine already knew all of it and the window did not ask. An operation that can only be
//  reached from a command line is not a feature of the app.

import SwiftUI
import AppKit

// ---------- about ----------

/// The same words as the Windows app, because it is the same program.
struct AboutPanel: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon).resizable().frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plain for Mac \(CLI.version)").font(.title3).bold()
                    Text("Built by Keith Adler.").foregroundStyle(.secondary)
                }
            }

            Text("Opens Word, Excel and PowerPoint files, edits the basics, and never damages what it doesn't "
                 + "understand.")

            Text("The panel on the right names everything in a file that Plain keeps but cannot draw. All of it is "
                 + "written back exactly as it was found, so nothing you cannot see is at risk when you save.")
                .foregroundStyle(.secondary)

            Text("Free and MIT licensed. No account, no cloud, no telemetry. The only thing it sends is a daily "
                 + "question to GitHub about whether there is a newer version, which you can turn off in Settings.")
                .foregroundStyle(.secondary)

            Text("The part that understands the file format is the same engine as Plain for Windows, so the two "
                 + "programs agree about what a file is by construction rather than by intention.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Link("More small apps like this one: keithadler.github.io",
                     destination: URL(string: "https://keithadler.github.io")!)
                Link("Source and issues: github.com/keithadler/plainmac",
                     destination: URL(string: "https://github.com/keithadler/plainmac")!)
            }
            .font(.callout)

            Text("Settings and kept copies live in:\n\(PlainModel.keepFolder.deletingLastPathComponent().path)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 520)
    }
}

// ---------- what else is in the file ----------

/// One panel with a tab per kind of thing the file carries besides its words.
///
/// They are together because they are one question — "what else is in here?" — and because a separate window for
/// each would be five windows to close.
struct InsidePanel: View {
    @EnvironmentObject var model: PlainModel
    @Environment(\.dismiss) private var dismiss
    @State private var showing = Inside.comments

    enum Inside: String, CaseIterable, Identifiable {
        case comments = "Comments"
        case changes = "Tracked changes"
        case links = "Links"
        case pictures = "Pictures"
        case properties = "Properties"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $showing) {
                ForEach(Inside.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)

            Divider()

            Group {
                switch showing {
                case .comments: CommentsList()
                case .changes: ChangesList()
                case .links: LinksList()
                case .pictures: PicturesList()
                case .properties: PropertiesList()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(16)
        }
        .frame(width: 640, height: 480)
        .environmentObject(model)
    }
}

private struct CommentsList: View {
    @EnvironmentObject var model: PlainModel
    @State private var found: [Engine.CommentList.Comment] = []

    var body: some View {
        Group {
            if found.isEmpty {
                NothingHere("Nobody has left a comment in this file.")
            } else {
                List(found, id: \.index) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(note.who).bold()
                            Text(note.when).foregroundStyle(.secondary).font(.caption)
                        }
                        Text(note.text)
                        // Where it is only worth saying when it says something: for a document comment the
                        // engine has nowhere better to point than "comment", and repeating that helps nobody.
                        if !note.where_.isEmpty, note.where_ != "comment" {
                            Text("on: \(note.where_)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Spacer()
                        Button("Take them all out") {
                            model.perform("removecomments")
                            load()
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let path = model.path else { return }
        found = ((try? Engine.ask("comments", ["path": path])) as Engine.CommentList?)?.comments ?? []
    }
}

private struct ChangesList: View {
    @EnvironmentObject var model: PlainModel
    @State private var found: [Engine.ChangeList.Change] = []

    var body: some View {
        Group {
            if found.isEmpty {
                NothingHere("Nothing in this file is marked as a tracked change.")
            } else {
                List(found, id: \.index) { change in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(change.added ? "Added" : "Struck out")
                                .font(.caption).bold()
                                .foregroundStyle(change.added ? Color.green : Color.red)
                            Text(change.who).bold()
                            Text(change.when).foregroundStyle(.secondary).font(.caption)
                        }
                        Text(change.text)
                    }
                    .padding(.vertical, 2)
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Text("Settling them writes the file.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Turn them all down") { model.perform("settle", ["accept": false]); load() }
                        Button("Accept them all") { model.perform("settle", ["accept": true]); load() }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let path = model.path else { return }
        found = ((try? Engine.ask("changes", ["path": path])) as Engine.ChangeList?)?.changes ?? []
    }
}

private struct LinksList: View {
    @EnvironmentObject var model: PlainModel
    @State private var found: [Engine.LinkList.Link] = []

    var body: some View {
        Group {
            if found.isEmpty {
                NothingHere("There are no links in this file.")
            } else {
                List(Array(found.enumerated()), id: \.offset) { _, link in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(link.text.isEmpty ? "(no words)" : link.text)
                        // Where it really goes, which is the point: the words can say anything.
                        Text(link.target)
                            .font(.caption)
                            .foregroundStyle(link.safe ? Color.secondary : Color.red)
                        if !link.safe {
                            Text("Plain will not open this one. It is not an ordinary web or mail address.")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let path = model.path else { return }
        found = ((try? Engine.ask("links", ["path": path])) as Engine.LinkList?)?.links ?? []
    }
}

private struct PicturesList: View {
    @EnvironmentObject var model: PlainModel
    @State private var described: [Described] = []

    struct Described: Decodable, Identifiable {
        let where_: String, name: String, text: String
        var id: String { where_ + name }
        enum CodingKeys: String, CodingKey { case where_ = "where", name, text }
    }
    struct Wrapper: Decodable { let pictures: [Described] }

    var body: some View {
        Group {
            if described.isEmpty {
                NothingHere("There are no pictures in this file.")
            } else {
                List(described) { picture in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(picture.where_): \(picture.name)")
                        TextField("What this picture shows, for somebody who cannot see it",
                                  text: Binding(
                                    get: { picture.text },
                                    set: { model.perform("describe", [
                                        "where": picture.where_, "name": picture.name, "text": $0,
                                    ]); load() }))
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let path = model.path else { return }
        described = ((try? Engine.ask("described", ["path": path])) as Wrapper?)?.pictures ?? []
    }
}

private struct PropertiesList: View {
    @EnvironmentObject var model: PlainModel
    @State private var found: [Property] = []

    struct Property: Decodable, Identifiable {
        let name: String, value: String
        let namesAPerson: Bool
        var id: String { name }
        enum CodingKeys: String, CodingKey { case name, value, namesAPerson = "names a person" }
    }
    struct Wrapper: Decodable { let properties: [Property] }

    var body: some View {
        Group {
            if found.isEmpty {
                NothingHere("This file records nothing about itself.")
            } else {
                List(found) { property in
                    HStack {
                        Text(property.name).frame(width: 160, alignment: .leading)
                        Text(property.value).foregroundStyle(.secondary)
                        Spacer()
                        if property.namesAPerson {
                            Text("names a person").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Spacer()
                        Button("Take out the ones that name a person") {
                            model.perform("setproperties", ["strip": true])
                            load()
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let path = model.path else { return }
        found = ((try? Engine.ask("properties", ["path": path])) as Wrapper?)?.properties ?? []
    }
}

private struct NothingHere: View {
    let said: String
    init(_ said: String) { self.said = said }
    var body: some View {
        VStack { Spacer(); Text(said).foregroundStyle(.secondary); Spacer() }
            .frame(maxWidth: .infinity)
    }
}
