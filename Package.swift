// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LivePhotoPairer",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "LivePhotoPairer",
            path: "Sources/LivePhotoPairer"
        )
    ]
)
