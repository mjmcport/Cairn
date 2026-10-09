# 4. Minimum macOS 15

- Status: Accepted
- Date: 2026-10-09

## Context

The plan first assumed macOS 14. A lower floor reaches more Macs; a higher one removes availability checks and allows newer AppKit and Swift concurrency APIs. Cairn supports Apple Silicon only, and every Apple Silicon Mac can run macOS 15.

## Decision

The minimum is **macOS 15 Sequoia**. Features from macOS 26 or later are adopted behind `#available`, each with a fallback that works on macOS 15. The floor is never raised for a single feature.

## Consequences

- The Observation framework and macOS 15 AppKit APIs are used with no guards.
- No Apple Silicon Mac is excluded by the operating-system requirement.
- Every use of a newer API costs a fallback path and a test on both sides of the check.
- Raising the floor later is easy; lowering it would not be.

## Alternatives considered

- **macOS 14.** ForkLift 4 requires 14.6; it would add users on Macs that could update anyway, at the cost of guards.
- **macOS 26 only.** The newest APIs with no fallbacks, but it would exclude anyone who has not updated.
