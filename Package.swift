// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Megaprompter",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "megaprompt", targets: ["Megaprompter"]),
    .executable(name: "megadiagnose", targets: ["MegaDiagnose"]),
    .executable(name: "megatest", targets: ["MegaTest"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1")
  ],
  targets: [
    // Core libraries
    .target(
      name: "MegaprompterCore"
    ),
    .target(
      name: "MegaDiagnoserCore",
      dependencies: [
        "MegaprompterCore"
      ]
    ),
    .target(
      name: "MegaTesterCore",
      dependencies: [
        "MegaprompterCore"
      ]
    ),

    // Executables
    .executableTarget(
      name: "Megaprompter",
      dependencies: [
        "MegaprompterCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),
    .executableTarget(
      name: "MegaDiagnose",
      dependencies: [
        "MegaDiagnoserCore",
        "MegaprompterCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),
    .executableTarget(
      name: "MegaTest",
      dependencies: [
        "MegaTesterCore",
        "MegaprompterCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),

    // Tests
    .testTarget(
      name: "MegaprompterTests",
      dependencies: ["MegaprompterCore"],
      path: "Tests/MegaprompterTests"
    ),
    .testTarget(
      name: "MegaDiagnoserCoreTests",
      dependencies: ["MegaDiagnoserCore"]
    ),
    .testTarget(
      name: "MegaTesterCoreTests",
      dependencies: ["MegaTesterCore"]
    ),
    // New: end-to-end regression tests for MegaTest
    .testTarget(
      name: "MegaTestRegressionTests",
      dependencies: ["MegaTesterCore", "MegaprompterCore", "MegaTest"],
      path: "Tests/MegaTestRegressionTests"
    )
  ]
)

