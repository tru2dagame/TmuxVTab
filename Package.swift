// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TmuxVTab",
  platforms: [.macOS(.v15)],
  targets: [
    .executableTarget(
      name: "TmuxVTab",
      path: "Sources",
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ]
    ),
  ]
)
