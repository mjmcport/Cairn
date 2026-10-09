# ci: Phase 0 step 9, continuous integration

Date: 2026-10-09

Run every check on GitHub for each push and pull request, so a failing change is visible before it reaches `main`.

## Acceptance criteria

- [x] `.github/workflows/ci.yml` runs on every push to `main` and every pull request, on the Apple Silicon `macos-26` runner
- [x] Steps: select Xcode, bootstrap, format check, build, unit tests, UI tests, performance tests
- [x] Performance tests are reported in the run summary and do not block
- [x] Test results are uploaded when a run fails
- [x] `scripts/ci-select-xcode.sh` picks the pinned Xcode, else the newest of the same major version, else the default
- [ ] **Branch protection on `main`: not possible yet.** GitHub refuses it on a private repository on the free plan ("Upgrade to GitHub Pro or make this repository public"). `scripts/protect-main.sh` applies it in one command once either changes.

## Tests

- [x] Trial pull request #1: all steps green in 5 min 13 s (run 37983298650), using Xcode 26.6 on the runner
- [x] Deliberately failing pull request #2: a failing unit test turned the **Build and test** check red and skipped the later steps (run 37983923434)
- [ ] **The failing pull request was not blocked from merging.** GitHub reported it as `MERGEABLE` with state `UNSTABLE`, because blocking needs branch protection. This half of the plan's test stays open with the item above.
- [x] `scripts/test-ci-select-xcode.sh`: the three selection cases
- [x] `scripts/test-performance.sh`: times from a different Mac are shown, not judged

## Design notes

- CI calls the same `make` tasks a developer runs, so there is one definition of "passing".
- `scripts/protect-main.sh` requires the **Build and test** check and refuses force pushes and deletion. It leaves administrators able to push directly, which the one-commit-per-step workflow uses.
- The first comparison on the runner marked five measurements as regressions purely because the runner is slower. `performance.py compare` now judges only runs from the same Mac model as the baseline.
- A run takes about 5 minutes. GitHub bills macOS minutes at ten times the Linux rate against a private repository's allowance, so one run uses about 50 of the free plan's 2,000 monthly minutes.

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 9
