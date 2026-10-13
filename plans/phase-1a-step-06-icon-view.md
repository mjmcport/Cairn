---
title: Phase 1A Step 6 Icon View - Plan
type: feat
date: 2026-10-13
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Phase 1A Step 6 Icon View - Plan

## Goal Capsule

- **Objective:** A tab can show its folder as icons. Each item is drawn as a picture above its name: the real thumbnail for an image or a document, the file's own icon for everything else, and a plain icon with a cloud mark, never a download, for a file that is online only. The picture arrives without the window waiting for it, scrolling stays smooth, and everything the list already does for the folder (selection, sort, hidden files, history, live updates, keyboard) works the same (quality bar 7).
- **Means:** A second presentation of the model's top level in an `NSCollectionView` (KTD1 to KTD4), a thumbnail pipeline in `FileMetadata` behind a protocol that hands back a `CGImage` and never touches AppKit (KTD5 to KTD9), one more value on `FileItem` that says a file is online only (KTD10), and a view mode per tab with View-menu commands (KTD11 to KTD13).
- **Authority:** R1 to R30 come from the step's row in `plans/phase-1a-browse.md`. Where a KTD and an R disagree, the R wins. Requirements marked "default" are unconfirmed bets listed under Assumptions.
- **Execution profile:** `FileItem` and the listing change by one value in `FileSystemCore`; `FileMetadata`, a stub until now, gets its first real code; `BrowserUI` gets a collection view, a thumbnail cache and a mode switch; end-to-end tests gain a launch. Nothing was run while planning: how fast thumbnails come, what a thumbnail request does to an online-only file, and what 100,000 items cost a collection view are read about, not measured, so U1 is a probe unit.
- **Stop and tell the user when:**
  - a thumbnail request for an online-only file causes it to be downloaded, or the probe cannot show that it does not;
  - the one new value on `FileItem` moves first rows of the 10,000-item folder above 200 ms (quality bar 4) and KTD10's fallback does not recover it;
  - scrolling a 10,000-item folder drops frames or blocks the main actor for more than a frame in a probe, and KTD7's limits do not fix it;
  - a real-stream or timing test fails some of the time: do not loosen or drop it;
  - UI automation is needed and the authentication prompt has not been approved;
  - a unit test fails on macOS 15 or macOS 26 only;
  - a fix would need a change under `.github/workflows/`.
- **Who finishes:** The implementer lands U1 to U7 on branch `phase-1a/icon-view`, runs the review and lessons steps, makes the commit or commits, opens the pull request, starts the macOS 15 run by hand and merges when both are green.

---

## Product Contract

### Summary

Phase 1A step 6 adds the icon presentation of a folder. View > as List and View > as Icons choose it for the showing tab. The icon view shows the same top-level items, selection and sort as the list, one picture and one name each. Pictures are filled in off the main actor, for the items on screen and a little beyond, and cached. A file that is online only gets the icon of its type with a cloud mark and no request is made for its thumbnail, so looking at a folder never downloads anything.

### Problem Frame

Three things in the current source shape the work:

- **The model is built for one presentation.** `BrowserModel` holds the top level as `items` and a tree of open folders for the outline, with a selection of URLs. An icon view has no tree: a folder is entered by navigating. The two presentations have to share the model without sharing the outline's open folders.
- **A listing knows nothing about clouds.** `FileItem` has size, size on disk and dates (step 5). It has no value for "this file is not on this Mac". A thumbnail request on such a file can make the system download it.
- **There is no cache and no pictures at all.** The list draws names and numbers. Producing a picture is file I/O and, for a document, rendering, and may take long.

The plan keeps the model, the load pipeline and the watches exactly as they are, adds one value to an item, and puts everything else in the view and a new pipeline.

### Requirements

**The mode**

