// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lurkr",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Lurkr"),
    ]
)
