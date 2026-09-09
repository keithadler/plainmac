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
    static let plainAbout = Notification.Name("plainAbout")
    static let plainInside = Notification.Name("plainInside")
    static let plainFolder = Notification.Name("plainFolder")
    static let plainCompare = Notification.Name("plainCompare")
    static let plainBand = Notification.Name("plainBand")
    static let plainSlide = Notification.Name("plainSlide")
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
        CommandGroup(replacing: .appInfo) {
            Button("About Plain for Mac") { NotificationCenter.default.post(name: .plainAbout, object: nil) }
            Button("Check for a newer version now") {
                Task { @MainActor in
                    Updates.lastCheck = nil
                    Updates.skippedVersion = nil
                    await Updates.checkIfDue()
                    if PlainModel.shared.newVersion == nil {
                        PlainModel.shared.said = "This is the newest version there is."
                    }
                }
            }
        }
        CommandMenu("File contents") {
            Button("What else is in this file…") {
                NotificationCenter.default.post(name: .plainInside, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("What this file would carry with it…") {
                NotificationCenter.default.post(name: .plainCarries, object: nil)
            }
            Divider()
            Button("Word and character count") { model.perform("count", [:], needsSaveFirst: false) }
            Button("Compare with another version…") {
                NotificationCenter.default.post(name: .plainCompare, object: nil)
            }
            Button("Find in a whole folder…") {
                NotificationCenter.default.post(name: .plainFolder, object: nil)
            }
            Divider()
            Button("Save the sheet as CSV…") { Files.csv(model) }
                .disabled(model.path == nil)
        }

        CommandMenu("Shape") {
            Section("Document") {
                Button("Add a row to the first table") { model.perform("tablerow", ["how": "add", "table": 0, "row": 0]) }
                Button("Take a row out of the first table") { model.perform("tablerow", ["how": "remove", "table": 0, "row": 0]) }
                Button("Change the page header…") {
                    NotificationCenter.default.post(name: .plainBand, object: true)
                }
                Button("Change the page footer…") {
                    NotificationCenter.default.post(name: .plainBand, object: false)
                }
                Button("Put a picture in…") { Files.picture(model) }
            }
            Section("Presentation") {
                Button("Add a slide") { model.perform("slide", ["how": "add", "at": 0]) }
                Button("Take this slide out") {
                    NotificationCenter.default.post(name: .plainSlide, object: "remove")
                }
                Button("Move this slide earlier") {
                    NotificationCenter.default.post(name: .plainSlide, object: "earlier")
                }
                Button("Move this slide later") {
                    NotificationCenter.default.post(name: .plainSlide, object: "later")
                }
            }
        }

        CommandGroup(replacing: .help) {
            Button("Plain Help") { Help.show() }
            Button("More from the Same Maker…") {
                NSWorkspace.shared.open(URL(string: "https://keithadler.github.io")!)
            }
        }
    }
}
