---
title: Checks that pass without checking anything
date: 2026-10-09
category: solutions
module: scripts and CI
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - Writing or changing a script under scripts/ that enforces a rule
  - Adding a step to .github/workflows that pipes a command into another
  - Writing a self-test for a check script
tags: [ci, shell, verification, silent-pass, github-actions]
---

# Checks that pass without checking anything

## Context

The Phase 0 review found three places where a check reported success because it had looked at nothing. A fourth had already been found by hand in step 12. Each one was a different mechanism with the same shape: the check's input was empty or its exit status was thrown away, and "nothing found" looked the same as "nothing wrong".

| Where | Mechanism |
| --- | --- |
| `check-no-network.sh`, `check-accessibility.sh`, `check-main-thread-guard.sh` | `for file in $(find ...)` split paths on spaces. Under a checkout path containing a space, `grep` was handed fragments that do not exist, counted no failures and exited 0. |
| The CI performance step | `make perf \| tee summary.txt` reported `tee`'s status. A step with no `shell:` key runs as `bash -e` without `pipefail` (per GitHub's documentation; not yet observed failing on a runner), so a failed `make perf` left the step green and the warning step unreachable. |
| `check-main-thread-guard.sh`, `check-appkit-boundary.sh`, the Makefile | Each kept its own hand-written list of packages. A package missing from a list would have been built and tested but never checked. |
| Step 12: tests that copied the repo with `git ls-files` | Outside a git checkout the list was empty, so every "must fail" case passed against an empty tree. See the build artifact notes. |

None of these was caught by the checks' own self-tests, because every self-test ran the check on a tree shaped like the one the author had in mind.

## Guidance

- **Give every check a "must fail" case built the awkward way.** For each rule, the self-test needs a violating tree that the check rejects, placed under a path with a space. `scripts/test-source-checks.sh` now does this for all three source checks.
- **Split file lists on newlines.** In POSIX `sh`, set `IFS` to a newline around a `for file in $(find ...)` loop, as `.githooks/pre-commit` does, or pipe `find` into `while IFS= read -r file`.
- **Keep the left side's status when piping to `tee` in a workflow.** Set `pipefail`, capture the status, write the summary, then exit with the captured status:

  ```sh
  set -o pipefail
  status=0
  make perf | tee build/performance/summary.txt || status=$?
  # ... write the summary ...
  exit "$status"
  ```

- **Derive lists from disk; name only the exceptions.** The guard check scans every folder under `Packages/` except an explicit exemption, the AppKit check fails on a package it has not been told about, and the Makefile builds `PACKAGES` from the manifests present.
- **A check that scans zero files should say so.** This one is still open: the source checks exit 0 when `CAIRN_ROOT` points at the wrong place.

## Why This Matters

A check that cannot fail is worse than no check, because the rule it stands for is listed in `ARCHITECTURE.md` as enforced. The first three mechanisms were found by independent reviewers reading the scripts cold, after self-review by the author had passed all of them.

## When to Apply

- Before trusting a new check: break the rule on purpose and watch the check go red, from a path with a space in it.
- When a CI step is `continue-on-error`: confirm its failure path once with a deliberately failing run, since nothing else will ever show it.

## Related

- `docs/solutions/2026-10-09-build-artifact-notes.md` (the empty-tree copy)
- `docs/solutions/2026-10-09-ci-notes.md`
- `docs/solutions/2026-10-09-main-thread-guard-notes.md` (the guard check is per file, not per function)
