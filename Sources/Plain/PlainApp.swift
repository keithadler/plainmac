//  Plain for Mac — MIT licensed. See LICENSE.
//
//  One window per file, which is how a Mac works: several documents open at once, and macOS puts tabs over the
//  top of that for free. The Windows app has a tab strip of its own because Windows does not hand you one.
//
//  Each window has its own model. That matters more than it sounds: with one model shared between windows,
//  opening a second file replaced the first, which is exactly what was happening.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct PlainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // The command line is answered before any window is put on screen, so `plainmac selftest` in a script
        // never flashes a window at somebody.
        MainActor.assumeIsolated {
            CLI.runIfRequested()

            // Started with files on the command line, which is what happens when the binary is run directly
            // rather than through the Finder.
            let opens = Set(["xlsx", "xlsm", "docx", "docm", "pptx", "pptm"])
            let files = CommandLine.arguments.dropFirst().filter {
                opens.contains(($0 as NSString).pathExtension.lowercased())
                    && FileManager.default.fileExists(atPath: $0)
            }
            if !files.isEmpty { AppState.shared.waiting.append(contentsOf: files) }
        }

        // Double-clicking a file with the app closed sends the open-documents event before any delegate exists,
        // and it is simply lost: the app came up with an empty window and the file nowhere. Claiming the event
        // here, in init, is early enough to catch it.
        Opening.listen()
    }

    var body: some Scene {
        // A default value so there is always a window at launch. Without one, starting the app with files to
        // open opened nothing at all: there was a process and no window.
        WindowGroup(for: String.self) { $path in
            FileWindow(path: path)
        } defaultValue: {
            ""
        }
        .commands { PlainCommands() }
        // Plain opens the files it is asked to open. Putting back the windows from a previous session gave
        // people files they had not asked for on top of the ones they had. macOS 14 has no way to say so and
        // restores them anyway, which is why a window that is handed a file it cannot find closes itself.
        .restoration()

        Settings { SettingsView() }
    }
}

private extension Scene {
    func restoration() -> some Scene {
        if #available(macOS 15, *) { return restorationBehavior(.disabled) }
        return self
    }
}

/// One open file, with a model of its own.
struct FileWindow: View {
    let path: String?
    @StateObject private var model = PlainModel()
    @State private var me = UUID()
    @State private var place = WindowPlace()

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var app = AppState.shared

    var body: some View {
        MainView()
            .environmentObject(model)
            .frame(minWidth: 900, minHeight: 560)
            .navigationTitle(model.name)
            // On macOS 27 the title above stays "Plain" after the file opens. The window then reads as blank to
            // closeIfSpare, a second request for the same file cannot find its window, and the Window menu lists
            // every window as "Plain". Setting the window's own title keeps all three working on every version.
            .background(WindowTitle(title: model.name, place: place))
            .focusedSceneObject(model)
            .onAppear {
                show()
                model.startKeeping()
                drain()
            }
            // The window's file arrives after the window does. SwiftUI hands a new window its value on a later
            // turn than the one it appears on, and a window put back from last time gets its value later still,
            // so opening the file only in onAppear opened nothing: the path was empty when it was asked for.
            .onChange(of: path) { _, _ in show() }
            .onDisappear { app.letGo(me) }
            .onChange(of: app.waiting) { _, _ in drain() }
            .onChange(of: app.opened) { _, _ in
                // Same reason for the wait: a window that looks blank this instant may be a file's window a
                // moment from now, and closing it would lose the file.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: closeIfSpare)
            }
    }

    /// Opens this window's file, once there is one.
    ///
    /// One file, one window. Asking for a file that is already open should bring its window forward, not make a
    /// second window onto the same file — two windows editing one file is a way to lose work.
    private func show() {
        guard let path, !path.isEmpty, model.path == nil else { return }
        // A window put back from a previous session can name a file that has since been moved or deleted.
        guard FileManager.default.fileExists(atPath: path) else { leave(); return }
        guard app.claim(path, by: me) else { leave(); return }
        model.open(path)
    }

    /// Once files have windows of their own, a window still sitting blank is one nobody asked for. There are two
    /// ways to end up with one: macOS opens a window at launch, and it puts back the windows that were open last
    /// time. Neither knows anything about the files being opened now.
    ///
    /// A blank window is never work in progress — New writes its file before opening a window, so a window with
    /// no file has nothing in it to lose.
    private func closeIfSpare() {
        guard (path ?? "").isEmpty, model.path == nil else { return }
        // Never the last one. An app with no window at all looks like an app that failed to start.
        guard NSApp.windows.contains(where: { $0.isVisible && $0.title != "Plain" }) else { return }
        leave()
    }

