# Architecture

Cairn is an AppKit app built from five Swift packages. The rule that shapes everything: **only the top two layers touch AppKit, so the core stays testable without a window.**

## Layers

```
App target      Windows, menus, launch, diagnostics subscriber
    │
BrowserUI       Panes, the file list, models that drive the views
    │                                          ── AppKit boundary ──
    ├── FileOperations     Copy, move, trash, rename, undo        (stub)
    ├── FileMetadata       Sizes, dates, tags, ACLs, cloud state  (stub)
    │         │
    └── FileSystemCore     Items, listing, sorting, logging, the main-thread guard

TestSupport     Fixture-tree builder; used by every test target, depends on nothing
```

An arrow means "depends on". `BrowserUI` also uses `FileSystemCore` directly. Nothing below the boundary imports AppKit, SwiftUI or Cocoa; `scripts/check-appkit-boundary.sh` enforces that.

| Module | Responsibility | May import |
| --- | --- | --- |
| `App/` | Entry point, main menu, the window, MetricKit subscriber | AppKit, MetricKit, BrowserUI, FileSystemCore |
| `BrowserUI` | `BrowserModel` (state of one browser), `BrowserHistory` (its back and forward places, with the selection left at each), `BrowserViewController` (the list), `BrowserToolbar` (the Back and Forward buttons), `AccessibilityElement`, `InitialLocation` | AppKit, the three core packages |
| `FileOperations` | `FileOperation` today; the operation engine in Phase 1 | Foundation, FileSystemCore |
| `FileMetadata` | `MetadataGroup` today; Get Info readers in Phase 1 | Foundation, FileSystemCore |
| `FileSystemCore` | `FileItem`, `DirectoryReader`, `FileItemSort`, `MainThreadGuard`, `Log`, `LocalDiagnosticsStore` | Foundation, os |
| `TestSupport` | `FixtureTree`, `FixtureNode`, `FixtureNames`, `TemporaryDirectory` | Foundation |

## How a folder gets on screen

1. `AppDelegate` resolves the launch folder (`-OpenFolder <path>`, else the home folder) and gives the window a `BrowserViewController`.
2. The controller owns a `BrowserModel` on the main actor. A user action that loads a folder goes through `run`, which cancels the previous action's task and starts a new one. A command that cannot do anything, such as Back with no history or Enclosing Folder at the root, never reaches `run`, so a load under way is left to finish.
3. `BrowserModel.load()` awaits `DirectoryReader.items(in:)`. That function is nonisolated and async, so it leaves the main actor. It enumerates the folder with the listing's resource keys prefetched and checks for cancellation every 256 items.
4. Back on the main actor, the model filters hidden items, sorts, and calls `onChange`. The controller reloads the table.
5. A load counter in the model discards a slow result for a folder the user has already left.
6. Every move to another folder is recorded in the model's `BrowserHistory` with the selection being left, so Back and Forward restore it. Places are compared by the text of their paths, and a selection is matched to the listed items by name; neither touches the disk.

The whole load is wrapped in a `LoadFolder` signpost interval, which the performance test measures.

## Rules the code enforces on itself

| Rule | Enforced by |
| --- | --- |
| No file-system call on the main thread | `MainThreadGuard.assertOffMainThread()` at each entry point; unit tests prove each guard fires; `scripts/check-main-thread-guard.sh` |
| Core packages never import a UI framework | Package manifests; `scripts/check-appkit-boundary.sh` |
| No networking code | `scripts/check-no-network.sh` |
| Every control has an identifier and a spoken label | `AccessibilityElement` and `apply(_:)`; `scripts/check-accessibility.sh`; the accessibility audit in the UI suite |
| Swift 6, complete concurrency checking, warnings as errors | `project.yml`, package manifests |
| One code style | `.swift-format`, `make lint`, the pre-commit hook |
| Build settings match the decisions | `scripts/check-project-spec.sh` |

## Testing

| Kind | Framework | Where | Run with |
| --- | --- | --- | --- |
| Unit | Swift Testing | `Packages/*/Tests/*Tests` | `make test` |
| Repository checks | Shell | `scripts/check-*.sh`, `scripts/test-*.sh` | `make test` |
| End-to-end | XCUITest | `UITests/` | `make uitest` |
| Performance | XCTest `measure` | `Packages/FileSystemCore/Tests/FileSystemCorePerformanceTests`, `UITests/PerformanceTests.swift` | `make perf` |

Tests build real folder trees with `FixtureTree` in the temporary directory and read results back with system calls. They never touch a real user folder.

## Build

`project.yml` is the source of truth; XcodeGen turns it into `Cairn.xcodeproj`, which is not committed. The `Makefile` wraps every task and sets `DEVELOPER_DIR` itself, so it does not depend on `xcode-select`. CI runs the same `make` tasks.

## Decisions

Each decision that shaped this structure has a record in [`docs/adr`](docs/adr):

1. [AppKit for the interface](docs/adr/0001-appkit-for-the-interface.md)
2. [XcodeGen for the project file](docs/adr/0002-xcodegen-for-the-project-file.md)
3. [MIT license with clean-room rules](docs/adr/0003-mit-license-with-clean-room-rules.md)
4. [Minimum macOS 15](docs/adr/0004-minimum-macos-15.md)
5. [Distribution outside the App Store](docs/adr/0005-distribution-outside-the-app-store.md)
6. [No telemetry](docs/adr/0006-no-telemetry.md)

## What is not here yet

Phase 0 is a skeleton. Tabs, the sidebar, icon and column views, live updates, Get Info, file operations, undo, state restoration, signing and updates all arrive in Phase 1. The plan is the Claude Doc "Mac file manager implementation plan".
