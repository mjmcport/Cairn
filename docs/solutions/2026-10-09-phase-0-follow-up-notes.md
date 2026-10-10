---
title: Phase 0 follow-up notes
date: 2026-10-09
step: Phase 0 follow-up
tags: [ci, github-actions, verification, accessibility]
---

# Phase 0 follow-up notes

Written before any of this ran on CI. Measured durations and anything the runs teach belong in a later note.

## What we learned

- **An "expect an error" case passes against a tool that is not there.** The first self-test for `scripts/ci-duration.sh` only asked for a non-zero exit and no output, and three of its cases were green before the script existed (exit 127). An error case now asserts the exit status and a phrase from the message. Run a new self-test once before the tool exists and read which cases pass.
- **Billing rounds up, so the limit is crossed a minute early.** A weekly run of 6 minutes costs 60 billed minutes, about 260 a month. At 6 minutes 1 second it is 70 a run and about 303 a month. The warning in `ci-duration.sh --weekly` is therefore tied to the monthly figure, not to a 7-minute mark.
- **Workflow steps can be dry-run locally.** Loading the workflow with PyYAML, writing a step's `run` text to a file and running it with `bash -e` and a fake `gh` first on `PATH` exercised the pull-request lookup and the audit-history download, including a failed listing and a failed download. It does not prove expressions, `if:` conditions, permissions or the real API's answers.
- **A step that must report on a failed test needs its own condition.** A plain step is skipped once an earlier one fails. The audit summary runs when the UI-test step's outcome is `success` or `failure`, so a retry in a failed run is still shown, and never when that step was skipped.
- **Job-level `permissions` replace the workflow's, they do not add to them.** The build job lists `contents: read` again beside `actions: read`.

## What to carry forward

- Unproved until the first runs: the `**.md` path filter, the job condition that lets the build run when the lookup job is skipped, whether the UI test process can write to `build/accessibility/`, and whether the `macos-15` runner has an Xcode 26 that compiles the code.
- If the UI tests are green on CI but the audit summary says the recording is broken, the test process could not write the log. Look at the test bundle's sandbox settings before anything else.
