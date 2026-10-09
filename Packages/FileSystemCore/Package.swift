// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FileSystemCore",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "FileSystemCore", targets: ["FileSystemCore"])
  ],
  dependencies: [
    .package(path: "../TestSupport")
  ],
  targets: [
    .target(
      name: "FileSystemCore",
      dependencies: []
    ),
    .testTarget(
      name: "FileSystemCoreTests",
      dependencies: [
        "FileSystemCore",
        .product(name: "TestSupport", package: "TestSupport"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
