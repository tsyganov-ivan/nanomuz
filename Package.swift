// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nanomuz",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "Nanomuz",
            path: "Sources"
        ),
        .testTarget(
            name: "NanomuzTests",
            path: "Tests"
        )
    ]
)
