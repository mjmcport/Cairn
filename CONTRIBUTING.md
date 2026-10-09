# Contributing to Cairn

Thank you for helping. These rules keep Cairn safe to use and legally clean. A pull request that breaks one of them will not be merged.

## Clean-room rule

Cairn is MIT licensed, and every line in it must be compatible with that.

- Do not copy, translate or adapt code from GPL, LGPL or AGPL projects. **Nimble Commander is GPL-3**, so its source is off limits, including as a reference while you write.
- Do not copy code or assets from closed-source apps such as Path Finder, ForkLift, QSpace, Commander One or Marta, and do not reverse-engineer them.
- You may study how any app behaves as a user, and you may read Apple's documentation and headers.
- If you have read the source of a GPL file manager recently, say so in your pull request and avoid the area you read.

## Dependencies

- Allowed licences: MIT, BSD (2- or 3-clause), Apache-2.0 and zlib.
- Open an issue before you add a dependency. Name the library, its licence and the licence of anything it bundles.
- Prefer Apple's frameworks over a third-party library when both do the job.

## Tests are required

- Every change ships with its tests in the same commit. A change without tests is incomplete.
- Unit tests use Swift Testing. Performance tests use XCTest. End-to-end tests use XCUITest.
- A change that touches the app's interface needs an end-to-end test.
- Tests may read and write only temporary fixture folders. They must never touch Desktop, Documents or any other real user folder.
- A flaky test gets an issue and is quarantined. Do not retry it silently.

## Commits

- One commit per step of the plan, with code, tests and docs together.
- Name the phase and step in the message, for example `Phase 0 step 3: package skeletons`.
- Keep `main` buildable at every commit.

## Code rules

- Swift 6 with strict concurrency checking. Do not silence a concurrency warning with `@unchecked Sendable` or `nonisolated(unsafe)` without a comment that explains why it is safe.
- No file-system call may run on the main thread. Every function that touches the file system starts with `MainThreadGuard.assertOffMainThread()`, and its tests prove the guard fires.
- Log through the categories in `Log`. Never mark a path or file name `.public`.
- The core packages (`FileSystemCore`, `FileMetadata`, `FileOperations`) never import AppKit. Only `BrowserUI` and the app target do.
- The minimum macOS is 15. Use a newer API only behind `#available`, with a fallback that works on macOS 15.
- Every control needs an accessibility label and an accessibility identifier.
- No telemetry, and no networking code outside the update checker.

## Before you open a pull request

1. Run `scripts/check-governance.sh`.
2. Run `make test` and `make uitest` (available from Phase 0 step 2).
3. Fill in the pull-request template.

## Conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
