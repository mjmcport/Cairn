---
title: Accessibility notes
date: 2026-10-09
step: Phase 0 step 10
tags: [accessibility, xcuitest, voiceover]
---

# Accessibility notes

## What we learned

- **`XCUIApplication.performAccessibilityAudit` works on a Mac app** and found two real problems on a three-control screen: low contrast from `secondaryLabelColor` on a message, and "--" as spoken text.
- **The audit's "human-readable" check rejects file names.** `alpha.txt` is flagged. The handler passed to `performAccessibilityAudit` can inspect `issue.auditType` and `issue.element` and return `true` to accept a finding; keep each exception as narrow as the element type and content allow.
- **The audit reports the Touch Bar** even on a Mac without one.
- **`issue.detailedDescription` prints the element's subtree and its path from the window.** That is how the flagged cell was identified; `compactDescription` alone ("Label not human-readable on Cell") was not enough.
- **A fixed accessibility label hides changing text.** A cell or status line must keep speaking its content, so those views get an identifier only. Set a label only to replace content that is not words.
- **UI tests can import BrowserUI** to share identifier constants. The test bundle links the package; the app under test is still a separate process.
- **A table cache reuse identifier is not an accessibility identifier**, but `NSUserInterfaceItemIdentifier("...")` looks the same to a grep. The convention check allows the `rawValue:` spelling for reuse identifiers.

## Known flake

`performAccessibilityAudit` failed with "Audit failed to complete in time" (code -56) once, and ran four times slower once, in roughly ten runs of the empty-folder screen. It was not reproducible in isolation (7 of 7 passes). The test announces the timeout as an XCTest activity and retries once. If CI shows a second timeout, quarantine the test and open an issue rather than adding retries.

Since the Phase 0 follow-up the retry is counted. The test records every audit and every retry through `AuditLog` (TestSupport), `scripts/accessibility-retries.py` puts the counts in each full-suite run's summary, and a run fails when it retried and the last 20 full-suite runs then hold more than 3 retries. The rule and what to do when it fails are in `CONTRIBUTING.md`. The retry rate on the CI runner is not yet known, so the threshold is a starting value. No retry has been seen on CI yet, so the retry line has only been exercised by the unit tests.

## What to carry forward

- Every new control: declare an `AccessibilityElement`, apply it, and add the screen to the audit tests if it is a new screen.
- Prefer `labelColor` for text that carries information; check anything dimmer with the audit.

## Added after step 12: the audit differs between macOS versions

The audit passed on the development Mac (macOS 27) and failed on the CI runner (macOS 26) with "Parent/Child mismatch" on an unnamed group. `detailedDescription` printed no element path on the runner until the handler printed `element.debugDescription`, which showed the group sits inside the window's zoom button (`_XCUI:FullScreenWindow`): system window chrome, not app code.

- The audit now skips that finding only for a group whose frame lies inside one of the window's own title-bar buttons.
- **The step 10 and step 11 commits are red on `main` for this reason.** The UI suite was run locally before each push, but CI's result was not checked before the next step was pushed.
- Check CI after every push, not only at the end. An accessibility audit is a test of the operating system's own controls as well as the app's, so it must pass on every macOS version CI runs.
- To see what an audit finding refers to on CI, print `issue.element?.debugDescription`.