    /// Closes this window. On macOS 27, `dismiss` asked while a new window is still being handed its file does
    /// nothing, so opening a file that was already open brought its window forward and left a blank one behind.
    /// The window itself is closed as well when it is still there a moment later.
    private func leave() {
        dismiss()
        let place = place
        DispatchQueue.main.async {
            if let window = place.window, window.isVisible { window.close() }
        }
    }

    /// Files that arrived from the Finder before there was a window to put them in.
    ///
    /// macOS hands them to the app delegate, which is outside any view and cannot open a window itself. They wait
    /// here until a window exists to ask for more.
    private func drain() {
        guard !app.waiting.isEmpty else { return }
        var rest = app.waiting
        app.waiting = []

        // An empty window takes the first one rather than opening a second and leaving a blank one behind.
        if model.path == nil, let first = rest.first, app.claim(first, by: me) {
            rest.removeFirst()
            model.open(first)
        }
        for path in rest { openWindow(value: path) }

        // Tells the windows that are still blank that they are now spare.
        app.opened += 1
    }
}

/// Puts a title on the window this view is in, and keeps it there as the title changes.
///
/// `navigationTitle` alone is not enough on macOS 27: it sets the first title and then stops following the model,
/// and other code here finds windows by their titles.
struct WindowTitle: NSViewRepresentable {
    let title: String
    var place: WindowPlace? = nil

    func makeNSView(context: Context) -> Holder { Holder() }

    func updateNSView(_ view: Holder, context: Context) {
        view.title = title
        view.place = place
        place?.window = view.window
        // SwiftUI may set its own title in the same pass, so this goes on the next turn of the run loop.
        DispatchQueue.main.async { WindowTitle.apply(view.title, to: view.window) }
    }

    /// Also answers when it is put into a window, since the first update can come before there is one.
    final class Holder: NSView {
        var title = ""
        var place: WindowPlace?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            place?.window = window
            WindowTitle.apply(title, to: window)
        }
    }

    @MainActor static func apply(_ title: String, to window: NSWindow?) {
        guard let window, window.title != title else { return }
        window.title = title
    }
}

/// Which window a SwiftUI view ended up in, for the times a view has to act on its window directly.
@MainActor
final class WindowPlace {
    weak var window: NSWindow?
}

/// The few things that belong to the whole app rather than to one open file.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// A newer version, when the daily check found one. Every window shows it; it is not about one file.
    @Published var newVersion: Found?

    /// Goes up every time files are given windows. A window with no file watches this to know it is spare.
    @Published var opened = 0

    /// Which window is showing which file, so the same file is never opened into two windows at once. macOS puts
    /// back the windows from last time, and those files can be the ones being opened now.
    private var showing: [String: UUID] = [:]

    /// True when this window may show this file: nobody else is, or it already is.
    func claim(_ path: String, by window: UUID) -> Bool {
        let real = (path as NSString).resolvingSymlinksInPath
        if let already = showing[real], already != window {
            bringForward(real)
            return false
        }
        showing[real] = window
        return true
    }

    func letGo(_ window: UUID) { showing = showing.filter { $0.value != window } }

    /// The window already showing a file, put where the person asking for it can see it.
    private func bringForward(_ path: String) {
        let name = (path as NSString).lastPathComponent
        NSApp.windows.first { $0.isVisible && $0.title == name }?.makeKeyAndOrderFront(nil)
    }

    /// Files the Finder handed over before a window existed to show them in.
    @Published var waiting: [String] = []

    struct Found: Equatable {
        let version: String
        let page: URL
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    /// Opening files from the Finder, which is how most of them arrive. One window each.
    ///
    /// The delegate cannot open a SwiftUI window itself, so the paths wait for the first window to take them.
    ///
    /// Both of these are here on purpose. WindowGroup is not a DocumentGroup, so SwiftUI does no file opening of
    /// its own, and which of the two AppKit calls arrives depends on how the app was started: the newer one when
    /// a file is opened into an app already running, the older one at a cold start with files. Answering only the
    /// newer one meant double-clicking a file with the app closed opened an empty window and lost the file.
    func application(_ app: NSApplication, open urls: [URL]) {
        Task { @MainActor in AppState.shared.waiting.append(contentsOf: urls.map(\.path)) }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        Task { @MainActor in AppState.shared.waiting.append(contentsOf: filenames) }
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        Task { @MainActor in AppState.shared.waiting.append(filename) }
        return true
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        guard Prefs.checkForUpdates else { return }
        Task { @MainActor in await Updates.checkIfDue() }
    }
}

