---
title: Main-thread guard notes
date: 2026-10-09
step: Phase 0 step 6
tags: [concurrency, testing, logging, metrickit]
---

# Main-thread guard notes

## What we learned

- **A task-local handler makes a crashing assertion testable.** `@TaskLocal` values are visible to synchronous code called inside the task, including code that hops to the main actor, and are invisible to other tests running in parallel.
- **A wrapper around `TaskLocal.withValue` for async closures must take `isolation: isolated (any Actor)? = #isolation`** and pass it on. Without it, calling the wrapper from a `@MainActor` test fails to compile with "sending value of non-Sendable type".
- **`os.Logger` redacts interpolated strings by default.** That is the behavior we want for paths. Only fixed text, counts and durations are marked `.public`.
- **A grep-based source check needs to skip declarations.** `case rename(item:newName:)` matched the POSIX `rename(` pattern until lines starting with `case`, `func` or `//` were excluded.
- **MetricKit's `MXMetricManagerSubscriber` does not say which thread it calls on.** The subscriber copies the JSON out synchronously and writes it in a detached task.

## What to carry forward

- Every new file-system function: guard first, then a test that calls it on the main actor inside `MainThreadGuard.withHandler` and expects one violation.
- When Phase 1 adds the update checker, add its folder to `allowed_directories` in `scripts/check-no-network.sh` instead of weakening the pattern.
