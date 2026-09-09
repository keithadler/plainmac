//  Plain for Mac — MIT licensed. See LICENSE.
//
//  The pictures in the README, rendered from demo files rather than photographed off somebody's screen.
//
//  Doing it this way means the pictures cannot quietly go stale, cannot contain anybody's real documents, and can
//  be looked at as part of checking a change. The content is invented: Pine Street Holdings, Sam Rivera,
//  Woodland Ave.

import SwiftUI
import AppKit

enum Screenshots {

    @MainActor
    static func render(to dir: String, announce: Bool) -> Int32 {
        let folder = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        guard let demo = demoFolder() else {
            CLI.err("no demo files: expected docs/demo beside the app or in PLAIN_DEMO")
            return 2
        }

        var wrote = 0
        for (name, file) in [("book", "quarter.xlsx"), ("doc", "review.docx"), ("deck", "woodland.pptx")] {
            let path = demo.appendingPathComponent(file).path
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let model = PlainModel()
            model.open(path)
            guard model.failed == nil else {
                CLI.err("\(file): \(model.failed ?? "")")
                return 2
            }

            // A real window, not ImageRenderer: that cannot draw a ScrollView, a Menu or a Picker, and renders
            // them as an empty space and a yellow "not allowed" box. What is wanted is a picture of the app as it
            // actually is, so the app is actually put on screen and photographed.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Plain for Mac"
            window.contentView = NSHostingView(rootView: MainView()
                .environmentObject(model)
                .frame(width: 1180, height: 720))
            window.center()
            window.makeKeyAndOrderFront(nil)
            settle()

            let out = folder.appendingPathComponent("\(name).png")
            do { _ = try capture(window, to: out) }
            catch { CLI.err("\(out.path): could not photograph the window"); return 2 }
            window.orderOut(nil)

            CLI.out("wrote \(out.path)")
            wrote += 1
        }

        // One more picture: the window when the daily check has found a newer version. It is a state nobody sees
        // on demand, so it is rendered deliberately rather than waited for.
        do {
            let model = PlainModel()
            model.open(demo.appendingPathComponent("quarter.xlsx").path)
            model.newVersion = (version: "1.1.0", page: URL(string: "https://example.invalid/r")!)

            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Plain for Mac"
            window.contentView = NSHostingView(rootView: MainView()
                .environmentObject(model)
                .frame(width: 1180, height: 720))
            window.center()
            window.makeKeyAndOrderFront(nil)
            settle()
            let out = folder.appendingPathComponent("update.png")
            if (try? capture(window, to: out)) != nil { CLI.out("wrote \(out.path)"); wrote += 1 }
            window.orderOut(nil)
        }

        if announce {
            CLI.err("promo cards are not written yet")
            return 2
        }
        return wrote > 0 ? 0 : 2
    }

    /// The demo files, beside the app when installed or in the repo when developing.
    private static func demoFolder() -> URL? {
        if let set = ProcessInfo.processInfo.environment["PLAIN_DEMO"] { return URL(fileURLWithPath: set) }

        var here = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0..<8 {
            here.deleteLastPathComponent()
            let candidate = here.appendingPathComponent("docs/demo")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("quarter.xlsx").path) {
                return candidate
            }
        }
        return nil
    }

    /// Let the window finish laying itself out before it is photographed.
    @MainActor
    private static func settle() {
        let until = Date().addingTimeInterval(0.8)
        while Date() < until { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    }

    @MainActor
    private static func capture(_ window: NSWindow, to url: URL) throws -> URL {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else {
            throw NSError(domain: "shots", code: 1)
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        guard let image = fn(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 4)?.takeRetainedValue() else {
            throw NSError(domain: "shots", code: 2)
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "shots", code: 3) }
        try png.write(to: url)
        return url
    }
}
