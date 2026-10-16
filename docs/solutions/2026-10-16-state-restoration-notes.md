---
title: State restoration: save on change, restore after the window opens, and let the system keep what it already keeps
date: 2026-10-16
category: solutions
module: BrowserUI, FileSystemCore, App
problem_type: best_practice
component: SavedState, StateSaver, RestoredLocation, LaunchRestoration, WindowFrame, AppDelegate
severity: medium
applies_when:
  - Something must survive a quit or a crash
  - A saved place may no longer exist at the next launch
  - A system autosave (window frame, table columns) must be isolated per test
tags: [state-restoration, user-defaults, autosave, debounce, crash]
---

# State restoration: save on change, restore after the window opens, and let the system keep what it already keeps

## Context

Step 10 brings back the window, its tabs, their view mode, sort, hidden files, open folders, selection, history, the sidebar's width and the path bar. The plan is `plans/phase-1a-step-10-state-restoration.md`.

## Guidance

- **Save on change, not at quit.** A crash gives no chance to save. `StateSaver` writes 0.5 s after the last change, or 1 s after the first unsaved one if changes never stop (a drag). Quit flushes. Quit and crash are then one path, and the end-to-end test kills the app after the delay to prove it.
- **One versioned value, one blob.** `SavedState` is a Codable tree written as `Data` to the user defaults: no file, so no file-system call on the main thread. Unknown version or damaged data decodes to nil, a default window opens, and the old blob stays until a good save replaces it.
- **Do not store what the system already keeps, but name it from the suite.** The window frame (`setFrameAutosaveName`) and the list's column widths (`NSTableView.autosaveName`) go to the standard defaults, not to a test's suite. Both names include the `-StateSuite` value, or tests pollute each other and the real app.
- **Open the window first, resolve the place after.** The saved folder may be gone. The window opens at once, the showing tab shows its loading state, `RestoredLocation` checks off the main thread and walks to the nearest folder that exists (or home), and the tab lists once. The missing folder is never listed and there is no second move. Tabs that were not showing resolve when first shown.
- **Until a tab resolves, it saves what it was given.** `captureState` returns the unresolved tab unchanged; otherwise a save during startup would replace the real location with a placeholder. The window does the same for the sidebar width until it is applied.
- **Walk `pathComponents`, never parent URLs.** The macOS 15 hang of step 9 (`deletingLastPathComponent` never reaches a fixed point) is avoided by construction; `RestoredLocation` has a test.

## Probes that changed the design

- **Table autosave.** The key is `NSTableView Columns v3 <name>`, written about 0.3 s after a resize, with a separate "Sort Ordering" key. The test scans the keys rather than hard-coding one. The model's restored sort wins over the autosaved ordering, and a test says so.
- **Frame autosave.** `setFrameAutosaveName` returns whether the name was accepted, not whether a frame was found. Call `setFrameUsingName` first. A frame on no connected screen is moved onto one.
- **The sidebar clamps at the first layout.** The first layout is too narrow for a 260 pt sidebar beside the pane's 400 pt minimum, so the width was clamped and consumed. It is applied on the first layout wide enough, with a fallback when the window appears.

## What the end-to-end tests found

- **A close observer with no window watched every window.** `startSaving` ran before `self.window` was set, so `object: window` was nil and the observer saw every `willClose`. The Go to Folder sheet closing cleared the saved state, and nothing was ever restored. No unit test could see it; the relaunch test did. The window is now passed in.
- **There is no `processID` on `XCUIApplication`.** The test finds the app with `NSRunningApplication` and sends SIGKILL, which the UI test runner is allowed to do.
- **Wait past the delay before killing**, or the kill proves nothing about saving on change.
- **Cells are groups, not static texts.** The icon view's items are found as in `IconViewTests`.

## Known flake, not from this step

`LiveUpdateTests.aFileCreatedInAWatchedFolderShowsWithinOneSecond` fails in full parallel runs on this Mac (6 to 9 s against its 1 s bound) and passes alone. It fails the same way on the step 9 baseline `03b4662`. Not touched.

## Open or not done

- **VoiceOver** checks stay open with steps 4 to 9.
- **Scroll position** is not restored (out of scope).
- **More than one window** is not built; the saved shape is a list so it can be added.
