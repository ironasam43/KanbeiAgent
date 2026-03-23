// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "KanbeiAgentCore",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "KanbeiAgentCore", targets: ["KanbeiAgentCore"]),
  ],
  targets: [
    .target(
      name: "KanbeiAgentCore",
      path: "Sources/KanbeiAgentCore"
    ),
  ]
)
