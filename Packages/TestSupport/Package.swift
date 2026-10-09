// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TestSupport",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "TestSupport", targets: ["TestSupport"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "TestSupport",
      dependencies: []
    ),
    .testTarget(
      name: "TestSupportTests",
      dependencies: [
        "TestSupport"
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