- R1. View > as List and View > as Icons choose the presentation of the showing tab, and are checked and enabled as the other View command is. List is the default (default).
- R2. The mode belongs to the tab: another tab, a new tab and a window do not change with it. It is not remembered after a quit (step 10's).
- R3. Switching changes nothing about where the browser is: history, the title, the toolbar's state, the selection of top-level items, the sort and the hidden-files setting are as they were. Folders that were open in the list are closed by the switch, and a selection inside them falls back to the folder, as when the user closes them (default).
- R4. Switching does not list the folder again, and takes no longer than drawing what is on screen.

**The icon view**

- R5. Each top-level item is a cell with a picture and its name under it. Names wrap to two lines and truncate in the middle. A cell for a folder, a file and a package is told apart by its picture and by what VoiceOver says.
- R6. Selection works as in the list: click, Command-click, Shift-click, Select All, arrow keys in two dimensions, and the selection is the model's. Double-click or Open on a folder enters it as a move; on a file it does nothing yet.
- R7. Typing selects the first item whose name starts with what was typed, and a pause starts again, as in the list (default).
- R8. The folder's first rows, its sorted settle, a refresh from a watch and a reload reach the icon view by the rules of steps 3 and 4: first rows at once, the settle replacing them, a refresh publishing only when visible items changed, nothing scrolled by a refresh, keyboard focus kept.

**Pictures**

- R9. Every cell has a picture at once, without any file I/O: the generic icon of its type, chosen from the name. A better picture replaces it when one arrives.
- R10. A thumbnail is requested only for items in or near the visible area, at most a small number at a time, newest request first. A request for an item that has scrolled away is cancelled.
- R11. A picture that was produced is cached in memory, by the item's place, its modified date and size and the size asked for, so it is not made again while it is valid and is made again when the file changed. The cache is bounded in count and in bytes and drops the least recently used.
- R12. A file that is online only is shown with the generic icon of its type and a cloud mark, a thumbnail is never requested for it, and VoiceOver says it is online only.
- R13. Opening a folder, scrolling it and changing the mode never cause a file to be downloaded.
- R14. Producing a picture never runs on the main actor, and never holds up the first rows, a refresh or a scroll.

**Fits the rest**

- R15. The 10,000-item folder's time to first rows is unchanged within noise, and the 200 ms target is met with the new value read in every listing (R28 of step 5's kind).
- R16. Scrolling a 10,000-item folder keeps the main actor free: no gap longer than one frame is added by picture work.
- R17. Memory for pictures stays within the cache's bounds when a 100,000-item folder is scrolled from top to bottom.
- R18. The mode switch and the two commands are reached through the responder chain like the other View command, so no new route to the browser is needed.

**Standing rules and proof**

- R19. No file-system call on the main thread. Every new function in `FileMetadata` and `FileSystemCore` that touches the file system starts with `MainThreadGuard.assertOffMainThread()`, and a test proves each guard fires.
- R20. `FileSystemCore` and `FileMetadata` import no UI framework. The thumbnail provider returns a `CGImage`.
- R21. Every new control and cell takes an `AccessibilityElement` through `apply(_:)` or `applyIdentifier(of:)` and is in `AccessibilityElement.all`; a cell speaks the item's name, its kind, and "online only" where it is.
- R22. The code compiles under Swift 6 strict concurrency with warnings as errors and runs on macOS 15.
- R23. Unit tests of the model, the cache and the view use stubs and gates and never wait on a clock. A test that asserts on a clock is in a suite named in `TIMING_SUITES`.
- R24. Existing unit and end-to-end tests pass.
- R25. The step adds no networking and no dependency, and nothing is sent anywhere: a thumbnail is made on this Mac.
- R26. Tests touch only fixture folders, and the one probe that asks about an online-only file runs on a file the test makes.
- R27. `ARCHITECTURE.md`, `README.md` and the status line in `CLAUDE.md` describe the app as it is after this step. The step's curriculum page, `docs/curriculum/phase-1-step-06-icon-view.md`, its row in `docs/curriculum/README.md` and the lessons note are in the step's commit.
- R28. The step lands through a pull request merged only when CI and a macOS 15 run started by hand are green.
- R29. The accessibility audit passes with the icon view showing, on every macOS version CI runs, and the keyboard alone can switch the mode, move through the items and open a folder.
- R30. `docs/performance/baseline.json` is not re-recorded; new measurements are added beside the old.

### Success Criteria

- With a folder of photographs open as icons, thumbnails fill in while the window stays responsive, and scrolling is smooth.
- A folder with online-only files shows them with a cloud mark and the folder is read without any of them being downloaded.
- Switching a tab between list and icons is immediate and keeps the selection.

### Scope Boundaries

Out of scope for this step:

