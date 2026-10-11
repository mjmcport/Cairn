# Performance baseline

`baseline.json` holds the measurements that later work is compared against. It was recorded on 2026-10-11 on a MacBook Air (Mac16,13, Apple M4, 10 cores, 16 GB) running macOS 27.0, from the `make perf` run that first met the 200 ms target.

| Measurement | 10,000 items | 100,000 items |
| --- | --- | --- |
| List a folder with prefetched name, kind, hidden flag, size and modified date | 0.054 s | 0.594 s |
| Sort by name, as Finder orders names | 0.026 s | 0.348 s |
| Read five detail keys per item (created, added, allocated size, tags, content type) | 0.368 s | 4.458 s |
| Time to first rows in the app (`FirstRows` signpost, debug build) | 0.026 s | not measured |

The first baseline, recorded on 2026-10-09 before Phase 1A step 3, had the sort at 0.144 s and 1.985 s, and 0.266 s for the whole load (`LoadFolder`) under the time-to-first-rows test. Step 3 made the sort read each name once and made the app's test measure the `FirstRows` interval, so those two rows are not comparable with the old ones.

Two figures in this recording were noisy: the 100,000-item listing (0.594 s, 15% relative standard deviation; it was 0.502 s in the first baseline and the listing code did not change) and time to first rows (0.026 s, 14%; slowest iteration 0.031 s).

## What the baseline says

- **Time to first rows is 0.026 s for 10,000 items, inside quality bar 4's 200 ms target.** Before Phase 1A step 3 the app listed and sorted the whole folder before it showed anything, and the whole load took 0.266 s. Now it shows the first 2,000 items as soon as they have been read and sorts the folder in the background.
- **Sorting used to cost more than listing.** Finder-style name comparison took almost three times as long as reading the folder, because each comparison rebuilt both names from their URLs. Since step 3 the sort reads each name once and costs about half of the listing.
- **Detail metadata must stay lazy.** Reading it for every item costs about ten times as much as the listing, so it belongs in Get Info and visible rows only.

## Running

```sh
make perf            # measure and compare with baseline.json
make perf-baseline   # measure and replace baseline.json
```

`make perf` reports any measurement more than 25% slower than the baseline. It does not fail the build yet; `scripts/performance.py compare --strict` does.

## The target

`targets.json` holds one target, from quality bar 4: the first rows of a 10,000-item folder within 200 ms. It names the test (`PerformanceTests.testTimeToFirstRows10000`), the metric the test must have been measured with (`Duration (FirstRows)`), and the limit.

`make perf` judges it on the reference Mac only, which is a Mac whose model identifier equals the baseline's (`Mac16,13`). There it fails, without `--strict`, when the average of the five iterations is above the limit, when the test was not measured, or when it was measured from another interval. It prints the slowest iteration beside the average. On any other Mac, CI included, the line ends "not judged" and the exit status does not change. A targets file that names no target is an error.

The 100,000-item case has no target. The first rows are the first 2,000 items read, whatever the folder's size, and a unit test proves that without a clock; `testList100000` and `testSortByName100000` measure what does grow.

Times from another Mac are not comparable with this file, so `compare` shows them without judging them. That includes CI: the GitHub runner (VirtualMac2,1) is 40% to 85% slower than the reference Mac on listing and sorting. CI proves the performance tests still run and posts the table in the run summary. Record a new baseline when the reference machine changes, and say so in the commit.

## How it works

- `Packages/FileSystemCore/Tests/FileSystemCorePerformanceTests` holds the XCTest `measure` tests. They run from a release build, five iterations each.
- `UITests/PerformanceTests.swift` measures the app's own `FirstRows` signpost interval with `XCTOSSignpostMetric`, so the figure excludes XCUITest's overhead. The interval runs from the request to load until the list has been given its first rows. The app's `LoadFolder` interval, the whole load, is there for Instruments and is not measured by a test.
- `scripts/performance.py` parses the "measured" lines XCTest prints, compares the averages and judges the targets.
