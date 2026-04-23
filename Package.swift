// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OllamaChat",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OllamaChat",
            path: "Sources/OllamaChat"
        )
    ]
)