- **Icon size and spacing controls.** The size is fixed (Assumptions). A slider is a control with its own accessibility and state.
- **Folders opening in place in the icon view.** A folder is entered.
- **Remembering the mode** across a quit, and per-folder view settings: step 10's.
- **Previews and the preview column:** step 7.
- **Badges for tags, sharing and sync state beyond online-only:** with Get Info and the sidebar's Cloud and Tags, later.
- **Downloading an online-only file** on request. Nothing in this step makes a file download.
- **Drag and drop, renaming in place, file operations.**
- **A Show Hidden Files command and a Use Groups option.**

Considered and not built:

- **One view for both modes**, an `NSTableView`-like list inside the collection view. The outline's tree and the collection view's flat sections are different enough that sharing a view would carry both models' complications.
- **Thumbnails generated by the reader as it lists.** It would make every listing pay for pictures nobody looks at.
- **`NSWorkspace.icon(forFile:)` for the generic icon.** It reads the disk. The generic icon is chosen from the name by `UTType`, which is a lookup.
- **A persistent thumbnail cache on disk.** A second place to invalidate and to keep private; the system's own thumbnail cache sits under `QLThumbnailGenerator`.
- **A request for every item in the folder, as a batch.** It would hold 100,000 requests in flight.

---

## Planning Contract

### Key Technical Decisions

**The presentation (`BrowserUI`)**

- KTD1. **The icon view reads the model the list reads.** `NSCollectionView` shows `model.items` as one section and writes `model.selection`. It needs no new model state for rows. The model gains `viewMode` (list or icons) and `closeOpenFolders()`, which the switch to icons calls so that what is selected is visible (R3).
- KTD2. **A browser owns both views and shows one.** `BrowserViewController` keeps its outline and gains a collection view in the same scroll container's place; a mode change swaps which is on screen. Both read the model; neither is torn down, so switching is a hide and a reload (R4). The status label, title, toolbar and watches are shared and untouched.
- KTD3. **Items are the model's, handles are keys.** A collection view item is configured from a `FileItem` by its index. Selection is mapped between index paths and URLs through the model's items, as the list maps rows, and applied under the flag that keeps it from being written back (`isApplyingModelState`).
- KTD4. **Plain layout.** `NSCollectionViewFlowLayout` with a fixed item size and no estimated sizes, so a layout of 100,000 items is arithmetic. The name is drawn in a fixed-height label of two lines.

**The pictures (`FileMetadata`, then `BrowserUI`)**

- KTD5. **A provider that hands back a `CGImage` and never touches AppKit.** `ThumbnailProviding` in `FileMetadata` has one async function: the file, the point size and the scale in, a `CGImage` or nil out, thrown away silently when the request is cancelled. `QuickLookThumbnailer` is the real one, built on `QLThumbnailGenerator`, which is not AppKit. The cell wraps the image.
- KTD6. **The generic icon is a lookup, and arrives first.** The generic icon comes from the name's `UTType` through the workspace's icon for a content type, which does not read the disk, and is cached by type. Every cell has it at once (R9). The thumbnail is an upgrade.
- KTD7. **Requests follow the screen.** A cell asks for its thumbnail when it is about to be shown and cancels when it goes away, through the collection view's display callbacks. A small limit on requests in flight and a most-recently-asked-first queue keep a fast scroll from building a backlog. The limits are named constants, and a probe in U1 chooses their values.
- KTD8. **A bounded cache keyed by what makes a picture valid.** The key is the item's path, modified date, size and the pixel size asked for. The cache is bounded in entries and in bytes and evicts the least recently used. A refresh that changes an item's date makes its old picture unreachable by key, with no invalidation call.
- KTD9. **The cache and the queue are one actor.** A `ThumbnailLoader` actor owns the cache, the queue and the in-flight tasks, and is the only thing the cells talk to. Nothing on the main actor waits on it: a cell asks and is called back.

**Online only (`FileSystemCore`)**

- KTD10. **One value on `FileItem`: `isOnlineOnly`.** It is true for a regular file whose allocated size is zero while its logical size is not. That needs no new key: the listing already reads both sizes. The iCloud `ubiquitousItemDownloadingStatus` says it outright, but U1 measured it: reading it for every item of a listing took 10,000 items from 0.06 s to 0.53 s and 100,000 from 0.57 s to 5.4 s, so the listing does not read it. A caller with few items to ask about may pass it to `FileItem.isOnlineOnly(size:allocatedSize:downloadingStatus:)`.
- KTD11. **No thumbnail request is made for an online-only item.** The cell checks the value before it asks, and the loader refuses it as well, so one bug is not enough to download a file (R12, R13).

