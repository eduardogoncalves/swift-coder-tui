// swift-tools-version: 6.3.1
import PackageDescription

let package = Package(
    name: "swift-coder-tui",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SwiftCoderTUI", targets: ["SwiftCoderTUI"]),
        .executable(name: "Example", targets: ["Example"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "SwiftCoderTUI",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/SwiftCoderTUI"
        ),
        .executableTarget(
            name: "Example",
            dependencies: ["SwiftCoderTUI"],
            path: "Example/Sources"
        ),
        .testTarget(
            name: "SwiftCoderTUITests",
            dependencies: ["SwiftCoderTUI"],
            path: "Tests/SwiftCoderTUITests"
        ),
        .testTarget(
            name: "ExampleTests",
            dependencies: ["Example", "SwiftCoderTUI"],
            path: "Tests/ExampleTests"
        ),
    ]
)
