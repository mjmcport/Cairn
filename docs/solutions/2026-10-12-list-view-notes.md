---
title: List view: an outline is a tree of arrivals, and a test that shares a main actor measures its neighbours
date: 2026-10-12
category: solutions
module: BrowserUI, FileSystemCore
problem_type: best_practice
component: BrowserModel, BrowserViewController, FolderKey
severity: medium
applies_when:
  - A list that was flat gains a second level that is listed, watched and selected on its own
  - A test asserts on a clock inside a package whose suites run in parallel on one main actor
  - A SwiftUI view is hosted in an AppKit window and has to pass the accessibility audit
tags: [nsoutlineview, swift-concurrency, main-actor, testing, accessibility, swiftui, performance]
---

# List view: an outline is a tree of arrivals, and a test that shares a main actor measures its neighbours

## Context

Step 5 replaced the table with an `NSOutlineView`. A folder in the list opens in place, is watched like the top level, and sorts with it. Columns gained Size on Disk and Date Added, headers sort, View > Keep Folders on Top groups folders, typing selects, and Back and Forward open again the folders that were open in the place returned to, under a setting. The plan is `plans/phase-1a-step-05-list-view.md`.

## Guidance

- **Key the tree by names, not by URLs.** A location under `/var` lists its items under `/private/var`, so a URL cannot name a row. A `FolderKey` is the names from the folder shown down to a folder, and a selection is looked up three ways in order: the item's own URL, the path below the location as spelled or below the folder the listing followed, and only for a URL outside both a top-level item of the same name. The third rule stays because Enclosing Folder selects the folder just left by a URL from outside the listing; a wanted path that is *below* either root and does not resolve must not fall through to it, or a vanished `Sub/x.txt` selects a top-level `x.txt`.
- **A second level is a second arrival under the same rules, not a second pipeline.** Each open folder has its own token beside the load counter; every listing and refresh checks both and its cancellation after each wait, and reads the counter without changing it. A close cancels the folder's task, so the token alone is redundant for a close; it is kept because a relisting after a reload is not preceded by a close.
- **One answerer, many watches.** One FSEvents stream per open folder feeds one dirty set and one task that looks at folders one at a time, shallowest first. A signal for a folder that is being listed, or that arrives during a load, is set aside and paid with one refresh when that settles. A folder that a reload lists again must have its owed signal *dropped*, not merely excluded from payment: its own relisting paid it a second time and listed the folder three times where two were right.
- **AppKit asks for handles lazily.** An `NSOutlineView` does not ask for the item of every row. A folder row far down a list may never have been requested, so a cache of handles has nothing for it, and "open the folders the model says are open" silently did nothing for the last of 301 rows. The controller makes the handle from the model when it is missing, and `expandItem` accepts it. A handle is an `NSObject` whose `isEqual` and `hash` are its key, which is what keeps a folder open across a reload.
- **An outline posts its own notifications.** Selection changes arrive as `NSOutlineView.selectionDidChangeNotification`, not the table's. A test that counted the table's saw none and failed in a way that read as a behavior change.
- **A test that waits on a stub must have a bound.** The stub watcher's wait for a stream to end and the answered-signals wait were unbounded, so a deliberate break hung the run and held the SwiftPM lock for 20 minutes behind it. Both now poll with a ten-second bound and record an issue. A mutation harness needs a hard timeout too, and a mutation that does not compile prints an empty result that looks like "nothing failed".
- **Count outstanding work instead of keeping tasks.** `waitForOpenFolders()` waits until a counter of started-and-not-ended listings reaches zero, retired ones included. It needs no list of tasks and holds nothing in production.
- **A timing test shares its main actor with every other suite in the package.** `LiveUpdateTests` read 0.011 to 0.14 s alone and 0.014 s with `--no-parallel`, 0.47 to 0.85 s in the parallel run without the outline suites, and 1.2 to 3.1 s with them: it was measuring how busy the neighbours kept the main actor. `make test` now runs the suites named in `TIMING_SUITES` alone, after the rest. The bound stayed at one second.
- **SwiftUI's accessibility tree is not there until something asks.** An in-process search of a hosted view for the checkbox found nothing; XCUITest finds it by identifier and by title. A hosting view needs a description of its own (`hosting.view.apply(...)`): the audit reported the unnamed outer group, not the SwiftUI content. `XCUIApplication` is the only thing that can be audited, so the Settings audit closes the main window first: it overlaps Settings and is drawn dimmer behind it, which the whole-app audit reports as a contrast failure.
- **A launch argument is not a setting to flip back.** The UI tests change a real preference of the real app, because the bundle id is shared. The test that clears the checkbox restores it in a teardown block, and ends by setting it again.

## What was measured

Reference Mac, macOS 27, Debug test builds unless noted.