**The commands (`App`, `BrowserUI`)**

- KTD12. **Two checkable commands on the responder chain.** `showAsList(_:)` and `showAsIcons(_:)` on `BrowserViewController`, validated like `toggleFoldersFirst(_:)`, with the checkmark set from the model's mode. The View menu gets both, with Command-1 and Command-2.
- KTD13. **Type-to-select is the list's rule.** `NSCollectionView` has no type-to-select. A small typeahead buffer in the controller, timed by the event's timestamp, selects the first item whose name starts with the buffer; the buffer is a value type with a function from (buffer, time, key) to (buffer), so it is tested without a window or a clock.

**Proof**

- KTD14. **The cache and loader are tested with a stub provider** that holds each request at a gate, counts requests and honours cancellation. The real provider is tested against a fixture folder with bounded waits. One probe, kept as a test, asks that a request for an online-only file the test makes does not leave it downloaded.

### High-Level Technical Design

What a cell does, in order:

```text
configure(item at index)
  1. picture = generic icon for the name's type          (a lookup; cached by type; no I/O)
  2. if item.isOnlineOnly: add the cloud mark; stop       (no request, ever)
  3. key = (path, modified date, size, pixel size)
     cache hit      -> picture = cached image; stop
     cache miss     -> when about to be shown: ask the loader, remember the request
  4. loader: queue (most recent first), at most N in flight, off the main actor
     done, still wanted -> store in the cache; call back on the main actor
  5. cell scrolled away, or reused -> cancel its request
```

Who owns what:

| Thing | Where | Why |
| --- | --- | --- |
| `viewMode` | `BrowserModel` | A tab's state, like sort; tests and the menu read it without a view |
| The two views | `BrowserViewController` | One browser, one status label, one set of commands |
| `ThumbnailProviding` | `FileMetadata` | No AppKit, so the core stays testable and the guard applies |
| Cache, queue, tasks | `ThumbnailLoader` actor in `BrowserUI` | It needs `CGImage` only, but its policy is the view's |
| `isOnlineOnly` | `FileItem` | Read with the listing; the view must know before it asks |

### Assumptions

- **Quality bar 7.** Its text is not in the repository (steps 1 and 5 recorded the same). R1 to R30 are assumed to cover it.
- **The icon size is fixed**, a 64 pt picture in a cell of about 100 by 100 pt. Nothing in the step needs it to change.
- **A cell shows the name only.** Size and date are for the list.
- **Switching to icons closes the open folders** (R3), so a nested selection is never invisible. The alternative, keeping them open and unseen, leaves the model holding a selection a person cannot see.
- **A zero allocated size with a non-zero logical size means online only** (KTD10). A sparse file looks the same to this rule and would be drawn with the cloud mark and get no thumbnail. Whether the rule agrees with iCloud's own status on a real iCloud folder is a by-hand check, because a test cannot make a placeholder.
- **Thumbnails are produced at the display's scale** and at the cell's picture size, not larger.
- **`QLThumbnailGenerator` does not download an online-only file when asked for a thumbnail** only because it was not asked: KTD11 never asks. U1 checks what happens if it were asked, on a file the test makes, and the answer decides whether KTD11's second guard is enough.
- **The cache bounds are 2,000 entries and 64 MB**, from arithmetic (a 64 pt picture at 2x is about 64 KB). U1 measures the real figure.
- **No telemetry:** a thumbnail is never sent anywhere.
- **The mode is not in the title or the toolbar** in this step. Commands live in the View menu.

### Open Questions

None blocks the plan. Each is behavior that planning read about and did not run; the named probe settles it, and the fallback is already chosen.

- **What does a thumbnail request for a dataless file do?** U1's probe on a file the test makes decides; KTD11 means the app never asks.
- **How many thumbnails per second, and with how many in flight, does `QLThumbnailGenerator` deliver for ordinary files on the reference Mac?** U1's probe decides KTD7's limits.
- **Does `isOnlineOnly` from the sizes agree with the iCloud status key on a real iCloud folder?** It needs a folder with online-only files, which the test cannot make. The step records what a person finds in the by-hand check.
- **What does an `NSCollectionView` with 100,000 items cost in layout and in memory?** U1's probe decides whether KTD4's plain layout is enough.
- **Does `NSCollectionView` selection by index path survive a reload that changes the items?** U4's test decides; the fallback is to reapply the model's selection after each reload, as the list does.
- **What does VoiceOver say for a cell, and does the audit pass on the collection view?** U6 and the by-hand check decide.

