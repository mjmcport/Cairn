---
title: Performance baseline notes
date: 2026-10-09
step: Phase 0 step 7
tags: [performance, xctest, signpost]
---

# Performance baseline notes

## What we learned

- **Sorting is the bottleneck, not listing.** For 10,000 items the listing takes 54 ms and `localizedStandardCompare` sorting takes 144 ms; at 100,000 items, 0.5 s against 2.0 s.
- **`XCTOSSignpostMetric` measures an interval inside the app from a UI test.** Begin and end an `OSSignposter` interval in the app, then pass the same subsystem, category and name to the metric. With `.manuallyStart` and `.manuallyStop`, only the navigation under test is counted.
- **XCTest `measure` blocks run on the main thread.** Calling a guarded file-system function there trips `MainThreadGuard`. The tests run the work in a detached task and wait on an expectation.
- **`Result` has no async-closure initializer.** Use `do`/`catch` to capture an async result.
- **XCTest prints one parseable line per `measure` block**: `Test Case '-[Module.Suite test]' measured [Metric, unit] average: N, relative standard deviation: N%, values: [...]`. The same format comes from `swift test` and `xcodebuild`.
- **Relative standard deviation was under 5% on every measurement**, so a 25% regression threshold leaves a wide margin on this Mac. CI runners are noisier.

## What to carry forward

- Phase 1's first-rows work should precompute sort keys or sort in batches, and measure against `testTimeToFirstRows10000`.
- A new performance test needs no registration: `make perf` picks up any `measure` block in the two performance test locations.
- Record a new baseline only on the reference Mac, and name the reason in the commit.
