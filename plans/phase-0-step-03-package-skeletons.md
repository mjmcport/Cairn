# feat: Phase 0 step 3, package skeletons

Date: 2026-10-09

Create the five packages with stub APIs, so every later step has a place to put code and a test target to put its tests in.

## Acceptance criteria

- [x] `Packages/FileSystemCore`, `FileMetadata`, `FileOperations`, `BrowserUI` and `TestSupport`, each with its own `Package.swift` (tools 6.0, Swift 6 language mode, macOS 15)
- [x] Each package has a Swift Testing target with at least one passing test
- [x] Dependencies follow the architecture: `BrowserUI` depends on the three core packages; `FileMetadata` and `FileOperations` depend on `FileSystemCore`; `TestSupport` depends on nothing and serves every test target
- [x] The app target links `BrowserUI` and hosts a `BrowserViewController`
- [x] `make test` runs every package's tests

## Stub APIs

| Package | Stub |
| --- | --- |
| FileSystemCore | `FileItem` (URL, kind, hidden flag, `isNavigable`) |
| FileMetadata | `MetadataGroup` (the Get Info groups, in order), `BasicMetadata` (size, modified date) |
| FileOperations | `FileOperation` (copy, move, trash, rename, new folder; `sources`, `isUndoable`) |
| BrowserUI | `BrowserViewController` (holds a location, loads an identified empty view) |
| TestSupport | `TemporaryDirectory`, `withTemporaryDirectory` |

## The AppKit boundary

SwiftPM cannot forbid an import, so the rule is enforced in two ways:

- The manifests: no core package depends on `BrowserUI`.
- `scripts/check-appkit-boundary.sh`: fails if a core package imports AppKit, SwiftUI, Cocoa or UIKit, or if its manifest names `BrowserUI`. `scripts/test-check-appkit-boundary.sh` tests the check against generated trees, including attributed and scoped imports.

`make test` runs both.

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 3 and the architecture diagram
