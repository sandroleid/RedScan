// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RedScan",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "RedScan", path: "Sources/RedScan")
    ]
)
