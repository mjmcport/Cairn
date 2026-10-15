---
title: Phase 1A Step 10 State Restoration - Plan
type: feat
date: 2026-10-15
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Phase 1A Step 10 State Restoration - Plan

## Goal Capsule

- **Objective:** Quit Cairn, or lose it to a crash, and open it again: the window is where it was and as big as it was, the tabs are the same folders in the same order with the same one showing, and each tab keeps its view (list, icons, columns), its sort, hidden files, open folders and list column widths. The sidebar keeps its width and whether it is collapsed.
- **Means:** A plain, versioned value that describes a window (KTD1), saved to the user defaults a moment after anything in it changes, not at quit (KTD2), and read at launch before the window is built (KTD3). Pure logic and tests in `BrowserUI`; the app target only wires launch and the frame.
- **Authority:** R1 to R18 come from the step's row in `plans/phase-1a-browse.md` ("Windows, tabs, view settings and column widths restored after quit and crash", quality bar 3). Where a KTD and an R disagree, the R wins. Requirements marked "default" are unconfirmed bets listed under Assumptions.
- **Execution profile:** New files in `BrowserUI`, edits to `PaneViewController`, `BrowserViewController`, `BrowserModel`, `WindowContentViewController`, `AppDelegate`, `SettingsView`, tests, an end-to-end relaunch. Nothing was run while planning: how often the list's column widths report a change while a divider is dragged, and whether `NSSplitView` reports the sidebar's width during a drag, are read about, not measured, so U3 and U4 carry probes.
- **Stop and tell the user when:**
  - saving or restoring touches the file system on the main thread;
  - a restored location that no longer exists would show an error instead of the nearest folder that does;
  - restoring would make launch slower to first rows than step 3's number (`make perf` regresses);
  - a relaunch test fails some of the time: do not loosen or drop it;
  - a unit test fails on macOS 15 or macOS 26 only;
  - a fix would need a change under `.github/workflows/`.
- **Who finishes:** The implementer lands U1 to U5 on branch `phase-1a/state-restoration`, runs the lessons and curriculum steps, commits, opens the pull request, starts the macOS 15 run by hand, and asks the user before merging.

---

## Product Contract

### Summary

Cairn remembers its window. What is saved is what the person set up: where, how big, which folders, how each is shown. What is not saved is what the disk says: file lists are read fresh, so a restored tab never shows a stale listing.

### Problem Frame

- **Every launch starts at home with one tab.** Tabs, view modes, sort and column widths set up over a day are gone at the next launch.
- **Quit is not the only way out.** A crash or a force quit gives no chance to save, so state written only at quit is lost exactly when it is wanted.
- **A saved place may be gone.** A folder deleted, a volume ejected or a tag removed must not leave a window that shows an error where the person's work was.

### Requirements

**What is restored**

- R1. The window's frame (position and size) is restored; a frame that is on no connected screen is moved onto one.
- R2. The tabs are restored in order, with the same tab showing.
- R3. Each tab restores its folder, or a virtual location (a tag, Recents) as it was.
- R4. Each tab restores its view mode, sort (key, direction, folders first) and whether hidden files show.
- R5. A tab in list view restores which folders were open in place and its selection (default: selection restored when the item still exists).
- R6. The list's column widths, order and visibility are restored per window (shared by tabs, as the columns are today).
- R7. The sidebar's width and whether it is collapsed are restored.
- R8. Whether the path bar shows is restored.
- R9. Each tab's history (Back and Forward) is restored, to a limit of 20 entries (default).

**When it is saved**

- R10. State is saved shortly after any change in it (at most one second later), not only at quit, so a crash loses at most that second.
- R11. A quit saves at once, ahead of the delay.
- R12. Saving never blocks the main thread on a file; it writes the user defaults, which the system already caches.

**When it is restored**

- R13. A launch with `-OpenFolder` ignores saved state and opens that folder (the argument is for tests and scripts).
- R14. A restored folder that no longer exists is replaced by its nearest ancestor that does; if none can be listed, home. The check is off the main thread.
- R15. State that cannot be read (an old version, damaged data) is ignored, and a default window opens. Nothing is deleted before a good save replaces it.
- R16. Restoration is a setting, "Reopen windows and tabs when Cairn starts", on by default (default).
- R17. A restored window shows its first rows as fast as a new one: restoring adds no listing before the showing tab's.
- R18. Tabs that were not showing are not listed until shown, as today.

### Scope Boundaries

