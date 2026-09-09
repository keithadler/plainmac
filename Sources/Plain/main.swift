//  Plain for Mac — MIT licensed. See LICENSE.

import Foundation

// Until the window is written, the command-line face is the whole program.
@MainActor
func start() {
    CLI.runIfRequested()
    CLI.out(CLI.usage)
    exit(0)
}

MainActor.assumeIsolated { start() }
