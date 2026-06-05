// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kairu",
    platforms: [.macOS(.v14)],
    targets: [
        // テスト可能な純粋ロジック（UI 非依存）
        .target(name: "KairuCore"),
        // GUI 実行ファイル（AppKit / SwiftUI）
        .executableTarget(
            name: "Kairu",
            dependencies: ["KairuCore"]),
        // ロジックのユニットテスト
        .testTarget(
            name: "KairuCoreTests",
            dependencies: ["KairuCore"]),
    ]
)
