//  Plain for Mac — MIT licensed. See LICENSE.
//
//  The window. One row of controls, the file, and a rail down the side naming what Plain is keeping but will not
//  draw. No ribbon, no tabs, no inspector: the shape of the app is the shape of the promise.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct PlainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = PlainModel.shared

    init() {
        // The command line is answered before any window is put on screen, so `plainmac selftest` in a script
        // never flashes a window at somebody.
        MainActor.assumeIsolated { CLI.runIfRequested() }
    }

    var body: some Scene {
        Window("Plain", id: "main") {
            MainView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands { PlainCommands(model: model) }

        Settings { SettingsView() }
    }
}

extension Notification.Name {
    static let plainFind = Notification.Name("plainFind")
    static let plainCarries = Notification.Name("plainCarries")
    static let plainTrace = Notification.Name("plainTrace")
    static let plainReplace = Notification.Name("plainReplace")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    /// Opening a file from the Finder, which is how most files arrive.
    func application(_ app: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated { PlainModel.shared.open(url.path) }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        guard Prefs.checkForUpdates else { return }
        Task { @MainActor in await Updates.checkIfDue() }
    }
}

struct PlainCommands: Commands {
    @ObservedObject var model: PlainModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Menu("New") {
                Button("Spreadsheet") { Files.new(.spreadsheet, into: model) }
                Button("Document") { Files.new(.document, into: model) }
                Button("Presentation") { Files.new(.presentation, into: model) }
            }
            Button("Open…") { Files.open(into: model) }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model.undo() }
                .keyboardShortcut("z")
                .disabled(!model.canUndo)
            Button("Redo") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
        }
        CommandGroup(after: .toolbar) {
            Button("Find…") { NotificationCenter.default.post(name: .plainFind, object: nil) }
                .keyboardShortcut("f")
                .disabled(model.path == nil)
            Button("Find and replace…") { NotificationCenter.default.post(name: .plainReplace, object: nil) }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(model.path == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { model.save() }
                .keyboardShortcut("s")
                .disabled(!model.dirty)
            Divider()
            Button("Check this file comes back byte for byte") { model.checkPromise() }
                .disabled(model.path == nil)
            Button("What this file would carry with it…") {
                NotificationCenter.default.post(name: .plainCarries, object: nil)
            }
            .disabled(model.path == nil)
            Divider()
            Button("Save as PDF…") { Files.pdf(model) }
                .disabled(model.path == nil)
            Button("Save a copy…") { Files.saveCopy(model) }
                .disabled(model.path == nil)
        }
        CommandGroup(replacing: .help) {
            Button("Plain Help") { Help.show() }
            Button("More from the Same Maker…") {
                NSWorkspace.shared.open(URL(string: "https://keithadler.github.io")!)
            }
        }
    }
}
