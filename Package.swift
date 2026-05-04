// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ghostbar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Ghostbar",
            path: "Sources/Veil",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
