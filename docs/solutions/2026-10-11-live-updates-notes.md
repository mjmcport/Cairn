---
title: Live updates: a refresh is a third arrival, and a watch is only as safe as its last callback
date: 2026-10-11
category: solutions
module: BrowserUI, FileSystemCore
problem_type: best_practice
component: FolderWatcher, BrowserModel
severity: medium
applies_when:
  - A folder on screen has to follow changes made by other processes
  - A C callback API (FSEvents) hands work back to Swift concurrency
  - A test needs a real FSEvents stream, or a clock-based bound
tags: [fsevents, swift-concurrency, main-actor, testing, performance]
---

# Live updates: a refresh is a third arrival, and a watch is only as safe as its last callback

## Context

Step 4 keeps the list of the folder on screen in step with the disk. One FSEvents stream per watched folder (`FolderWatcher`) hands "look again" signals to `BrowserModel`, which answers each with a whole-folder refresh that runs off the main actor and publishes only when the visible rows changed. The plan is `plans/phase-1a-step-04-live-updates.md`. This note records what the work taught that the plan did not already say.

## Guidance

- **A refresh reads the load counter and never changes it.** Step 3 named live updates as the third way for rows to arrive. The answer to "a change arrives for a folder the user just left" is the same as for a load: capture `generation` when the refresh starts, check it (with the session id and cancellation) after every wait. A move or a load bumps the counter and retires the refresh; a refresh can never retire a load. A signal that arrives while a load is in flight is set aside and paid with one refresh when the load settles, so the first rows are never replaced.
- **Give the C API ownership of the callback's `info`, not a promise.** The first version passed the watch to FSEvents with `passUnretained` and relied on `stop()` running on the stream's queue before the owner let go. A callback FSEvents queued at the same moment as `stop()` could still run after the watch was freed. The stream context's `retain` and `release` callbacks make FSEvents hold the watch for as long as the stream exists, and the stream's release is what frees it.

```swift
FSEventStreamContext(
  version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
  retain: { info in /* retain the watch */ },
  release: { info in /* release the watch */ },
  copyDescription: nil)
```

- **A test of a real stream has to wait for quiet, not only for "live".** A new stream can deliver events from just before it started, such as the ones that built the fixture. A test that waits only for the "live" signal can then be satisfied by a stale event, and a timing assertion measures nothing. `LiveUpdateTests.watchingModel(on:)` waits until the session has been silent for one second before it touches the disk. The tests assert that a signal arrives, never how many.
- **A refresh that finds nothing new publishes nothing.** The comparison of the sorted result with the rows shown runs off the main actor (`FileItemSort`), and a refresh that is equal publishes no table reload and nothing for VoiceOver. The table is still reloaded whole when something did change, which keeps the scroll offset and focus (step 3's probe) and which step 5 replaces with an outline view.

## Why This Matters

Each of these fails silently. A refresh that resets the load counter cancels a navigation with no error. A callback that outlives its watch is a crash that depends on timing. A timing test that passes on a stale event shows a number that is not the thing it claims to measure.

## What was measured

- **The one-second bound.** `LiveUpdateTests` (a 100-file folder, the real reader and the real watcher) saw a new file in the list between 0.001 s and 0.61 s after it was created, over about a dozen runs on the development Mac (macOS 27); runs after the quiet wait (below) read 0.015 s to 0.31 s. The spread fits FSEvents flushing on its own 0.3 s tick, not a fixed delay after the first event, and the earliest readings may have been answered by a stale event. Every run was inside the bound, with at least 0.39 s to spare on a small folder.
- **First rows.** `make perf` on the reference Mac, with the app watching its folder, reported the 200 ms target met both times: 0.024 s (baseline 0.026 s), then 0.033 s. The second run had a load average above 11 from background daemons (`duetexpertd`, `fileproviderd`, other apps) and flagged +27 % against the baseline. The first run flagged six Phase 0 listing benchmarks at +98 % to +226 %, including `testDetailMetadata`, which this step does not touch; a second run, a minute later, had all six within ±15 %. A performance run on a busy Mac is not a measurement: check `uptime` first and repeat before believing a regression. `docs/performance/baseline.json` was not re-recorded.
- **End to end.** `make uitest`: 18 tests, 0 failures, including `testChangesMadeByAnotherProcessShowInTheListAndKeepTheSelection` and the extended tab test.

## The plan's Open Questions

1. *Does a stream keep reporting after its folder is deleted and created again?* The watcher does not rely on it. On a root-changed event it ends the stream and starts a new one on the same location, then signals (`startAfresh`). Two tests cover the result: a file created after the folder came back brings a signal, and so does one created when the folder was deleted and created again at once. I did not separately record what a single plain stream does.
2. *Is a change made straight after the "live" signal always delivered?* In every run recorded here, yes (`aFileCreatedStraightAfterTheWatchIsLiveBringsASignal`, ten runs in a row, then more through the suite). The stop condition for unstable FSEvents tests did not fire.
3. *Does AppKit send `viewDidDisappear` when the window closes?* On macOS 27 yes: the pane test that orders a window front and closes it sees the stream end without a call by hand. The pane does not listen for the window's will-close notification. macOS 15 and 26 are covered by the CI run and the manual macOS 15 run before the merge.
4. *What does VoiceOver say when the item under its cursor is deleted, or the folder goes away?* **Not answered.** The VoiceOver checks of U5 (expectations 1 to 4, observations 5 and 6, and the check step 3 postponed, 7) were skipped on 2026-10-11 at the user's request. They remain open, and the curriculum page should say so. The R14 requirement (no announcement for a refresh, the selection not read again) is designed for and not verified.

## Related

- `docs/solutions/2026-10-10-a-load-that-publishes-twice.md`
- `docs/solutions/2026-10-10-check-then-act-across-a-task-boundary.md`
- `docs/solutions/2026-10-09-main-thread-guard-notes.md`
- `docs/solutions/2026-10-09-performance-baseline-notes.md`
- `docs/solutions/2026-10-09-checks-that-pass-without-checking.md`
