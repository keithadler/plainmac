// swift-tools-version: 5.9
import PackageDescription
import Foundation

// The engine is a native library built from the same C# as Plain for Windows. engine/build.sh makes it, and
// build-app.sh runs that first, so a clean clone builds with one command.
let engine = Context.packageDirectory + "/engine/out"

let package = Package(
    name: "Plain",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CPlainEngine", path: "Sources/CPlainEngine"),
        .executableTarget(
            name: "Plain",
            dependencies: ["CPlainEngine"],
            path: "Sources/Plain",
            linkerSettings: [
                .unsafeFlags([
                    "-L", engine, "-lPlainEngine",
                    // Found beside the executable in the app bundle, and in engine/out while developing.
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
                    "-Xlinker", "-rpath", "-Xlinker", engine,
                ])
            ]
        ),
        .testTarget(name: "PlainTests", dependencies: ["Plain"], path: "Tests/PlainTests"),
    ]
)
