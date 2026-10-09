# Performance baseline

`baseline.json` holds the measurements that later work is compared against. It was recorded on 2026-10-09 on a MacBook Air (Mac16,13, Apple M4, 10 cores, 16 GB) running macOS 27.0.

| Measurement | 10,000 items | 100,000 items |
| --- | --- | --- |
| List a folder with prefetched name, kind, hidden flag, size and modified date | 0.054 s | 0.502 s |
| Sort by name, as Finder orders names | 0.144 s | 1.985 s |
| Read five detail keys per item (created, added, allocated size, tags, content type) | 0.428 s | 5.405 s |
| Time to first rows in the app (`LoadFolder` signpost, debug build) | 0.266 s | not measured |

## What the baseline says

- **Time to first rows is 0.266 s for 10,000 items, above quality bar 4's 200 ms target.** The app lists and sorts the whole folder before it shows anything. Phase 1 must deliver the first batch of rows before the full sort finishes.
- **Sorting costs more than listing.** Finder-style name comparison takes almost three times as long as reading the folder. A cheaper comparison (precomputed sort keys) is the first thing to try.
- **Detail metadata must stay lazy.** Reading it for every item costs about ten times as much as the listing, so it belongs in Get Info and visible rows only.

## Running

```sh
make perf            # measure and compare with baseline.json
make perf-baseline   # measure and replace baseline.json
```

`make perf` reports any measurement more than 25% slower than the baseline. It does not fail the build yet; `scripts/performance.py compare --strict` does.

Times from another Mac are not comparable with this file. Record a new baseline when the reference machine changes, and say so in the commit.

## How it works

- `Packages/FileSystemCore/Tests/FileSystemCorePerformanceTests` holds the XCTest `measure` tests. They run from a release build, five iterations each.
- `UITests/PerformanceTests.swift` measures the app's own `LoadFolder` signpost interval with `XCTOSSignpostMetric`, so the figure excludes XCUITest's overhead.
- `scripts/performance.py` parses the "measured" lines XCTest prints and compares the averages.
