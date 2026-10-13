---
title: Column view: a selection is a request to the model, and a description lives in more than one place
date: 2026-10-13
category: solutions
module: BrowserUI
problem_type: best_practice
component: ColumnBrowserController, PreviewViewController
severity: medium
applies_when:
  - An older AppKit control has to follow a model that also changes without it
  - A control's own selection and the model's selection must stay one thing
  - An image has to pass the accessibility audit
tags: [nsbrowser, swift-concurrency, main-actor, accessibility, previews]
---

# Column view: a selection is a request to the model, and a description lives in more than one place

## Context

Step 7 added the third presentation: View > as Columns (Command-3) shows the folder as an `NSBrowser` with a preview. The plan is `plans/phase-1a-step-07-column-view.md`.

## Guidance

- **The model already held the path.** The tree of open folders that the outline needed (step 5) is the chain of columns: column 0 is the folder, and each next column is the open folder selected in the one before it. The only new model rule is `pruneOpenFolders(keepingPathTo:)` for the switch, which keeps the folders that lead to the selection and closes the rest.
- **Make the control's selection a request, and draw the model's answer.** The person selects in a column; the controller opens the folders on the path and closes the others in the model, sets the model's selection, and shows the preview. The publishes that come back from that request are not drawn as if they were changes made elsewhere: a flag (`isApplying`) covers them. The test that removes the flag does not fail an assertion, it kills the test process (a reload and a selection feeding each other). The listing of a newly opened folder arrives later, and that publish is drawn: only that folder's column is reloaded.
- **Probe the old control before building on it.** An item-based `NSBrowser` is lazy: the first column of 100,000 items asked the delegate for no children until they were drawn, a folder selection took 1.4 ms, a reload of a column was free, and a preview callback came with every leaf selection. A first column of 100,000 items took 36 ms to appear in a debug build, which is two frames once.
- **A description lives in more than one place.** The audit flagged an image whose view had the label "Preview of inner.txt" with "Image has no label". It reads an image's description from the image (`NSImage.accessibilityDescription`), not from the view that shows it. The picture is copied, so the shared cached icon is not changed, and the copy is given the description. The icon cell of step 6 did the opposite: it hid its picture from assistive technology, because the cell speaks for itself. Whether a picture is decoration or the point decides which.
- **Name the parts a system control makes.** The browser's column lists are `NSBrowserTableView`s with no description, and the audit reports a list with none. The controller finds the table views in the browser after each reload and names each by its place ("Column 1", "Column 2") through an `AccessibilityElement`.
- **XCUITest sees an `NSBrowser` as a `browser` whose entries are text fields.** There are no static texts, rows or cells: an entry is `textFields` with its name as its value, found by a `value == name` predicate.
- **Leave the control's keyboard to it.** Right and Left move between columns and select, Up and Down move within one, typing selects through `typeSelectStringForRow`, and a double-click is the control's `doubleAction`. None of it needed help.

## What was measured

Reference Mac, macOS 27, Debug test builds.

- **A column of 100,000 items:** first column 36 ms (1,000 items: 2 ms); selecting a folder 1.4 ms; selecting a file 0.8 ms; selecting the middle row 0.9 ms.
- **First rows of the 10,000-item folder:** 0.026 s, unchanged (target 0.2 s). `docs/performance/baseline.json` was not re-recorded.
- **End to end:** `make uitest` 34 tests, 0 failures, including four launches of the columns and the audit with the columns and a preview showing.

## The plan's Open Questions

1. *Does an item-based `NSBrowser` ask lazily and reload one column at a time?* Yes to both (above).
2. *How is it seen by XCUITest and the audit?* As a `browser`; entries are text fields; its lists needed names (above).
3. *What does a column of 100,000 items cost?* 36 ms once to appear, then about a millisecond per selection.
4. *Is the preview controller recreated or reused?* The browser asks for it on every leaf selection; handing back the same controller, which is configured each time, works.
5. *Do Left and Right move between columns, and does typing select?* Yes, by the control (the end-to-end test presses them).
6. *What does VoiceOver say?* **Not listened to.** The facts are words, the columns and the picture have names, and the audit passes.

## What is not done

- The VoiceOver checks of steps 4 to 7.
- Column widths that are remembered, and a size for the preview: step 10's.
- A look at a folder of real photographs by eye. The preview uses the icon view's pipeline, which was probed with 601 photographs in step 6.

## Related

- `docs/solutions/2026-10-13-icon-view-notes.md`
- `docs/solutions/2026-10-12-list-view-notes.md`
- `docs/solutions/2026-10-09-accessibility-notes.md`
