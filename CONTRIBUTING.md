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

### The accessibility audit's one retry

The system's accessibility audit sometimes times out without reporting an issue, so the audit test retries once. The retry is not silent: the test records every audit and every retry, and each full-suite CI run shows both counts in its summary.

- The window is the 20 most recent full-suite runs, the current one included.
- A run fails when it retried and the window then holds more than 3 retries. A run that did not retry passes whatever the count, and its summary carries a warning while the count is over.
- A run whose UI tests recorded no audits fails, because the recording is broken. If the earlier records cannot be read, the run passes and its summary says the count is unknown.
- When this check fails, open an issue and find out why the audit is timing out. Do not simply re-run.
- The numbers are `WINDOW` and `THRESHOLD` in `scripts/accessibility-retries.py`. Change them there and in this section together; `scripts/test-accessibility-retries.sh` fails when the two disagree.
- The weekly macOS 15 run shows its own counts. They are not gated and do not count toward the window.

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
- **Light tier**, on a push to any other branch: `bootstrap`, `lint`, `build` and `test`. If the branch already has an open pull request that GitHub reports as mergeable at the pushed commit, the push runs only a short Linux job that finds it, because the pull-request run covers the commit. The light tier runs when the pull request has a merge conflict, because GitHub then starts no pull-request run, and whenever the lookup fails or gets no clear answer after a short wait.

A change that touches only documents (`*.md`, `plans/`, `docs/`) starts no macOS run. The **Documents** workflow checks it on Linux instead: the governance check, and the comparison of the retry numbers in this file with the tool. A push is judged by the commits pushed, but a pull request is judged by its whole diff, so a docs-only commit added to a pull request that also changes code still runs.

A pull request needs a green **Build and test** check.

### What a run costs

The repository is private, and GitHub counts a macOS minute ten times and rounds each job up to a whole minute. Measured on 2026-10-10, with 16 end-to-end tests:

| Run | Job time | Billed minutes |
| --- | --- | --- |
| Full: a pull request or a push to `main` | about 7 min 10 s to 7 min 25 s | 80 |
| Light: a push to a branch with no pull request | about 2 min | 30, plus 1 for the lookup |
| A push to a branch with a mergeable pull request | 5 s on Linux | 1 |
| A docs-only change | under 1 min on Linux | 1 |
| macOS 15 by hand, every end-to-end test | 4 min 40 s to 5 min 2 s | 50 to 60 |
| macOS 15 weekly, unit tests and the accessibility end-to-end tests | 2 min 38 s | 30, about 130 a month |

The full run grew from 50 to 60 billed minutes to 80 when the end-to-end suite went from 8 tests to 16; each test launches the app. The light figure was measured on 2026-10-09 and has not been measured again.

GitHub's published allowance for the free plan is 2,000 minutes a month, which is about 25 full runs at 80. Every run prints its duration and its billed minutes in its last step and in the run summary. The printed time starts at the job's first step, so the bill can be one minute, ten billed minutes, more than the printed figure.

The weekly macOS 15 run is trimmed to the unit tests and the accessibility end-to-end tests (`make uitest UITEST_SUITE=audits`), to keep it under about 300 billed minutes a month. Its last step prints its monthly figure and raises a warning when that passes about 300. Started by hand (`gh workflow run macos-15.yml --ref <branch>`), the workflow runs every end-to-end test.

## Conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
