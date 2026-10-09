// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FileOperations",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "FileOperations", targets: ["FileOperations"])
  ],
  dependencies: [
    .package(path: "../FileSystemCore"),
    .package(path: "../TestSupport"),
  ],
  targets: [
    .target(
      name: "FileOperations",
      dependencies: [
        .product(name: "FileSystemCore", package: "FileSystemCore")
      ]
    ),
    .testTarget(
      name: "FileOperationsTests",
      dependencies: [
        "FileOperations",
        .product(name: "TestSupport", package: "TestSupport"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
