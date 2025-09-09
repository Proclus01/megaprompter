// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Megaprompter",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "megaprompt", targets: ["Megaprompter"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1")
  ],
  targets: [
    .target(
      name: "MegaprompterCore"
    ),
    .executableTarget(
      name: "Megaprompter",
      dependencies: [
        "MegaprompterCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),
    .testTarget(
      name: "MegaprompterCoreTests",
      dependencies: ["MegaprompterCore"]
    )
  ]
)
