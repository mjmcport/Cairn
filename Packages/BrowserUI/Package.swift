// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "BrowserUI",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "BrowserUI", targets: ["BrowserUI"])
  ],
  dependencies: [
    .package(path: "../FileMetadata"),
    .package(path: "../FileOperations"),
    .package(path: "../FileSystemCore"),
    .package(path: "../TestSupport"),
  ],
  targets: [
    .target(
      name: "BrowserUI",
      dependencies: [
        .product(name: "FileSystemCore", package: "FileSystemCore"),
        .product(name: "FileMetadata", package: "FileMetadata"),
        .product(name: "FileOperations", package: "FileOperations"),
      ]
    ),
    .testTarget(
      name: "BrowserUITests",
      dependencies: [
        "BrowserUI",
        .product(name: "TestSupport", package: "TestSupport"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
