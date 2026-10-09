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

## What to carry forward

- Every new control: declare an `AccessibilityElement`, apply it, and add the screen to the audit tests if it is a new screen.
- Prefer `labelColor` for text that carries information; check anything dimmer with the audit.