### Risks

| Risk | Mitigation |
| --- | --- |
| A thumbnail request downloads an online-only file. | KTD11 asks for nothing; U1 checks what asking would do; a failure to show it does not is a stop condition. |
| A fast scroll builds a backlog of requests and the visible cells stay empty. | Most recent first, a small in-flight limit, cancellation on scroll-off (KTD7); U1 chooses the numbers. |
| The cache grows without bound on a large folder. | Entry and byte bounds with LRU eviction (KTD8); a test scrolls 100,000 stub items and asserts the bound. |
| The collection view's layout of a large folder blocks the main actor. | Fixed sizes, no estimates (KTD4); U1 measures. |
| Selection and sort get out of step between the two views. | Both read and write the model; one test drives both views through the same sequence. |
| The one new key slows listing. | Measured in U1 beside step 5's; fallback in KTD10. |
| VoiceOver reads a cell as a picture with no words. | The cell's label is built from name, kind and online-only state, tested; judged by hand. The VoiceOver checks of steps 4 and 5 are still open. |
| The same audit false positive as step 5 (1x contrast) appears on cell text. | The handler's measured-contrast re-check applies to static text; cells use the same label color. |

---

## Implementation Units

### U1. The online-only value, and the probes that decide the rest

- **Goal:** `FileItem` knows a file is online only, the thumbnail provider exists in its simplest form, and the questions about cost and behavior are answered before the view is built.
- **Requirements:** R12, R13, R15, R19, R20, R26, R30
- **Dependencies:** none
- **Files:**
  - `Packages/FileSystemCore/Sources/FileSystemCore/FileItem.swift`
  - `Packages/FileSystemCore/Tests/FileSystemCoreTests/FileItemTests.swift`, `DirectoryReaderTests.swift`
  - `Packages/FileMetadata/Sources/FileMetadata/ThumbnailProviding.swift` (new), `QuickLookThumbnailer.swift` (new)
  - `Packages/FileMetadata/Tests/FileMetadataTests/ThumbnailerTests.swift` (new)
  - `UITests/PerformanceTests.swift`
- **Approach:**
  1. Add `isOnlineOnly` to `FileItem` and to `init(url:resourceValues:)`, from the sizes (KTD10). The downloading-status key was tried and removed: it cost nine and ten times the listing. Both sets of numbers go into the lessons note.
  2. Write `QuickLookThumbnailer` and its guard, and probe it on a fixture of mixed files: time to first picture, throughput at different in-flight limits, what a request for a file the test makes dataless does (if the test can make one).
  3. Probe an `NSCollectionView` with 100,000 items: layout time, memory, selection by index path across a reload.
- **Execution note:** Run the measurements and the probes first and stop if they hit the stop conditions in the Goal Capsule, before any view is built.
- **Test scenarios:**
  - A regular file with zero allocated size and a non-zero logical size is online only; a file with both non-zero is not; a folder, a package and a link never are; an empty file is not.
  - A downloading status passed to `isOnlineOnly(size:allocatedSize:downloadingStatus:)` marks a file online only whatever the sizes say, and the listing does not pass one.
  - The thumbnailer returns an image for a small PNG fixture and nil for a file it cannot draw, honours cancellation, and refuses to run on the main actor under `withHandler`.
- **Verification:** The numbers are inside the stop conditions or the plan is revised.

### U2. The mode in the model

- **Goal:** A browser has a view mode and can close what is open in the list.
- **Requirements:** R1 to R4, R18
- **Dependencies:** U1
- **Files:**
  - `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`
  - `Packages/BrowserUI/Tests/BrowserUITests/BrowserModelTreeTests.swift`, `BrowserModelModeTests.swift` (new)
- **Approach:** `ViewMode` (list, icons) and `viewMode` on the model; `setViewMode(_:)` closes every open folder when the mode becomes icons, in one publish, selection falling back to the folders as `closeFolder` does; a publish kind for a mode change so the view can swap without scrolling.
- **Test scenarios:**
  - The default is list. Setting the same mode again does nothing and publishes nothing.
  - Switching to icons closes every open folder with one publish, drops nested selection onto the folders, keeps top-level selection, sort and location, and leaves history untouched.
  - Switching back does not reopen anything and does not list the folder again.
  - A mode set while a load, a refresh or a listing of an open folder is held does not disturb them.
  - Every existing model test passes unchanged.

