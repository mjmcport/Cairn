# test: Phase 0 step 7, performance baseline

Date: 2026-10-09

Record how fast the walking skeleton is on large folders, so every later change can be compared with a number instead of a feeling.

## Acceptance criteria

- [x] XCTest performance tests for listing 10,000- and 100,000-item folders
- [x] XCTest performance tests for loading detail metadata on both folders
- [x] XCTest performance tests for sorting both folders by name
- [x] A UI test that measures time to first rows in a 10,000-item folder
- [x] `docs/performance/baseline.json` committed, with the machine it was recorded on
- [x] `make perf` measures and compares with the baseline; `make perf-baseline` replaces it
- [x] `make test` and `make uitest` skip the performance tests

## Tests

- [x] `scripts/test-performance.sh`: parsing XCTest output, rejecting an empty log, threshold handling, strict and non-strict regressions, a measurement that disappeared
- [x] The performance tests themselves assert the item counts they measured

## Design notes

- Xcode stores performance baselines inside the project file, which this repository generates and does not commit. The baseline is therefore a JSON file compared by `scripts/performance.py`.
- The app marks each folder load with an `os_signpost` interval named `LoadFolder`. The UI test measures that interval, which excludes XCUITest's own delays and also shows up in Instruments.
- Unit performance tests use a release build. The UI figure comes from the debug app, because the UI-test scheme builds Debug.
- Regressions are reported, not blocking, until step 9 puts them in CI and the numbers have proved stable.

## Result

See `docs/performance/README.md`. Time to first rows is 0.266 s for 10,000 items, above the 200 ms target that applies from Phase 1.

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 7 and quality bar 4
