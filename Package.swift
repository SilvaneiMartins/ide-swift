// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ide-swift",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ide-swift", targets: ["ide-swiftApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        .executableTarget(
            name: "ide-swiftApp",
            dependencies: ["DesignSystem", "EditorCore", "ProjectModel", "Shell"],
            path: "Sources/ide-swiftApp"
        ),
        .target(name: "DesignSystem", path: "Sources/DesignSystem"),
        .target(
            name: "EditorCore",
            dependencies: ["DesignSystem", "SyntaxHighlight"],
            path: "Sources/EditorCore"
        ),
        .target(
            name: "SyntaxHighlight",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            path: "Sources/SyntaxHighlight"
        ),
        .target(
            name: "LSPClient",
            dependencies: [],
            path: "Sources/LSPClient"
        ),
        .target(
            name: "ProjectModel",
            dependencies: [],
            path: "Sources/ProjectModel"
        ),
        .target(
            name: "Shell",
            dependencies: ["DesignSystem", "EditorCore", "ProjectModel", "SyntaxHighlight"],
            path: "Sources/Shell"
        ),
        .testTarget(
            name: "EditorCoreTests",
            dependencies: ["EditorCore"],
            path: "Tests/EditorCoreTests"
        ),
        .testTarget(
            name: "SyntaxHighlightTests",
            dependencies: ["SyntaxHighlight"],
            path: "Tests/SyntaxHighlightTests"
        ),
        .testTarget(
            name: "LSPClientTests",
            dependencies: ["LSPClient"],
            path: "Tests/LSPClientTests"
        ),
        .testTarget(
            name: "ShellTests",
            dependencies: ["Shell"],
            path: "Tests/ShellTests"
        ),
        .testTarget(
            name: "ProjectModelTests",
            dependencies: ["ProjectModel"],
            path: "Tests/ProjectModelTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
