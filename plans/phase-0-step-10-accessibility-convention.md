# feat: Phase 0 step 10, accessibility convention

Date: 2026-10-09

Make accessibility part of how a control is created (quality bar 9), and have the system's own audit check every screen in the end-to-end suite.

## Acceptance criteria

- [x] `AccessibilityElement` pairs a stable identifier with a spoken label; every element is declared in one catalog
- [x] `view.apply(_:)` sets the view identifier, the accessibility identifier and the label together; `applyIdentifier(of:)` is for views whose spoken text is their changing content; `window.apply(_:)` identifies a window
- [x] The app and BrowserUI set accessibility only through these helpers
- [x] UI tests find elements through the same catalog, so a renamed identifier cannot drift from its tests
- [x] The system accessibility audit runs in the UI suite on three screens: a populated folder, an empty folder and a folder that cannot be listed
- [x] A folder can be opened and left with the keyboard alone

## Tests

- [x] Unit: identifiers are unique, lowercase and hyphenated; every label is non-empty; `apply` sets all three properties; every identified view in the browser is declared in the catalog
- [x] `scripts/check-accessibility.sh` fails on a direct `setAccessibilityIdentifier`, `setAccessibilityLabel` or literal view identifier outside the helper file (tested in `scripts/test-source-checks.sh`)
- [x] End-to-end: the audit on three screens; keyboard-only navigation with the arrow keys, Command-O and Command-Up

## What the audit found

| Finding | Fix |
| --- | --- |
| The status message ("This folder is empty.") nearly failed contrast | It now uses the primary label color instead of the secondary one |
| Dashes shown for a folder's missing size and date are not words | VoiceOver now says "No size" and "No date" for those cells |
| "Label not human-readable" on a cell showing `alpha.txt` | Accepted: a file name is the user's data and the right thing to speak. The audit skips this finding only for list cells that show text |
| "Element has no description" on the Touch Bar | Accepted: the system owns that element and the app does not populate it |

## Known issue

The audit timed out once in about ten runs ("Audit failed to complete in time") without reporting a finding. The test announces the timeout and retries once; a second timeout fails. See `docs/solutions/2026-10-09-accessibility-notes.md`.

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 10 and quality bar 9