### U3. The thumbnail pipeline

- **Goal:** A loader that gives a picture for an item, from a bounded cache or from the provider, off the main actor, for what is wanted and nothing else.
- **Requirements:** R9 to R14, R17, R20, R23, R25
- **Dependencies:** U1
- **Files:**
  - `Packages/BrowserUI/Sources/BrowserUI/ThumbnailLoader.swift` (new), `ThumbnailCache.swift` (new), `GenericIcons.swift` (new)
  - `Packages/BrowserUI/Tests/BrowserUITests/ThumbnailLoaderTests.swift` (new), `StubThumbnailer.swift` (new)
- **Approach:** KTD5 to KTD9 and KTD11. The cache is a value type with entry and byte bounds and LRU eviction, tested apart from the actor. The loader takes a `ThumbnailProviding`, a limit and a cache.
- **Test scenarios:**
  - A request is answered from the provider once, then from the cache; a changed modified date or size is a different key.
  - An online-only item is never requested of the provider, and a direct request for one is refused.
  - At most the limit is in flight; the newest request is served first; a cancelled request is never started, or is cancelled if running, and publishes nothing.
  - A request that fails or returns nil leaves the generic icon and is not retried in a loop.
  - 100,000 distinct requests leave the cache within its entry and byte bounds.
  - The provider runs off the main actor, and a stub that holds at a gate leaves the main actor free.
  - Generic icons are chosen from the name with no file access, and are cached by type.

### U4. The icon view

- **Goal:** An `NSCollectionView` that draws the model's items with their pictures, selects, sorts and refreshes as the list does.
- **Requirements:** R5 to R8, R10, R16, R21, R24
- **Dependencies:** U2, U3
- **Files:**
  - `Packages/BrowserUI/Sources/BrowserUI/IconCollectionViewController.swift` (new), `IconItemView.swift` (new), `TypeAhead.swift` (new)
  - `Packages/BrowserUI/Sources/BrowserUI/BrowserViewController.swift`, `Accessibility.swift`
  - `Packages/BrowserUI/Tests/BrowserUITests/IconViewTests.swift` (new), `TypeAheadTests.swift` (new)
- **Approach:** KTD1 to KTD4, KTD6, KTD7, KTD12 and KTD13. The browser shows one of two views by mode (KTD2). A cell configures from an item, asks the loader when about to be shown, cancels when it goes away.
- **Test scenarios:**
  - The collection view is identified and labelled; there is one cell per top-level item and none for a hidden one.
  - Each cell has a generic picture at once, and its label says name, kind and, for an online-only item, that it is online only.
  - A thumbnail arriving replaces the picture of the right cell only, including after the cell has been reused.
  - The model's selection is shown and a click, a Command-click and Select All write it back once, not looped.
  - A refresh that adds an item above the selected one keeps the same item selected, and does not scroll or move focus.
  - The first rows, then the settled list, then a reload each arrive as in the list.
  - Opening a folder cell enters it as a move; a file does nothing.
  - Typing selects by name; a pause starts again (`TypeAhead` is tested apart).
  - Every existing view test passes.

### U5. The commands and the switch

- **Goal:** View > as List and as Icons, with Command-1 and Command-2, switch the showing tab and show their state.
- **Requirements:** R1, R2, R18
- **Dependencies:** U4
- **Files:**
  - `Packages/BrowserUI/Sources/BrowserUI/BrowserViewController.swift`
  - `App/MainMenu.swift`
  - `Packages/BrowserUI/Tests/BrowserUITests/IconViewTests.swift`, `PaneViewControllerTests.swift`
- **Test scenarios:**
  - Each command is enabled for a browser and checked for the current mode; it acts on the showing tab only.
  - Switching to icons and back keeps the selection, the sort, the location and the scroll position of each view.
  - A new tab opens as list; a mode set in one tab does not appear in another.
  - Folders-first and a header-sort change survive a round trip through icons.

### U6. The running app

- **Goal:** The end-to-end tests prove the icon view in the app, and a person has checked what a test cannot.
- **Requirements:** R6, R8, R13, R15, R16, R29
- **Dependencies:** U5
- **Files:**
  - `UITests/IconViewTests.swift` (new), `UITests/AccessibilityTests.swift`, `UITests/PerformanceTests.swift`
