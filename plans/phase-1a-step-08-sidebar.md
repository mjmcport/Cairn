---
title: Phase 1A Step 8 Sidebar - Plan
type: feat
date: 2026-10-13
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Phase 1A Step 8 Sidebar - Plan

## Goal Capsule

- **Objective:** The window has a sidebar. Its Favorites are folders the person chose and can change; Locations are the volumes that are mounted, with an eject button on the ones that can be ejected; Cloud holds iCloud Drive and the other cloud services' folders; Tags and Recents are places that are not folders, each listing the files that have a tag or that were used lately. Clicking an item shows it in the tab that is showing (quality bar 7).
- **Means:** A sidebar model with no UI in `FileSystemCore` (KTD1 to KTD4), a split view and a source-list outline in `BrowserUI` (KTD5 to KTD7), and virtual locations: a location that a reader answers by a query, not by listing a folder (KTD8 to KTD11).
- **Authority:** R1 to R30 come from the step's row in `plans/phase-1a-browse.md`. Where a KTD and an R disagree, the R wins. Requirements marked "default" are unconfirmed bets listed under Assumptions.
- **Execution profile:** New code in `FileSystemCore` (the sidebar's model, volume and cloud discovery, favorites, a reader for virtual locations) and `BrowserUI` (the split view, the source list, navigation hooks), changes to `AppDelegate` and the menus, tests, and an end-to-end launch. Nothing was run while planning: what Spotlight returns for tags and recents on this Mac, what `unmountAndEjectDevice` needs, and what a mounted network share looks like are read about, not measured, so U1 is a probe unit.
- **Stop and tell the user when:**
  - a virtual location cannot be shown by the existing browser without changes to the load pipeline of steps 3 and 4 that U1's probe cannot keep small;
  - reading volumes, the cloud folders or the favorites takes the main actor more than a frame, and moving it off does not fix it;
  - an eject would be made without the person asking for it, or a tag or recents query would send anything off this Mac;
  - a real-stream or timing test fails some of the time: do not loosen or drop it;
  - UI automation is needed and the authentication prompt has not been approved;
  - a unit test fails on macOS 15 or macOS 26 only;
  - a fix would need a change under `.github/workflows/`.
- **Who finishes:** The implementer lands U1 to U7 on branch `phase-1a/sidebar`, runs the lessons and curriculum steps, makes the commit or commits, opens the pull request, starts the macOS 15 run by hand, and asks the user before merging.

---

## Product Contract

### Summary

Phase 1A step 8 puts a sidebar to the left of the pane. Four sections: Favorites (Recents, then bookmarks the person manages), Locations (mounted volumes, with eject), Cloud (iCloud Drive and the folders cloud services keep under `~/Library/CloudStorage`) and Tags (the Finder tags in use, each a place that lists what carries it). Recents, what was used in the last days, is the first Favorite. Clicking an item shows it in the showing tab, through the same load pipeline as any folder. Tags and Recents are virtual locations: their location is not a folder, and a reader answers a listing of one from a Spotlight query.

### Problem Frame

Three things in the current source shape the work:

- **The window is one pane.** `AppDelegate` sets the pane as the window's content, and the pane titles the window. There is no container for a second column and no way for something outside the pane to make a tab go somewhere.
- **A location is a folder URL.** `BrowserModel` loads `DirectoryReading.listing(in:)` for `history.current`, watches it, and titles the tab from its last path component. A tag or the recents are not folders.
- **A browser's history and tabs speak URLs.** A virtual location has to be a URL too, so history, Back and Forward, the title and the tab need no new idea.

The plan keeps the browser, the load pipeline and the watches exactly as they are. The sidebar is a new column that asks a tab to go somewhere, and a virtual location is a URL with its own scheme that a composite reader sends to a query.

### Requirements

**The window**

- R1. The window has a sidebar to the left of the pane, which can be shown and hidden (View > Hide Sidebar, Option-Command-S) and resized, with its width kept for the life of the window (not across a quit: step 10's).
- R2. Everything the pane did is unchanged: tabs, toolbar, the title of the window, keyboard focus after a switch, and the commands that reach the showing browser through the responder chain.
- R3. Keyboard focus can move between the sidebar and the pane (Tab, and the responder chain), and the sidebar can be used with the keyboard alone.

**Items and navigation**

- R4. Clicking, or pressing Return on, an item shows it in the showing tab, as a move: history, the title and the toolbar follow, and Back returns. The item is selected in the sidebar while its place is the tab's location.
- R5. Command-clicking an item opens it in a new tab (default).
- R6. A folder item whose place no longer exists shows why it cannot be listed, as a failed listing does, and stays in the sidebar.
- R7. The sidebar follows the showing tab: when the tab's location is, or becomes, one of the items, that item is selected; otherwise none is.

**Favorites**

- R8. The sidebar starts with Home, Desktop, Documents, Downloads and Applications as Favorites where they exist (default). A person can add the folder that is selected in the showing browser (File > Add to Sidebar), remove a favorite (context menu, and Delete with a favorite selected), and the changes are kept across launches.
- R9. A favorite is a bookmark: it follows the folder when it is moved or renamed, and a favorite whose folder cannot be found is kept and marked, not silently dropped (default).
- R10. A favorite is kept as a bookmark in the user defaults, and reading it, resolving it and listing a folder are done off the main actor.

**Locations and Cloud**

- R11. Locations lists the startup disk and the other mounted volumes, in the order the system gives, without hidden ones, and follows mounting, unmounting and renaming without a restart.
- R12. A volume that can be ejected has an eject button, with a spoken label and a tooltip; pressing it unmounts and ejects that volume and removes it when the system says it has gone. Nothing is ejected unless the person asked for that volume.
- R13. A failed eject says why, in the window, and leaves the volume listed.
- R14. Cloud lists iCloud Drive and each folder under `~/Library/CloudStorage`, by the name the service gives, where they exist, and follows additions and removals when the sidebar is shown again (default).
- R15. A cloud folder is opened as any folder. Nothing in this step downloads a file: listing a cloud folder reads names and metadata only, and an online-only file is shown as in step 6.

**Tags and Recents**

- R16. Tags lists the Finder's color tags and the other tags that are in use on this Mac (default). Choosing one shows the files that carry it.
- R17. Recents shows files used in the last seven days, most recent first, at most a few hundred (default).
- R18. A virtual location is shown by the browser as any listing is: first rows, a settled sorted list, the list, icon or column presentation, history, tabs and the title. It is not watched by FSEvents; it refreshes when the query says its results changed (default).
- R19. Opening a folder from a virtual location enters that folder as a move; opening a file does nothing yet. Enclosing Folder is not available in a virtual location, and Back returns to where the tab was.
- R20. A tag or recents query is local to this Mac; nothing is sent anywhere.

**Standing rules and proof**

- R21. No file-system call on the main thread. Anything new that touches the file system starts with the guard and has a test that it fires. `FileSystemCore` imports no UI framework.
- R22. Every new control and row takes an `AccessibilityElement` through `apply(_:)` or `applyIdentifier(of:)` and is in `AccessibilityElement.all`; a row speaks its name and, where it matters, its state ("ejectable", "not found", "online only").
- R23. The code compiles under Swift 6 strict concurrency with warnings as errors and runs on macOS 15.
- R24. Unit tests use stubs and gates and never wait on a clock. Tests touch only fixture folders; the volume, cloud and Spotlight sources are protocols with stubs.
- R25. Existing unit and end-to-end tests pass.
- R26. The accessibility audit passes with the sidebar showing and with a virtual location showing, on every macOS version CI runs.
- R27. First rows of the 10,000-item folder are unchanged within noise (the 200 ms target is met) and the sidebar adds nothing to a load.
- R28. No new dependency and no networking; nothing leaves this Mac.
- R29. `ARCHITECTURE.md`, `README.md` and the status line in `CLAUDE.md` describe the app after this step; the curriculum page, its index row and the lessons note are in the commit.
- R30. The step lands through a pull request merged only when CI and a macOS 15 run started by hand are green, and with the user's approval.

### Success Criteria

- Clicking Documents shows Documents in the tab, and Back returns.
- Plugging in or ejecting a disk changes Locations without a restart, and pressing the eject button ejects that disk.
- Choosing a tag lists the files that carry it, and the list can be shown as icons or columns.

### Scope Boundaries

Out of scope for this step:

- **Drag and drop** into and out of the sidebar, reordering favorites by dragging.
- **Creating, renaming and recoloring tags,** and tagging files.
- **Sections that can be collapsed and remembered,** and the sidebar's width across a quit: step 10's.
- **Search** beyond the two fixed queries; a search field is a later step.
- **Network locations** (Bonjour, "Connect to Server"). A mounted share appears as a volume; discovering shares does not.
- **Sync status badges** on cloud items, and downloading on request.
- **A sidebar for each window or tab:** one per window.

Considered and not built:

- **A tree in the sidebar for the folders under Favorites.** The outline could open them, but the pane already shows the contents, and a second tree to keep in step with watches is a second pipeline.
- **A tag or recents listing that is a saved search file.** It would put files on disk for something that is a query.
- **FSEvents for a virtual location.** It has no folder to watch; a metadata query already reports its own changes.

---

## Planning Contract

### Key Technical Decisions

**The model (`FileSystemCore`, no UI)**

- KTD1. **A sidebar is a list of sections of items, built from sources.** `SidebarSection` (favorites, locations, cloud, tags, recents) and `SidebarItem` (an identity, a title, a place, an icon name, and capabilities such as "can eject" and "can remove"). The place is a URL: a folder URL for folders and volumes, a virtual URL (KTD8) for a tag or the recents.
- KTD2. **Each source is a protocol with a stub.** `VolumeSource` (mounted volumes, and an async stream of changes), `CloudSource` (the folders), `FavoriteStore` (bookmarks) and `TagSource`. The real ones read the system; tests supply lists. The model is a function from their answers to sections, so it is tested without a window or a disk.
- KTD3. **Favorites are bookmarks in the user defaults.** An entry is bookmark data and the name it had when it was made. Reading and resolving them is file-system work: it is done in one function that is guarded, off the main actor. A bookmark that cannot be resolved is kept with a `missing` state.
- KTD4. **Discovery is off the main actor and the result is a value.** The model asks its sources in a task and publishes a new list of sections; the view never calls a source.

**Virtual locations (`FileSystemCore`)**

- KTD8. **A virtual location is a URL with a scheme that is not `file`.** `cairn-tag:Red` and `cairn-recents:`. The URL goes through history, tabs and the title unchanged; `lastPathComponent` of `cairn-tag:Red` is `Red`, which titles the tab.
- KTD9. **`CompositeReader` answers by scheme.** A `file` URL goes to `DirectoryReader`; a virtual URL goes to `MetadataQueryReader`, which runs a Spotlight query and yields the same two events a folder listing does (`firstItems`, `allItems`), so the model's load, sort and refresh need no new path.
- KTD10. **A query result is a `FileItem` for a real file.** Its URL is the file's, so open, selection by URL and the thumbnail pipeline work as they do for any folder. Two results can have the same name; selection is by URL, and the model's keys (names under the location) are not used for a flat result, which is a top-level list of items with no open folders.
- KTD11. **Watching a virtual location is the query's own live updates.** `FolderWatching` is not asked for a virtual URL; the reader's stream can stay open and yield again, and the model's refresh path (step 4) answers a signal from it. If that is not simple in U1's probe, the fallback is no live updates for virtual locations and a reload when the tab is shown again.

**The window (`BrowserUI`, `App`)**

- KTD5. **An `NSSplitViewController` holds the sidebar and the pane.** The sidebar item uses the sidebar behavior, so Option-Command-S, resizing and the standard hide command come from the system. The window's content is the split view controller; the pane is unchanged.
- KTD6. **The sidebar is a source-list outline.** An `NSOutlineView` with `.sourceList` style, section headers as group rows, items as rows with an icon and a name, and an eject button as a row-trailing view where a volume can be ejected.
- KTD7. **The sidebar asks a tab to go somewhere through the pane.** `PaneViewController.show(_ location: URL, inNewTab:)` makes the move on the showing browser as a command does (move first, then the listing in a task), or opens a tab. The sidebar holds no browser.

### High-Level Technical Design

What a click does:

```text
click on a sidebar item (or Return)
  1. the sidebar controller reads the item's place            (a value; no I/O)
  2. pane.show(place, inNewTab: commandKey)                  (main actor)
       moves the showing browser as the commands do:
       model.move(to: place); movedAway(); run { load }
  3. the browser lists it through CompositeReader             (off the main actor)
       file URL     -> DirectoryReader  (folder, volume, cloud, favorite)
       virtual URL  -> MetadataQueryReader (tag, recents)
  4. the sidebar follows the tab: the item whose place equals the tab's location is selected
```

What feeds the sidebar:

| Section | Source | Changes |
| --- | --- | --- |
| Favorites | `FavoriteStore` (bookmarks in the user defaults) | the person adds and removes |
| Locations | `VolumeSource` (mounted volumes) | mount, unmount and rename notifications |
| Cloud | `CloudSource` (iCloud Drive, `~/Library/CloudStorage/*`) | re-read when the sidebar is shown |
| Tags | `TagSource` (color tags, tags in use) | re-read when the sidebar is shown |
| Recents (in Favorites) | a fixed item | none; the query is run when it is chosen |

### Assumptions

- **Quality bar 7.** Its text is not in the repository (steps 1, 5 and 6 recorded the same). R1 to R30 are assumed to cover it.
- **The default favorites are Home, Desktop, Documents, Downloads and Applications** where they exist. **Recents is the first item of Favorites,** as in Finder, and cannot be removed; it is not a section of one item.
- **Command-click opens in a new tab,** which is not what Finder does (it opens a new window); tabs are the app's own.
- **A tag lists files from Spotlight's index.** Files the index has not seen, or folders Spotlight excludes, are not listed. The step does not make the index.
- **Tags are the tags found in use,** from a metadata query's value list for the tag attribute (U1 probed it: the tag and its count, in 26 ms). Finder keeps its own tag list in a private preference, which this step does not read, so a tag that no file carries is not listed.
- **Recents is seven days and a few hundred items,** from `kMDItemLastUsedDate`.
- **A virtual location is a flat list:** no folders open in place in it, no `FolderKey` tree. The list presentation shows it as rows; icons and columns show it as they show a folder's top level.
- **Cloud is re-read when the sidebar is shown** (R14), not watched.
- **Eject is unmount and eject of that one volume,** as `NSWorkspace` does it, with no force.
- **The sidebar is one per window,** and its selection follows the showing tab.

### Open Questions

None blocks the plan. Each is behavior that planning read about and did not run; the named probe settles it, and the fallback is already chosen.

- **What does a Spotlight query for items with tags, and for recently used items, return on this Mac, and how fast?** U1's probe decides the limits and whether the tags can be listed from results.
- **Can a query's live updates feed the model's refresh path without a new pipeline?** U1 and U3 decide (KTD11's fallback).
- **What do mounted volumes look like on this Mac** (names, ejectable, internal, hidden)? U1's probe decides the filter.
- **Does `NSSplitViewController` with the pane inside keep the toolbar, the window title and focus behavior of steps 1 and 2?** U5's tests decide; the fallback is a plain `NSSplitView` in the window.
- **How is a source-list outline seen by XCUITest and the audit?** U6 decides.
- **What does VoiceOver say for a section header, a row and the eject button?** The by-hand check decides; steps 4 to 7's checks are still open.

### Risks

| Risk | Mitigation |
| --- | --- |
| A virtual location pushes a second pipeline into the model. | One reader answers both, with the same two events (KTD9); U1 probes before U3 builds on it. |
| A tag query is slow or huge and holds the first rows. | Limits on the query, first rows from the first results, tested with a gate; stop condition if it cannot be bounded. |
| An eject runs on the wrong volume or without being asked. | The button is per row and acts on that row's volume; a test presses each of two and asserts which was asked; nothing ejects from a keyboard shortcut. |
| A bookmark is resolved on the main actor. | One guarded function; a test that the guard fires. |
| The split view changes the toolbar, title or focus the pane has. | U5's tests restate steps 1 and 2's behaviors with the split in place. |
| A cloud folder is listed in a way that downloads something. | Listing reads names and metadata only (step 6's values); a test lists a folder and asserts no content was read; by-hand check. |
| The 1x contrast false positive of step 5 appears on sidebar text. | The audit handler's measured-contrast re-check applies to static text. |

---

## Implementation Units

### U1. The probes

- **Goal:** The questions about volumes, Spotlight queries and the split view are answered before they are built on.
- **Requirements:** R11, R14, R16, R17, R18
- **Dependencies:** none
- **Files:** throwaway probes; `Packages/FileSystemCore/Tests/FileSystemCoreTests/` for any that are kept
- **Approach:** In-process probes of `mountedVolumeURLs` with the keys needed, the contents of `~/Library/CloudStorage`, an `NSMetadataQuery` for tagged items and for recents (count, time to first results, what the result items carry), and whether the query's updates arrive on the main run loop.
- **Verification:** The answers are inside the stop conditions or the plan is revised.

### U2. The sidebar model and its sources

- **Goal:** Sections of items built from stubbed sources, with favorites kept as bookmarks.
- **Requirements:** R8 to R11, R14, R16, R21, R24
- **Dependencies:** U1
- **Files:** `Packages/FileSystemCore/Sources/FileSystemCore/Sidebar*.swift` (new), `VolumeSource.swift`, `CloudSource.swift`, `FavoriteStore.swift`, tests
- **Test scenarios:**
  - The default favorites are the folders that exist; a missing one is left out.
  - Adding a favorite keeps its bookmark; removing one removes only it; both are kept across a new store over the same defaults.
  - A bookmark of a folder that was moved resolves to the new place; one that cannot be resolved is kept, marked missing.
  - Locations are the volumes the source gives, minus hidden ones, with ejectable ones marked; a change from the source replaces the list.
  - Cloud lists the folders the source gives by their names.
  - The guard fires for the bookmark resolution on the main thread.

### U3. Virtual locations

- **Goal:** A tag or recents listing reaches the browser through the same events as a folder.
- **Requirements:** R16 to R20, R21
- **Dependencies:** U1
- **Files:** `Packages/FileSystemCore/Sources/FileSystemCore/VirtualLocation.swift`, `CompositeReader.swift`, `MetadataQueryReader.swift`, tests
- **Test scenarios:**
  - A virtual URL round trips its tag or kind; its last path component titles the tab.
  - The composite sends a file URL to the folder reader and a virtual URL to the query reader.
  - The query reader yields first items and then all items for more than one batch, a failed query ends the stream with its error, and a cancelled consumer stops the query.
  - A model loaded from a virtual URL sorts, filters hidden items and keeps selection by URL.
  - A virtual location is not asked of the watcher.

### U4. The window and the sidebar view

- **Goal:** A split view with a source-list sidebar that draws the model and moves the showing tab.
- **Requirements:** R1 to R7, R22
- **Dependencies:** U2, U3
- **Files:** `Packages/BrowserUI/Sources/BrowserUI/SidebarViewController.swift`, `WindowContentViewController.swift`, `PaneViewController.swift`, `Accessibility.swift`, `App/AppDelegate.swift`, tests
- **Test scenarios:**
  - The window shows the sidebar and the pane; the sidebar hides and shows with its command.
  - Clicking an item moves the showing tab through the same move as a command, and Back returns.
  - Command-click opens a new tab at the item.
  - The sidebar selects the item whose place is the tab's location, and none otherwise, and follows a tab switch.
  - A folder item whose place is gone shows the browser's failed listing and stays.
  - The title, toolbar state and focus behaviors of steps 1 and 2 hold with the split in place.

### U5. Favorites, volumes and eject

- **Goal:** Favorites can be added and removed, locations follow mounts, and a volume can be ejected on request.
- **Requirements:** R8, R9, R11 to R13
- **Dependencies:** U4
- **Files:** `SidebarViewController.swift`, `App/MainMenu.swift`, `VolumeSource.swift` (real), tests
- **Test scenarios:**
  - File > Add to Sidebar adds the selected folder; the context menu and Delete remove a favorite; the list is kept by the store.
  - A mount, an unmount and a rename change Locations through the stub source.
  - Pressing the eject button of one of two volumes asks for that one and no other; a failure says why and leaves it; success removes it when the source reports it gone.
  - Nothing ejects without a press.

### U6. The running app

- **Goal:** The end-to-end tests prove the sidebar in the app, and a person has checked what a test cannot.
- **Requirements:** R4, R5, R16, R17, R26
- **Dependencies:** U5
- **Files:** `UITests/SidebarTests.swift` (new), `UITests/AccessibilityTests.swift`
- **Test scenarios:**
  - A favorite is clicked and shown; Back returns; Command-click opens a tab.
  - A folder is added to the sidebar and survives a relaunch, and is removed.
  - A tag file made by the test (a fixture file with a tag) is listed under its tag if Spotlight has indexed it; otherwise the test records that it was not and does not fail on the index.
  - The audit passes with the sidebar showing and with a tag listing showing.
  - By hand: eject a real disk image; iCloud Drive and a cloud service folder; VoiceOver.

### U7. Documents

- **Goal:** The documents describe the app after U1 to U6.
- **Requirements:** R29
- **Dependencies:** U1 to U6
- **Files:** `ARCHITECTURE.md`, `README.md`, `CLAUDE.md`, `docs/curriculum/phase-1-step-08-sidebar.md`, `docs/curriculum/README.md`, `docs/solutions/<date>-sidebar-notes.md`

---

## What the units found

Recorded after the build, so the plan matches what shipped.

- **U1 probes.** Mounted volumes 1.8 ms (10 with hidden, 1 without). `kMDItemUserTags == '*'` returns nothing; `LIKE '*'` with the attribute as a value list returns each tag in use with its count in 26 ms. A recents query sorted by last-used date: 50 results in 74 ms. A `$time.today(-7)` predicate variable crashed the test process.
- **KTD11 fallback taken.** A virtual location is a one-shot query, not live.
- **Added to the plan while building.** `-FavoritesSuite` and `-SearchScope` launch arguments (end-to-end tests stay on their own data); window opens at 1100 so the pane keeps about 900; focus goes to the list when the window appears; section headers use the primary label color; the history key includes the scheme; favorites are de-duplicated by resolving symbolic links off the main actor.
- **Not built.** Live updates of a virtual location; Tags a file does not carry; remembered sidebar width.

---

## Verification Contract

| Gate | Where | Proves |
| --- | --- | --- |
| U1's probes | Local, reference Mac | The system sources behave as the model assumes |
| `make lint`, `make test`, `make build` | Local, then CI | Unit tests, source checks, the timing suites alone |
| `make uitest` | Local | The new launches, the audits and every existing test |
| `make perf` | Local | First rows still met |
| By-hand checks (U6) | Local | Eject of a real disk image; cloud folders; VoiceOver |
| Pull-request CI on `macos-26` | GitHub | Everything automated, on a second macOS |
| macOS 15 workflow, started by hand | GitHub, before the merge | AppKit behavior on the minimum macOS |

---

## Definition of Done

- U1 to U7 are complete, and every scenario exists as a test or has been done by hand and written down, or named as skipped.
- `make lint`, `make test`, `make build`, `make uitest` and `make perf` pass.
- The Open Questions have answers in the lessons note.
- No abandoned attempt remains in the diff, and no probe file is in the repository other than probes kept as tests.
- `CLAUDE.md` says step 8 is done and step 9 is next.
- A pull request is open, its CI is green, the macOS 15 run on the same commit is green, and it is merged only with the user's approval.

---

## Sources

- `plans/phase-1a-browse.md`: the step 8 row and quality bar 7. Not in the repository: the text of quality bar 7.
- `plans/phase-1a-step-06-icon-view.md` and `docs/solutions/2026-10-13-icon-view-notes.md`: online-only files are never read to be drawn; one spoken element per cell.
- `plans/phase-1a-step-07-column-view.md` and `docs/solutions/2026-10-13-column-view-notes.md`: a view asks the model and writes back through requests; name the parts a system control makes; an image's description is read from the image.
- `docs/solutions/2026-10-12-list-view-notes.md`: tell the view at the move; a model that publishes late; timing suites run alone; the audit's 1x contrast estimate.
- `docs/solutions/2026-10-09-main-thread-guard-notes.md`: guard first, then a test on the main actor inside `withHandler`.
- Current source read for this plan: `AppDelegate` (the window and its content), `PaneViewController` (the title, tabs, focus), `BrowserModel` (location, history, load, watches), `DirectoryReading` and `DirectoryReader`, `Accessibility.swift`.
