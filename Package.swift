// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "KanbeiAgentCore",
  defaultLocalization: "en",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "KanbeiAgentCore", targets: ["KanbeiAgentCore"]),
  ],
  targets: [
    .target(
      name: "KanbeiAgentCore",
      path: "Sources/KanbeiAgentCore",
      resources: [.process("Resources")]
    ),
  ]
)
