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
- From Phase 1, changes arrive by pull request and merge only on a green **Build and test** check.

## Code rules

- Format with Apple's swift-format and the committed `.swift-format`: two-space indentation, 100-column lines. `try!` is not allowed.
- Swift 6 with strict concurrency checking. Do not silence a concurrency warning with `@unchecked Sendable` or `nonisolated(unsafe)` without a comment that explains why it is safe.
- No file-system call may run on the main thread. Every function that touches the file system starts with `MainThreadGuard.assertOffMainThread()`, and its tests prove the guard fires.
- Log through the categories in `Log`. Never mark a path or file name `.public`.
- The core packages (`FileSystemCore`, `FileMetadata`, `FileOperations`) never import AppKit. Only `BrowserUI` and the app target do.
- The minimum macOS is 15. Use a newer API only behind `#available`, with a fallback that works on macOS 15.
- Every control needs an accessibility label and an accessibility identifier. Declare an `AccessibilityElement` and call `apply(_:)`; do not call `setAccessibilityIdentifier` or `setAccessibilityLabel` directly. A new screen gets an accessibility-audit test.
- No telemetry, and no networking code outside the update checker.

## Before you open a pull request

1. Run `make bootstrap` once. It enables the pre-commit hook, which refuses unformatted Swift.
2. Run `make format`, then `make lint`.
3. Run `make test` and `make uitest`.
4. Fill in the pull-request template.

CI runs the same `make` tasks, in two tiers:

- **Full tier**, on every pull request and every push to `main`: `bootstrap`, `lint`, `build`, `test`, `uitest` and `perf`.
- **Light tier**, on a push to any other branch: `bootstrap`, `lint`, `build` and `test`. If the branch already has an open pull request, the push runs only a short Linux job that finds it, because the pull-request run covers the commit.

A change that touches only documents (`*.md`, `plans/`, `docs/`) starts no run. A push is judged by the commits pushed, but a pull request is judged by its whole diff, so a docs-only commit added to a pull request that also changes code still runs.

A pull request needs a green **Build and test** check.

### What a run costs

The repository is private, and GitHub counts a macOS minute ten times. A full run takes about 5 minutes, so it costs about 50 billed minutes. GitHub's published allowance for the free plan is 2,000 minutes a month, which is about 40 full runs. Every run prints its duration and its billed minutes in its last step and in the run summary.

A second workflow builds and tests on macOS 15, the minimum supported version, once a week. It is expected to take about 6 minutes: 60 billed minutes a run, about 260 a month. Its last step prints that monthly figure and raises a warning when it passes about 300, which one second over 6 minutes does, because billing rounds up to 70 minutes a run and about 303 a month.

## Conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