- **Test scenarios:**
  - Five launches, in `UITests/IconViewTests.swift` (a cell is found by its spoken label, because it is one element): the folder is switched to icons from the View menu; every item is a cell; a folder cell is entered by double-click; Back returns in icons; Command-1 returns to the list with the same selection.
  - The accessibility audit passes with the icon view showing; the keyboard alone switches the mode, moves with the arrows and opens a folder.
  - `make perf`: first rows still within the target with the new value read.
  - By hand: a folder of photographs fills in while the window answers; a folder with online-only files shows the cloud mark and none is downloaded; the VoiceOver check for a cell, with steps 4 and 5's checks still open.

### U7. Documents and the curriculum page

- **Goal:** The documents describe the app after U1 to U6, and the step has its teaching page.
- **Requirements:** R27
- **Dependencies:** U1 to U6, and the review step's fixes
- **Files:** `ARCHITECTURE.md`, `README.md`, `CLAUDE.md`, `docs/curriculum/phase-1-step-06-icon-view.md` (new), `docs/curriculum/README.md`, `docs/solutions/<date>-icon-view-notes.md` (new)
- **Test expectation:** none -- documents. `make lint` runs the governance check over them.

---

## Verification Contract

| Gate | Where | Proves | Needs the user at the Mac |
| --- | --- | --- | --- |
| U1's measurements and probes | Local, reference Mac | The value, the provider and the collection view cost what the plan assumes | Yes, for the reference Mac's numbers |
| `make lint` | Local, then CI | Governance files and Swift formatting | No |
| `make test` | Local, then CI | Unit tests of U1 to U5, the timing suites alone, the source checks | No. Use `rtk proxy make test` for full output. |
| `make uitest` | Local | The new launch, the audits, every existing test | Yes, for the authentication prompt |
| `make perf` | Local, reference Mac | First rows still met with the new value read | Yes |
| By-hand checks (U6) | Local | Photographs fill in; online-only files are not downloaded; VoiceOver | Yes |
| Pull-request CI on `macos-26` | GitHub | Everything automated, on a second macOS | No. Watch it with `gh run watch`. |
| macOS 15 workflow, started by hand | GitHub, before the merge | AppKit behavior on the minimum macOS | No. `gh workflow run macos-15.yml --ref phase-1a/icon-view` |

---

## Definition of Done

- U1 to U7 are complete, and every scenario listed under them exists as a test or, for the by-hand checks, has been done and written down (or named as skipped, with the date, in the lessons note and on the curriculum page).
- `make lint`, `make test` and `make build` pass on the final tree, and `make uitest` and `make perf` on the reference Mac.
- The Open Questions have answers in the lessons note.
- No abandoned attempt remains in the diff, and no probe file is in the repository other than probes kept as tests.
- `CLAUDE.md` says step 6 is done and step 7 is next.
- A pull request is open, its CI run is green, the macOS 15 run started by hand on the same commit is green, and it is merged only then.
- The pull request's diff touches nothing under `.github/workflows/` and does not change existing numbers in `docs/performance/baseline.json`.

---

## Sources

- `plans/phase-1a-browse.md`: the step 6 row and quality bar 7. Not in the repository: the text of quality bar 7.
- `plans/phase-1a-step-05-list-view.md` and `docs/solutions/2026-10-12-list-view-notes.md`: the model, selection, sort and watch the icon view shares; a view asks for what it draws, and the model may change under cached counts, so a command that empties rows tells the view at once; timing suites run alone; the audit's 1x contrast estimate and the measured re-check.
- `plans/phase-1a-step-04-live-updates.md`: a refresh publishes only when visible items changed and never scrolls.
- `docs/solutions/2026-10-09-accessibility-notes.md`: cells that show text get an identifier only; prefer the label color.
- `docs/solutions/2026-10-09-main-thread-guard-notes.md`: guard first, then a test on the main actor inside `withHandler`.
- Current source read for this plan: `FileItem` and its resource keys, `BrowserModel` (items, selection, open folders, publish kinds), `BrowserViewController` (the outline, `modelDidChange`, `applyModelSelection`), `MainMenu`, `Accessibility.swift`, and the `FileMetadata` package, which holds `MetadataGroup` only.
