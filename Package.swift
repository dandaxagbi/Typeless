// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Typeless",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Typeless",
            targets: ["Typeless"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Typeless",
            dependencies: [],
            path: "Sources/Typeless"
        )
    ]
)