- **In scope:** one window, as the app opens one today. The state is shaped as a list of windows so more are possible later.
- **Not in scope:** multiple windows (not built), per-folder view settings (Finder's `.DS_Store` style), restoring the scroll position, restoring the text of a Go to Folder sheet, Sparkle or login-item relaunch.

---

## Key Technical Decisions

- **KTD1. A Codable value tree, versioned.** `SavedState { version, windows: [SavedWindow] }`, `SavedWindow { frame, sidebarWidth, sidebarCollapsed, showsPathBar, listColumns, tabs: [SavedTab], showingIndex }`, `SavedTab { location, viewMode, sort, showsHidden, openFolders, selection, history }`. Paths are stored as strings, locations through `VirtualLocation` as their URL string. Unknown version: ignored (R15). Pure, no AppKit, in `BrowserUI` because `ViewMode` is there.
- **KTD2. Save on change, debounced.** One `StateSaver` owned by the window content collects "something changed" from the pane, its tabs and the split view, and writes after 0.5 s of quiet. Quit flushes. This makes quit and crash the same path (R10, R11).
- **KTD3. Read before the window is built.** `AppDelegate` asks `StateRestorer` for a `SavedWindow` and passes it to `WindowContentViewController`; the pane creates its tabs from it. Only the showing tab lists; the others are made without a listing, as `newTab` does.
- **KTD4. The user defaults hold one `Data` blob.** Not a file: no file-system call on the main thread (R12), and the test suites already use a suite name for isolation (`-StateSuite`, as `-FavoritesSuite`).
- **KTD5. Existence checks are guarded.** `RestoredLocation.resolve` walks up from the saved folder with a guarded, off-main existence check and returns the nearest folder; the tab is created on that and a second move is never needed.
- **KTD6. Column widths through the table's own autosave.** `NSTableView.autosaveName` and `autosaveTableColumns` already persist order, width and visibility in the user defaults; use it with a name derived from the suite, rather than writing it by hand (R6). Probe in U3: autosave under a test suite.
- **KTD7. The frame through `NSWindow.setFrameAutosaveName`**, which the system already corrects for missing screens (R1). Not part of the saved blob.

---

## Implementation Units

- **U1. The saved shapes and their coding** (`BrowserUI/SavedState.swift`): the tree in KTD1, `encode`/`decode` with version check, a `StateStoring` protocol with `UserDefaultsStateStore` (suite via `-StateSuite`). Tests: round trip; unknown version decodes to nil; damaged data decodes to nil; a virtual location survives.
- **U2. Capturing and applying** (`BrowserModel`, `BrowserViewController`, `PaneViewController`): `captureState()` on each, and creation of tabs from a `SavedWindow`. `BrowserModel.restore(_:)` sets view mode, sort, hidden files and a selection to restore, opens folders through the existing `foldersToRestore` path. Tests: a model captured and restored reproduces mode, sort, hidden, open folders, selection with a stub reader; a pane with three tabs restores their order and the showing one; not-showing tabs have listed nothing (R18).
- **U3. The saver and the change signals** (`StateSaver`, hooks): debounce, flush, and signals from tab changes, moves, view mode, sort, path bar and the sidebar split. Column widths and order through `autosaveName` (KTD6). Tests: three changes inside the delay make one write; flush writes at once; a write happens with no quit (R10); the saver writes nothing when restoration is off (R16).
- **U4. Restore at launch** (`AppDelegate`, `WindowContentViewController`, `RestoredLocation`, `SettingsView`, `BrowserSettings`): launch order (R13), nearest existing ancestor (R14), the setting (R16), frame autosave (KTD7), sidebar width and collapse (R7). Tests: `RestoredLocation` against a fixture tree with a removed folder and with nothing left; the settings key; `-OpenFolder` wins.
- **U5. End to end** (`UITests/StateRestorationTests.swift`): build a window with two tabs in a fixture, switch one to icons, relaunch with the same `-StateSuite`, assert tabs, showing tab and mode; relaunch after the fixture folder is removed, assert the nearest ancestor shows and no error; a relaunch with `-OpenFolder` ignores the state. Accessibility audit of the Settings window with the new checkbox.
- **U6. Docs:** lessons note, curriculum page and index row, `ARCHITECTURE.md` ("How state is restored"), `README.md`, `CLAUDE.md` status.

---

## Verification Contract

- `make lint`, `make test`, `make build`, `make uitest`, `make perf` pass on the dev Mac; the pull request's CI passes; the macOS 15 workflow passes on the same commit (`gh workflow run macos-15.yml --ref phase-1a/state-restoration`).
- A tab's restore never lists on the main thread (guard tests exist for `RestoredLocation`).
- `make perf` first-rows number does not regress (R17).
- A real crash is simulated in the UI test by relaunching with the process killed before the quit flush; the unit test proves a write happens with no flush.

## Definition of Done

R1 to R18 each have a test or are listed under open items. Plan, notes and curriculum page are in the commit. The pull request is open with CI and the macOS 15 run green on the same commit, and the user has been asked before merging.

## Assumptions

- Restoration is on by default and has a setting (R16), a bet: the plan row names no setting.
- Selection and 20 history entries are restored (R5, R9). If the folder changed, a missing selected item is dropped silently.
- One window only; the format is a list so a second window is an addition.
- The saved frame is not part of the blob and uses the system's frame autosave.
- VoiceOver checks stay open with steps 4 to 9.
