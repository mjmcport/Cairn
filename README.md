# Cairn

Cairn is a native file manager for the Mac, written in Swift and AppKit. The goal is a Finder replacement you can trust with your files: it never loses data, never freezes on a large folder, and restores your windows exactly as you left them.

## Status

**Phase 1 (Finder-replacement core) is under way.** Phase 0 is complete. The app opens one window, lists a folder, navigates into subfolders, goes back and forward, and keeps several folders open as tabs. A large folder shows its first rows at once and is sorted in the background. The list follows changes that other apps make to the folder it shows: a file created, renamed, deleted or changed elsewhere appears within a second, and the selection and scroll position stay where they were. It cannot open, copy, move or delete anything yet. This phase built the project skeleton, the test fixtures, continuous integration and a performance baseline. Phase 1 delivers the first build meant for daily use.

To open the app on a folder of your choice after `make build`:

```sh
build/DerivedData/Build/Products/Debug/Cairn.app/Contents/MacOS/Cairn -OpenFolder ~/Documents
```

## Requirements

| | |
| --- | --- |
| macOS | 15 Sequoia or later |
| CPU | Apple Silicon (arm64) only |
| Xcode | 26 or later, with the macOS 26 SDK |
| Swift | 6, with strict concurrency checking |
| XcodeGen | 2.46 or later (`brew install xcodegen`) |

## Building

The Xcode project is generated from `project.yml` by XcodeGen and is not committed.

```sh
git clone https://github.com/mjmcport/Cairn.git
cd Cairn
make             # check the toolchain, generate the project, build and test
```

The individual tasks:

| Task | What it does |
| --- | --- |
| `make bootstrap` | Checks Xcode, its license and components, installs XcodeGen and enables the git hooks |
| `make generate` | Creates `Cairn.xcodeproj` from `project.yml` |
| `make build` | Builds the app |
| `make test` | Runs the unit tests of every package, the script tests and the project-spec checks |
| `make uitest` | Runs the end-to-end tests |
| `make perf` | Runs the performance tests, compares them with `docs/performance/baseline.json` and judges the targets in `docs/performance/targets.json` |
| `make package` | Builds the Release app, zips it into `build/package` and checks the zip |
| `make lint` | Checks the governance files and Swift formatting (strict) |
| `make format` | Reformats every Swift file with the committed `.swift-format` |
| `make clean-clone` | Proves a clean copy builds and tests with one command |

The Makefile uses the Xcode at `/Applications/Xcode.app`. Set `DEVELOPER_DIR` to use another one.

## Privacy

- Cairn collects no telemetry and no analytics.
- Crash and diagnostic reports stay on your Mac unless you choose to share them. They are saved in `~/Library/Application Support/Cairn/Diagnostics`.
- The only network request Cairn will make is the check for app updates, once that feature ships.
- No feature is locked behind a paywall.

## Contributing

[ARCHITECTURE.md](ARCHITECTURE.md) describes how the code is organized, and [docs/adr](docs/adr) records why. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Two rules matter most: every change ships with its tests, and no code may be copied or adapted from GPL or closed-source projects.

Report security problems as described in [SECURITY.md](SECURITY.md).

## License

Cairn is released under the [MIT License](LICENSE).