- **The two new resource keys.** Listing 10,000 items went from 0.053 s to 0.059 s and 100,000 from 0.510 s to 0.561 s with `.totalFileAllocatedSizeKey` and `.addedToDirectoryDateKey` read in the listing. First rows of the 10,000-item folder: 0.027 s, 0.029 s with the real outline (baseline 0.026 s, target 0.2 s). `docs/performance/baseline.json` was not re-recorded.
- **`NSOutlineView` reloads (kept as `OutlineBehaviorTests`).** A root `reloadData()` with row count, layout and display took 2.4 to 7.5 ms at 100,000 top-level rows; the scroll offset and first responder were kept, and a folder stayed open when the new handle was equal to the old. A per-folder `reloadItem` took about 3 to 11 ms and the selection followed its item.
- **Opening a folder in place, off the main actor.** 10,000 items: 0.12 s, with the longest gap the main actor was away from a 1 ms ticker 2 ms. 100,000 items: 1.3 s, longest gap 0.25 to 0.30 s. A process sample taken during the 100,000-item open found the main thread idle in its run loop (941 samples) and busy only with the test's own fixture cleanup, so the gap is not app code on the main actor. It was not explained further: the likeliest reading is scheduling latency while every core lists and sorts. Moving the release of the listing array off the main actor made no difference and was reverted.
- **A change inside an open folder** showed in that folder's rows in 14 ms to 0.20 s over ten real-stream runs, with the selection and the open state kept.
- **End to end.** `make uitest`: 23 tests. Everything in `ListViewTests` and the new audits passes. `testAuditPassesOnAPopulatedFolder` fails in full runs, see below.

## The plan's Open Questions

1. *Do the two keys cost first rows?* No: about +5 ms listing 10,000 items, first rows within the baseline's noise.
2. *Cost and behavior of an outline reload at 100,000 rows?* Under one frame; offset, focus and open folders kept (above).
3. *Does `outlineView(_:typeSelectStringFor:item:)` apply?* In the running app on macOS 27, typing `be` selected `beta.txt`. macOS 15 and 26 are covered by the CI run and the manual macOS 15 run before the merge.
4. *How does `XCUIApplication` see the outline?* As an `outline`, with `outlineRows`, `disclosureTriangles` and header `buttons`. `tables` is empty.
5. *Is a SwiftUI checkbox found by identifier?* Yes, by identifier and by title, with value 1 for on. The hosting view had to be named for the audit.
6. *What does VoiceOver say for a row's level and state, and when a folder opens?* **Not answered.** The VoiceOver checks were skipped again. They remain open with step 4's.

## What the CI runners showed, and what was done about it

The first pull request run failed on both macOS 26 and macOS 15, deterministically, in three ways. Each one was a different cause.

- **A column hanging out of the window.** Date Added was flagged for contrast. The five columns were 930 points wide in a 900-point window: the last one ran about 30 points past the edge and the list grew a horizontal scroller. A probe of the running app measured it. My Mac's audit tolerated it; the runners did not. The columns now fit with room to spare, Name takes any width the window gains, and a unit test (which fails on the old widths) and an end-to-end assertion keep it that way.
- **A trap on macOS 15 only.** The BrowserUI unit tests died with `Index out of range`. The model empties its rows at a move and does not publish until the listing starts, and an `NSOutlineView` keeps the counts it was given and asks for rows later. The table had asked the data source for its live count every time. The commands now reload the outline at the move, and the data source answers an index beyond the rows with an empty row that cannot be selected. Two tests pin both. macOS 27 and 26 never asked late; macOS 15 did.
- **A contrast failure on `Empty`.** Two audits failed on both runners with "Contrast failed for Empty". The runner's recording showed dark text on white, and a color histogram of the failing element's screenshot (put in the failure message for this) showed text pixels at `#272727` on `#FFFFFF`, about 14.6:1 where 4.5:1 is asked, and few full-strength ink pixels because the glyphs are thin on a 1x screen. The system's estimate of the text color is an average that anti-aliasing pulls lighter. The same word passed on these runners before the outline, and that was not explained. The audit handler now re-measures contrast for a flagged static text from the element's own screenshot (its most contrasting pixel against its most common) and accepts it at 4.5:1 or more; text that is really too light still fails because its strongest pixel is light. This was chosen by the user over investigating further or merging red.

## A pre-existing audit flake on the development Mac

`testAuditPassesOnAPopulatedFolder` fails in full end-to-end runs on the macOS 27 development Mac with "Contrast failed" on one name (`Empty`, `beta.txt`), and `testAuditPassesWithTwoTabs` once on a size (`Zero kB`). It is not from the outline: `main`, with the table, failed the same audit in 2 of 2 full runs, and this branch failed one audit in 3 of 4 full runs and in none of 6 runs of the accessibility suite alone. CI on macOS 26 passed the audit at the step 4 merge. It was recorded and not fixed (chosen by the user); `docs/solutions/2026-10-09-accessibility-notes.md` already says contrast depends on where the stripes fall.

## What is not done

- The VoiceOver checks of steps 4 and 5.
- The by-hand check that a 100,000-item folder opens while the window answers a click. The process sample and the 2 ms gap at 10,000 items are what there is.
- Per-window or per-tab settings: the setting is global.

## Related

- `docs/solutions/2026-10-11-live-updates-notes.md`
- `docs/solutions/2026-10-10-a-load-that-publishes-twice.md`
- `docs/solutions/2026-10-10-check-then-act-across-a-task-boundary.md`
- `docs/solutions/2026-10-09-navigation-history-notes.md`
- `docs/solutions/2026-10-09-accessibility-notes.md`
