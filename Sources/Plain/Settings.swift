//  Plain for Mac — MIT licensed. See LICENSE.

import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("keepUnsaved") private var keepUnsaved = true
    @AppStorage("showPreserved") private var showPreserved = true

    var body: some View {
        Form {
            Toggle("Show what the file keeps but Plain will not draw", isOn: $showPreserved)
            Text("The rail down the side. It is the point of the program, so it is on by default.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            Toggle("Keep a copy of unsaved work", isOn: $keepUnsaved)
            Text("A copy is kept beside the settings and offered back the next time Plain starts.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            Toggle("Check GitHub once a day for a new version", isOn: $checkForUpdates)
            Text("The only network request Plain makes. It sends nothing about you or your files, downloads "
                 + "nothing and installs nothing. Turn it off and Plain makes no network request at all.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 460)
    }
}

enum Help {
    /// The help page travels inside the app, so it works with no network.
    @MainActor
    static func show() {
        let spanish = Locale.current.language.languageCode?.identifier == "es"
        let name = spanish ? "Help.es" : "Help"
        if let url = Bundle.main.url(forResource: name, withExtension: "html")
            ?? Bundle.main.url(forResource: "Help", withExtension: "html") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/keithadler/plainmac")!)
        }
    }
}
