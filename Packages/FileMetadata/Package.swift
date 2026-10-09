// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FileMetadata",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "FileMetadata", targets: ["FileMetadata"])
  ],
  dependencies: [
    .package(path: "../FileSystemCore"),
    .package(path: "../TestSupport"),
  ],
  targets: [
    .target(
      name: "FileMetadata",
      dependencies: [
        .product(name: "FileSystemCore", package: "FileSystemCore")
      ]
    ),
    .testTarget(
      name: "FileMetadataTests",
      dependencies: [
        "FileMetadata",
        .product(name: "TestSupport", package: "TestSupport"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