struct PlainCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var model: PlainModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Menu("New") {
                Button("Spreadsheet") { make(.spreadsheet) }
                Button("Document") { make(.document) }
                Button("Presentation") { make(.presentation) }
            }
            Button("Open…") { open() }
                .keyboardShortcut("o")
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model?.undo() }
                .keyboardShortcut("z")
                .disabled(model?.canUndo != true)
            Button("Redo") { model?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(model?.canRedo != true)
        }

        CommandGroup(after: .toolbar) {
            Button("Find…") { NotificationCenter.default.post(name: .plainFind, object: nil) }
                .keyboardShortcut("f")
            Button("Find and replace…") { NotificationCenter.default.post(name: .plainReplace, object: nil) }
                .keyboardShortcut("f", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { model?.save() }
                .keyboardShortcut("s")
                .disabled(model?.dirty != true)
            Divider()
            Button("Check this file comes back byte for byte") { model?.checkPromise() }
            Button("What this file would carry with it…") {
                NotificationCenter.default.post(name: .plainCarries, object: nil)
            }
            Divider()
            Button("Save as PDF…") { if let model { Files.pdf(model) } }
            Button("Save a copy…") { if let model { Files.saveCopy(model) } }
        }

        CommandMenu("File contents") {
            Button("What else is in this file…") {
                NotificationCenter.default.post(name: .plainInside, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("Word and character count") { model?.perform("count", [:], needsSaveFirst: false) }
            Button("Compare with another version…") {
                NotificationCenter.default.post(name: .plainCompare, object: nil)
            }
            Button("Find in a whole folder…") {
                NotificationCenter.default.post(name: .plainFolder, object: nil)
            }
            Divider()
            Button("Save the sheet as CSV…") { if let model { Files.csv(model) } }
        }

        CommandMenu("Shape") {
            Section("Document") {
                Button("Add a paragraph") { model?.perform("paragraph", ["how": "add", "at": 0]) }
                Button("Add a row to the first table") {
                    model?.perform("tablerow", ["how": "add", "table": 0, "row": 0])
                }
                Button("Take a row out of the first table") {
                    model?.perform("tablerow", ["how": "remove", "table": 0, "row": 0])
                }
                Button("Change the page header…") {
                    NotificationCenter.default.post(name: .plainBand, object: true)
                }
                Button("Change the page footer…") {
                    NotificationCenter.default.post(name: .plainBand, object: false)
                }
                Button("Put a picture in…") { if let model { Files.picture(model) } }
            }
            Section("Presentation") {
                Button("Add a slide") { model?.perform("slide", ["how": "add", "at": 0]) }
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

        CommandGroup(replacing: .appInfo) {
            Button("About Plain for Mac") { NotificationCenter.default.post(name: .plainAbout, object: nil) }
            Button("Check for a newer version now") {
                Task { @MainActor in
                    Updates.lastCheck = nil
                    Updates.skippedVersion = nil
                    await Updates.checkIfDue()
                    if AppState.shared.newVersion == nil {
                        model?.said = "This is the newest version there is."
                    }
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

    /// Several files at once, each in its own window, which is the point of doing it this way.
    @MainActor
    private func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Files.opens
        panel.allowsMultipleSelection = true
        panel.message = "Open a Word, Excel or PowerPoint file"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { openWindow(value: url.path) }
    }

    @MainActor
    private func make(_ kind: Files.Kind) {
        guard let path = Files.chooseNew(kind) else { return }
        do {
            _ = try Engine.make(path)
            openWindow(value: path)
        } catch {
            NSAlert(error: error as NSError).runModal()
        }
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


/// Catching the files a Mac asks the app to open, however they arrive.
///
/// There are three ways in and which one is used depends on how the app was started, so all three are answered
/// and they all end in the same queue. The event handler is the one that matters at a cold start.
enum Opening {
    @MainActor
    static func listen() {
        NSAppleEventManager.shared().setEventHandler(
            Catcher.shared,
            andSelector: #selector(Catcher.opened(_:reply:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments))
    }

    final class Catcher: NSObject {
        static let shared = Catcher()

        @objc func opened(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
            guard let list = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
            var paths: [String] = []
            for i in 1...max(1, list.numberOfItems) {
                guard let item = list.atIndex(i) else { continue }
                // A file arrives as an alias or as a URL depending on who is asking.
                if let url = item.fileURLValue { paths.append(url.path) }
                else if let text = item.stringValue, text.hasPrefix("file://"),
                        let url = URL(string: text) { paths.append(url.path) }
            }
            guard !paths.isEmpty else { return }
            Task { @MainActor in AppState.shared.waiting.append(contentsOf: paths) }
        }
    }
}



