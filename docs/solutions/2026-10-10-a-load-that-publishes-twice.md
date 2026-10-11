---
title: A load that publishes twice has to ask "am I still wanted" at every stage
date: 2026-10-10
category: solutions
module: BrowserUI
problem_type: best_practice
component: BrowserModel
severity: medium
applies_when:
  - A load publishes more than once (first rows, then the sorted list; later, live updates)
  - A consumer reads an AsyncThrowingStream and may be cancelled or superseded part-way
  - A synchronous change of place is followed by a load started in a later turn
tags: [swift-concurrency, asyncstream, cancellation, navigation, main-actor]
---

# A load that publishes twice has to ask "am I still wanted" at every stage

## Context

Until step 3 a folder load published once: list, sort, publish. One check after the single `await` was enough to drop a load the user had moved on from. Step 3 made `BrowserModel.load()` publish twice, first rows and then the sorted list, with two waits in between (the listing stream and the off-main sort). Each new wait is a place where an older load can wake up and write into a folder the user has already left. Three separate things turned out to be needed, and each was found by a test that failed without it.

## Guidance

- **Check after every event of the stream, not only after the loop.** A stream hands an event it has already buffered to a consumer whose task was cancelled a moment ago. Without a check inside the loop, a cancelled load shows its first rows.
- **Check again after the loop.** When the consuming task is cancelled, `for try await` ends normally; it does not throw. A load that only relied on `CancellationError` would carry on as if the listing had finished. The model also treats a stream that ends with no all-items event as an error (`DirectoryReadError.incomplete`), so "ended early" can never look like "empty folder".
- **Retire the old load at the move, not at the next load.** `isStillWanted()` compares a generation counter. The counter used to change only when the next `load()` started, and a command moves the model first and starts the load in a task. In between, the old load was still "current" and could publish the folder just left into the list. `prepareToShow(selecting:)` now bumps the counter, so the move alone retires whatever is in flight.

```swift
func isStillWanted() -> Bool { current == generation && !Task.isCancelled }

for try await event in reader.listing(in: folder) {
  guard isStillWanted() else { return }
  // ...
}
// A cancelled listing ends without throwing.
guard isStillWanted() else { return }
```

## Why This Matters

Every one of these failures is silent. Nothing crashes and no error is logged; the user sees rows from the wrong folder, or a list that flashes and empties. The single-publish load hid all three, because there was only one place to be wrong.

## When to Apply

- Step 4 (live updates) adds a third way for rows to arrive. It needs the same check on every arrival, and its own answer to "a change arrives for a folder the user just left".
- Any test of a staged load: hold it at each stage with a gate, change place, release, and assert that nothing more is published. `BrowserModelTests` does this at the reader and at the sort. No wall-clock waits.

## Examples

`aMoveRetiresTheLoadInFlightBeforeTheNextLoadStarts` holds a load after its first rows, calls `move(to:)` with no load after it, and releases. Before the counter moved into `prepareToShow`, the old load published the first folder's sorted items into the second folder.

## Related

- `docs/solutions/2026-10-10-check-then-act-across-a-task-boundary.md`
- `docs/solutions/2026-10-09-walking-skeleton-notes.md`
- `docs/solutions/2026-10-09-performance-baseline-notes.md`
