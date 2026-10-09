# Cairn

Cairn is a native file manager for the Mac, written in Swift and AppKit. The goal is a Finder replacement you can trust with your files: it never loses data, never freezes on a large folder, and restores your windows exactly as you left them.

## Status

**Phase 0 (foundation).** There is nothing to use yet. This phase builds the project skeleton, the test fixtures, continuous integration and a performance baseline. Phase 1 delivers the first build meant for daily use.

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
| `make bootstrap` | Checks Xcode, its license and components, and installs XcodeGen |
| `make generate` | Creates `Cairn.xcodeproj` from `project.yml` |
| `make build` | Builds the app |
| `make test` | Runs the script tests and the project-spec checks |
| `make uitest` | Runs the end-to-end tests |
| `make lint` | Checks the governance files and Swift formatting |
| `make clean-clone` | Proves a clean copy builds and tests with one command |

The Makefile uses the Xcode at `/Applications/Xcode.app`. Set `DEVELOPER_DIR` to use another one.

## Privacy

- Cairn collects no telemetry and no analytics.
- Crash and diagnostic reports stay on your Mac unless you choose to share them.
- The only network request Cairn will make is the check for app updates, once that feature ships.
- No feature is locked behind a paywall.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Two rules matter most: every change ships with its tests, and no code may be copied or adapted from GPL or closed-source projects.

Report security problems as described in [SECURITY.md](SECURITY.md).

## License

Cairn is released under the [MIT License](LICENSE).
