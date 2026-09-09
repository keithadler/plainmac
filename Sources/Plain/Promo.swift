//  Plain for Mac — MIT licensed. See LICENSE.
//
//  The four cards that go with the announcement, 1600×900 at 2×. They are rendered from the same demo files as
//  the screenshots, so what a card shows is the app actually running rather than a mock-up of it.

import AppKit
import SwiftUI

enum Promo {
    @MainActor
    static func render(to dir: URL, screenshots: URL) throws -> [URL] {
        let out = dir.appendingPathComponent("promo")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let cards: [(String, String, String, String?)] = [
            ("1-hero",
             "Open the file.\nGive back the same file.",
             "Word, Excel and PowerPoint documents, edited where you need to edit them and left alone everywhere "
             + "else. Free, open source, and it never phones home.",
             "book.png"),
            ("2-preserved",
             "13 parts read.\n13 kept byte for byte.",
             "Every editor rewrites what it does not understand. Plain writes back the parts it did not edit as "
             + "the exact bytes it found, and counts them at the bottom of the window.",
             "doc.png"),
            ("3-carries",
             "It tells you what\nit cannot draw.",
             "Charts, macros, tracked changes, comments, headers. The panel names everything the file carries "
             + "that Plain will not show you — and keeps all of it.",
             "panel-carries.png"),
            ("4-both",
             "Mac and Windows.\nOne engine, not two opinions.",
             "Free, MIT licensed, no account and no cloud. The part that understands the file format is the "
             + "same code on both, compiled native — so the two agree by construction.\n\n"
             + "plainmac roundtrip ~/Documents/*.docx",
             nil),
        ]

        var written: [URL] = []
        for (name, title, sub, shot) in cards {
            let picture = shot.flatMap { NSImage(contentsOf: screenshots.appendingPathComponent($0)) }
            let view = Card(title: title, subtitle: sub, image: picture)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 1600, height: 900)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            Screenshots.settle()
            written.append(try Screenshots.capture(window, to: out.appendingPathComponent("\(name).png")))
            window.orderOut(nil)
        }
        return written
    }

    struct Card: View {
        let title: String, subtitle: String, image: NSImage?

        var body: some View {
            ZStack {
                // Paper and ink: the colours of the thing the app is about.
                LinearGradient(colors: [Color(red: 0.10, green: 0.13, blue: 0.20),
                                        Color(red: 0.18, green: 0.28, blue: 0.44)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").font(.system(size: 34))
                            Text("Plain for Mac").font(.system(size: 30, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.85))

                        Text(title)
                            .font(.system(size: image == nil ? 60 : 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: image == nil ? 1300 : 620, alignment: .leading)

                    if let image {
                        Image(nsImage: image)
                            .resizable().aspectRatio(contentMode: .fit).frame(width: 820)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(radius: 30, y: 12)
                    }
                }
                .padding(80)
            }
            .frame(width: 1600, height: 900)
        }
    }
}
