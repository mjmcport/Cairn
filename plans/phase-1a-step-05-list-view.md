---
title: Phase 1A Step 5 List View - Plan
type: feat
date: 2026-10-11
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Phase 1A Step 5 List View - Plan

## Goal Capsule

- **Objective:** The browser's list becomes an outline. A folder in the list has a disclosure triangle, and opening it shows its contents indented beneath it, in the same window, with the selection, sort, live updates and keyboard of the rest of the list. The columns can be sorted by clicking their headers, and two new ones, Size on Disk and Date Added, join them. Typing a name selects the matching row. A "folders first" option groups folders ahead of files at every level (quality bar 6). The folders that were open in a place are remembered with its history entry and opened again on Back and Forward, unless a setting says not to.
- **Means:** A tree model under `BrowserModel` whose root level is today's load and whose deeper levels are listed on demand and watched (KTD1 to KTD9), an `NSOutlineView` in place of the `NSTableView` (KTD10 to KTD14), two more resource keys on every item (KTD15), and what a history entry remembers about open folders, with a setting for it (KTD19 to KTD23).
- **Authority:** R1 to R38 come from the step's row in `plans/phase-1a-browse.md` and from what steps 3 and 4 left to this step. Where a KTD and an R disagree, the R wins. Requirements marked "default" are unconfirmed bets listed under Assumptions; the user may change one without reopening the rest.
- **Execution profile:** Two changed files and tests in `FileSystemCore`, a rewritten model section, a history entry that carries open folders and a rewritten list in `BrowserUI`, a new Settings window in the app target, changes to the end-to-end tests that query the list, and six documents. Nothing was run while planning: `NSOutlineView` behaviors and the cost of the two new resource keys are read about, not measured, so U1 is a probe unit that answers the Open Questions before anything is built on them. Three proofs need the user at the development Mac: `make uitest` (authentication prompt), `make perf` (the reference Mac) and the VoiceOver check.
- **Stop and tell the user when:**
  - U1 shows that reading the two new keys, or reloading an outline of 100,000 rows, puts first rows of the 10,000-item folder above 200 ms (quality bar 4) and the fallback under KTD15 or KTD13 does not recover it;
  - a test that uses a real FSEvents stream fails some of the time: do not loosen or drop it;
  - UI automation is needed and the authentication prompt has not been approved;
  - a unit test fails on macOS 15 or macOS 26 only;
  - the pull-request CI run or the manual macOS 15 run is red and the cause is not understood, or a fix would need a change under `.github/workflows/`;
  - the step needs a change to `docs/performance/baseline.json` other than adding measurements.
- **Who finishes:** The implementer lands U1 to U7 on branch `phase-1a/list-view`, runs the review and lessons steps, makes the one commit, opens the pull request, starts the macOS 15 run by hand and merges when both are green.

---

## Product Contract

### Summary

Phase 1A step 5 replaces the flat table with an outline of the folder being shown. A folder row can be opened in place, one level at a time, and what is open is watched and kept current as step 4 keeps the top level. Columns sort by their headers, Size on Disk and Date Added are new, "Keep Folders on Top" is a View-menu option, and typing selects. Opening a folder in place is not navigation: it does not touch history, tabs or the title. What was open is kept with the history entry of the place being left, and Back and Forward open it again as the folder settles, unless a setting in a new Settings window says not to.

### Problem Frame

Today `BrowserModel` holds one flat `items` array for one folder and a `selection` of URLs that belong to that folder. Three things in the current source stand in the way of an outline:

- **A selection is matched by name** (`BrowserModel.matching`), because a location spelled `/var/...` lists its items under `/private/var/...` and names are the only part that agrees (`docs/solutions/2026-10-09-navigation-history-notes.md`). Names repeat between folders, so the same rule applied to an outline would select every `notes.txt` that is open.
- **Every load, refresh and sort assumes one level.** `FileItemSort.arranged` sorts one array, `differs(from:)` compares one array, and `BrowserModel.refresh` re-reads one folder.
- **The watcher is one stream per folder and is started by the model for `location` only** (`BrowserModel.startSession`). Step 4's plan left the folders that are open to this step.

The plan keeps the root level exactly as step 3 and step 4 built it, so first rows, refreshes and the load counter work as they do, and adds the deeper levels as a second kind of arrival under the same rules.

### Requirements

**Opening folders in place**

- R1. A folder row shows a disclosure triangle. Clicking it, or pressing Right Arrow on the row, opens the folder; Left Arrow or another click closes it. Files, packages and symbolic links show none (default: a symbolic link to a folder is not opened in place, as Open does not enter one today).
- R2. An open folder's items are listed below it, indented one level, with the columns of the list. They are filtered for hidden items and sorted like the top level.
- R3. Opening a folder lists it off the main actor and publishes its rows only when they are sorted. The triangle turns at once; no placeholder row and no loading state is shown for it (default).
- R4. A folder that cannot be listed shows a row in its place that says why, and the folder stays open so a later change can list it. The row is not selectable and is spoken like any other (default).
- R5. What is open stays open through a refresh of the top level, a refresh of its own folder, a sort and a change of the hidden-files setting. It does not survive a move to another folder, except as R33 to R36 say.
- R6. Opening a folder is not a move: history, the title, the toolbar's enabled state and tabs are unchanged, and "Open" on the selection still enters a folder as it does today.

**Selection**

- R7. The selection may hold items at any open level. It is kept by the item's place under the top-level folder, never by name alone, so two files with the same name in different folders are two selections.
- R8. Closing a folder drops from the selection every item inside it, and the selection falls back to the folder row if one of them was selected (default).
- R9. Every selection rule of steps 1 to 4 still holds for the top level: restored by name on Back, the folder just left selected on Enclosing Folder, kept through a refresh, and the user's own selection made during a load or refresh wins.

**Sorting and columns**

- R10. Clicking a column header sorts the list by it, and clicking it again reverses it. The sort applies at every open level, and the rows settle into the new order with the selection kept and scrolled into view.
- R11. The list has five columns: Name, Size, Size on Disk, Date Modified and Date Added. Size on Disk and Date Added are sortable like the others. A folder has no value for Size or Size on Disk and shows the dashes of today, spoken as words.
- R12. "Keep Folders on Top" is a checkable item in the View menu. When on, folders are grouped ahead of files at every level, in either sort direction. It is off by default (default). It acts on the showing browser through the responder chain and is enabled only when a browser can take it.
- R13. The sort and the folders-first setting belong to the browser (a tab), not to the app (default). Neither is remembered after a quit; that is step 10's.

**Keyboard and type-to-select**

- R14. Typing selects the first visible row whose name starts with what was typed, and a pause starts a new search, as the system's type-to-select does. Rows inside closed folders are not searched.
- R15. Up and Down Arrow, Return-to-open, Command-Down for Open and every existing keyboard command behave as before.

**Fits the pipeline of steps 3 and 4**

- R16. The top level loads exactly as step 3 built it: first rows, then the sorted list, `FirstRows` and `LoadFolder` signposts measured as before, the load counter checked after every wait.
- R17. A change on disk inside an open folder shows in its rows within 1 s, by the rules of step 4: collected for 0.3 s, answered by one refresh off the main actor, published only when something visible changed, and never shown through a loading state.
- R18. A refresh of one level never changes another level's rows, the selection of items that still exist, the scroll offset or keyboard focus.
- R19. A folder that is open and is deleted or renamed away leaves the outline with the folders inside it, and its selection is dropped (default). A folder that is open and unreadable shows R4's row.
- R20. A move, a load of the top level, and a reload retire every listing and refresh in flight at any level, whichever stage it had reached. A close retires the listing and the watch of the folder closed and of everything inside it.
- R21. A watch exists for the top-level folder and for each open folder, only while the browser is on screen (step 4's R17), and ends when the folder is closed, when it leaves the outline, and when the browser stops watching.

**Standing rules and proof**

- R22. No file-system call runs on the main thread. Every new function that touches the file system starts with `MainThreadGuard.assertOffMainThread()`, and a test proves each guard fires.
- R23. `FileSystemCore` and `FileMetadata` import no UI framework.
- R24. Every new control, column and menu command that is a view takes an `AccessibilityElement` through `apply(_:)` or `applyIdentifier(of:)` and appears in `AccessibilityElement.all`. Cells that show changing text speak that text, and a missing value is spoken in words.
- R25. The list is an outline to VoiceOver: a row says its level and whether it is open or closed, and opening or closing a folder is announced by the system, not by an app announcement (judged by hand, U6).
- R26. The code compiles under Swift 6 strict concurrency with warnings as errors and runs on macOS 15.
- R27. Unit tests of the model and the controller use stubs and gates and never wait on a clock. Tests that use a real FSEvents stream wait with a bound and touch only fixture folders.
- R28. `make perf` still reports the 200 ms first-rows target met on the reference Mac with the two new keys read for every item. `docs/performance/baseline.json` is not re-recorded; the new measurements are added beside the old (U1).
- R29. Opening a folder of 10,000 items shows its sorted rows without the main actor waiting for the listing, and the time it takes is recorded in the lessons note (default: not judged against a target).
- R30. Existing unit and end-to-end tests pass, except the ones that query the list's type or its columns, which are updated in this step and listed under U5 and U6.
- R31. The step adds no networking, no telemetry and no dependency.
- R32. `ARCHITECTURE.md`, `README.md` and the status line in `CLAUDE.md` describe the app as it is after this step. The step's curriculum page, `docs/curriculum/phase-1-step-05-list-view.md`, and its row in `docs/curriculum/README.md` are in the step's commit. The step lands as one commit named `Phase 1 step 5: list view` on `phase-1a/list-view`, through a pull request merged only when CI and a macOS 15 run started by hand are green.

**History and the setting**

- R33. When the browser leaves a folder by a move, the folders that were open in it are kept in that history entry beside its selection (default: all of them, no cap). Opening and closing a folder does not change any entry but the one being left.
- R34. Going Back or Forward to an entry opens again, as the folder settles, the folders remembered there that still exist, shallowest first, and restores the selection of items inside them as their rows appear. A remembered folder that is gone, or is no longer a folder, is skipped without a message.
- R35. Only Back and Forward restore (default). Open, Enclosing Folder, a new tab and a first visit start with a closed outline.
- R36. A setting, "Open folders again when going back or forward", turns R34 off and on. It is on by default (default). It is read when the move is made, so a change applies to the next Back or Forward and never to an outline that is showing. It applies to every window and tab.
- R37. The setting is in a Settings window opened from the app menu with Command-comma. The window holds the one checkbox and a line that says what it does; the checkbox has an identifier and a spoken label through `AccessibilityElement`; the setting is kept across launches in the user defaults.
- R38. Restoring never shows a loading state, never delays or cancels a load, and is retired by a move, a load or the user closing a folder. The restore of one arrival never publishes into another, and the user's own open, close or selection made while it runs wins.

### Success Criteria

- With a folder open in the list, `touch`, `mv` and `rm` in Terminal inside that open folder show in its rows before the user has looked back at the window, and the rows above and below it do not move.
- A folder of 10,000 items can be opened, and the window answers a click while it opens.
- Clicking Date Added once sorts the folder by when its items were added to it.
- With the setting on, opening a folder, entering another and pressing Back shows the first folder with the same folders open and the same items selected; with the setting off in Settings, Back shows it closed.

### Scope Boundaries

Out of scope for this step:

- **Remembering what is open beyond Back and Forward.** What is open is kept with each history entry for the life of the window and used by Back and Forward only (R33 to R36). An outline remembered across a quit, and one remembered for a place that is revisited by Open or Enclosing Folder, are step 10's (state restoration).
- **Other settings.** The Settings window holds this one checkbox. A default sort, the columns and Show Hidden Files are not added to it.
- **Hiding and showing columns, reordering and resizing that is remembered.** Columns can be dragged and resized by AppKit's defaults; nothing is persisted (step 10).
- **Folder sizes.** A folder's size is the sum of everything inside it and needs a recursive read; a folder shows dashes.
- **Option-click to open everything inside.** AppKit's request to open a folder and all it holds is answered by opening one level, because the deeper levels have not been listed.
- **Icons and thumbnails** (step 6), **columns of metadata beyond the five** (Get Info, later), **renaming, drag and drop, file operations** (later steps).
- **A "Show Hidden Files" command.** The model already has the flag; its command and key belong with the View menu work after this step.
- **Network and cloud locations**, as in step 4.

Considered and not built:

- **One FSEvents stream for the whole outline** whose events are sorted into folders. It would use fewer streams, but it changes the signal type of `FolderWatching` that step 4 tested, and nothing measured so far says a stream per open folder is a cost. U3's test of fifty open folders, or a profile with hundreds, would change the call (see Risks).
- **A flat array of rows with a depth number, shown in the existing table with manual indentation.** It would keep the table, but it has no disclosure triangle for VoiceOver to describe, and the plan names an outline view.
- **Listing the children of every visible folder ahead of the user opening it**, so a triangle can show whether the folder is empty. It costs a listing per folder in view, and nothing in the step needs it.
- **Selecting by file identity.** A selection moves with a rename in Finder; here it follows the path, as the selection by name did (step 4 recorded the same choice).
- **Opening the remembered folders in parallel.** They open one at a time so each follows the rules of KTD4 and the order of publishes is plain. A restore that reads as slow would change the call.
- **A per-folder memory, as Finder keeps one, that restores on any visit.** It would need a store keyed by place and a rule for when to forget; history entries already carry what Back and Forward need.
- **Animating a folder open or closed.** The system's animation is left to AppKit; a measured problem would change the call.

---

## Planning Contract

### Key Technical Decisions

**The tree (`BrowserUI`, with two small additions in `FileSystemCore`)**

- KTD1. **The model keeps the top level as it is and adds a dictionary of open folders.** `items` stays the sorted top-level rows, so every model test and every caller of `items` keeps working. A new `openFolders: [FolderKey: OpenFolder]` holds, for each open folder, its sorted items and its state (listing, listed, failed with a reason). A `FolderKey` is the folder's path relative to the top-level folder, as an array of names. A view asks the model for the children of a key; the model never builds a flat copy of the tree.
- KTD2. **A selection is a set of URLs as before, and is matched through the key.** The URL of an item is whatever the listing reported, and a listing's items sit under the folder the listing followed. `BrowserModel.matching` becomes a function of the tree: a wanted URL is first made relative to the location as spelled, then to the root the first listing reported, and the remainder is looked up as a key. A wanted URL under neither prefix matches a top-level item by its last component, which is today's rule and what Enclosing Folder and the tests need. Alternatives rejected: storing keys in the public `selection` (changes `BrowserHistory`, the toolbar tests and every caller for no gain here) and matching by suffix (a nested `b/x` also matches a top-level `x`).
- KTD3. **Opening and closing are synchronous model commands, like moves.** `open(_ key:)` marks the folder open and starts its listing; `close(_ key:)` removes it and everything under it, drops their selection, and retires their listings and watches. Both change state as the command arrives, and only the listing runs in a task, for the reason in `docs/solutions/2026-10-10-check-then-act-across-a-task-boundary.md`.
- KTD4. **Each open folder lists through the reader's `items(in:)` and arranges through the same `FileItemSort`, off the main actor.** `items(in:)` waits for the all-items event, so the rows an open folder publishes are always sorted (R3). The listing is a task owned by the open folder; it carries the tree's generation and the folder's own token, and checks both and its cancellation after every wait (the rule of `docs/solutions/2026-10-10-a-load-that-publishes-twice.md`). A move or a load of the top level bumps the generation and so retires every open folder's listing; a close removes the folder's token.
- KTD5. **A failed open folder keeps its place and shows a status row.** The state `.failed(reason)` is part of the open folder, so the same refresh that lists a folder again after a failure (step 4's KTD14) brings its rows back. The view draws a status row beneath it as a child that is not an item (KTD11).
- KTD6. **One sort, applied to every level.** `FileItemSort` gains two keys, `sizeOnDisk` and `dateAdded`. A change of sort re-arranges the top level and every listed open folder in one off-main pass (`arrangeTree`), and publishes once, as a new kind of publish (`.resort`) that scrolls the first selected row into view like a load does. The pass checks the generation after each level so a move retires it.

**Live updates for open folders**

- KTD7. **One watch per open folder, from the unchanged `FolderWatching` protocol.** Step 4 left this question here and built the watcher to take one folder per stream. The model holds one watch session per watched key. All sessions feed one dirty set and one answering task, so refreshes of different folders run one at a time and never overlap (the single-answerer rule of step 4's KTD8 extended from one folder to many).
- KTD8. **A refresh is per folder, and the load rules apply to the tree.** A signal marks one key dirty. The answerer takes a dirty key, reads that folder through `items(in:)`, arranges it, compares it with the rows shown (`differs(from:)`), and publishes only if they differ or a failure changed. A refresh reads the tree's generation and the folder's token and never changes either, so a move, a load, a close or a newer open retires it and it can never retire one of them. A signal that arrives while the top level is loading is owed and paid when the load settles (step 4's KTD11), for every key. A load clears what is owed, because its listing begins after every signal so far.
- KTD9. **The watch of a folder starts when the folder is opened and every start is followed by a look** (step 4's KTD12). A folder opened while the browser is not on screen is listed and not watched; it is brought up to date when the browser comes back, by the same look. Watching is off for the whole tree when `stopWatching()` is called, and each session ends with its folder.

**The outline (`BrowserUI`)**

- KTD10. **`NSOutlineView` replaces `NSTableView` in `BrowserViewController`, and the data source answers from the model.** `outlineView(_:numberOfChildrenOfItem:)` and `child(_:ofItem:)` read `items` and `openFolders`. `NSOutlineView` is an `NSTableView`, so the controller's identifier, columns, selection and double-action code carries over. The outline column is Name; its cell leaves room for the system's indentation and triangle.
- KTD11. **Outline items are small reference objects with the identity of their key.** AppKit's item handle must be a class instance and must stay equal across a reload so that open rows stay open. A node is an `NSObject` whose `isEqual` and `hash` are its key and whose item is looked up in the model when drawn. The view keeps no copy of the rows: a node is a handle, and the status row of KTD5 is a node of a second kind.
- KTD12. **Reloading is per folder, and open rows are re-opened from the model.** A refresh reloads only the folder that changed (`reloadItem(_:reloadChildren:)`, or the root with `reloadData()`), then re-opens, top down, the nodes the model says are open, with no animation. A reload that changes nothing is not done (step 4's R5). The probe of U1 settles whether a root `reloadData()` keeps the scroll offset and first responder as it did for the table (step 3's probe), and if it does not, the model's publish carries the key and the view reloads that folder alone.
- KTD13. **Header clicks write the model's sort through sort descriptors.** Each sortable column has a `sortDescriptorPrototype` whose key is the column's identifier. `outlineView(_:sortDescriptorsDidChange:)` reads the first descriptor into `FileItemSort` and asks the model to re-arrange. The outline's own indicator is set from the model, so a sort set in code (a test, a later restoration) shows in the header.
- KTD14. **"Keep Folders on Top" is a menu command on the responder chain.** The View menu item has the action `toggleFoldersFirst(_:)`, handled by the showing browser, validated like Back and Forward, with the checkmark set from the model's sort. The menu is built in the app delegate beside the Go menu. A menu item is not given an accessibility identifier by the system either; if the probe shows UI tests cannot find it by title, the item is found through the menu bar by its title, which is fixed text.
- KTD15. **Two more resource keys on every item, read in the listing.** `FileItem` gains `allocatedSize: Int64?` (from `.totalFileAllocatedSizeKey`, a file only, like `size`) and `dateAdded: Date?` (from `.addedToDirectoryDateKey`). Reading them with the others keeps "building an item never makes another file-system call" true. Whether they cost first rows anything is measured in U1 before anything else is built. If they do, the fallback is to read them only while their column is shown or sorted, which is a second listing mode for the reader and is a change to the plan, not a decision to take silently.
- KTD16. **Type-to-select uses the delegate's string for a row.** `outlineView(_:typeSelectStringFor:item:)` returns the item's name; AppKit does the matching, the pause and the timing. Rows inside closed folders are not in the outline, so they are not searched (R14).

**Proof**

- KTD17. **Four layers of tests.** `FileItem`, the reader and the sort are tested in `FileSystemCore` without a view. The tree is tested in `BrowserModel` with the stub reader's gates and the stub watcher, one new hook per kind of arrival, no clock. The controller is tested in a window with a real `NSOutlineView`. The end-to-end tests prove the wiring in the running app.
- KTD18. **The probes are tests that are kept.** U1's questions about AppKit are answered by tests in `BrowserUITests` that run the behavior in a window, so they keep guarding it on macOS 15, 26 and 27, as step 3's probe of `reloadData` did. A probe that cannot be kept is recorded in the lessons note with its numbers.

**What a history entry remembers, and the setting**

- KTD19. **A history entry carries the keys of the folders that were open.** `BrowserHistory.Entry` gains `openFolders: Set<FolderKey>`, and `visit`, `goBack` and `goForward` take it beside the selection with an empty default, so existing callers and `BrowserHistoryTests` compile and behave as before. The model captures it as the move is made, from the same place it captures the selection (`selectionWanted`). It is always stored; whether it is used is decided on arrival (KTD22).
- KTD20. **Restoring is one task per arrival, started when the top level settles, and it uses the same listing path as the user's own open.** The task takes the remembered keys shallowest first, and for each key whose parent is open and listed and whose name is a folder in the parent's rows, opens it through the path of KTD3 and KTD4 and waits for it before the next. A key that does not resolve is dropped without a message. It carries the tree's generation and checks it, the task's cancellation and the key's own token after every wait, so a move, a load, a newer arrival or a user's close retires it, and a user's open of a key it holds is a no-op for the restore.
- KTD21. **The selection comes back in two parts.** The top-level part is matched when the top level settles, as in steps 1 to 4. The part inside open folders is matched as each folder's rows appear, from the same remembered set, and only while the user has not selected since the move (the rule `selectionWanted` already holds). The remembered set is released when the pass ends or is retired.
- KTD22. **The setting is a small type with an injectable store.** `BrowserSettings` in `BrowserUI` holds `rememberOpenFolders`, backed by `UserDefaults` under a named key with a registered default of true, and takes the defaults object in its initializer as `InitialLocation.resolve(defaults:)` does. The model is given one and reads it on a Back or Forward arrival. A test passes a suite of its own; the app passes the standard defaults. Nothing observes the value: it is read when it is needed.
- KTD23. **A Settings window hosted in AppKit, and an accessibility check that covers SwiftUI.** `App/` gets a window controller that hosts one SwiftUI view in an `NSHostingController` (the arrangement `CLAUDE.md` names for settings), opened by Settings… in the app menu with Command-comma. The checkbox gets its identity from a SwiftUI `apply(_:)` that `Accessibility.swift` declares beside the AppKit one, and the element is added to `AccessibilityElement.all`. `scripts/check-accessibility.sh` learns the SwiftUI spellings (`.accessibilityIdentifier(` and `.accessibilityLabel(`) outside the helper file, with a must-fail case for each in `scripts/test-source-checks.sh`.

### High-Level Technical Design

The model's data, with two open folders:

```text
location: ~/Projects                      items (top level, sorted)
                                          ├─ Cairn/            key []        open
                                          │   ├─ Packages/     key [Cairn]   open
                                          │   │   ├─ BrowserUI/               (closed)
                                          │   │   └─ FileSystemCore/          (closed)
                                          │   └─ README.md
                                          └─ notes.txt

openFolders:
  [Cairn]           → items [Packages, README.md], state listed
  [Cairn, Packages] → items [BrowserUI, FileSystemCore], state listed
sessions (one watch each): [], [Cairn], [Cairn, Packages]
selection: { …/Cairn/Packages/BrowserUI }   found by key [Cairn, Packages, BrowserUI]
```

What happens, by arrival:

| Arrival | Which folder | Rows published | Load counter |
| --- | --- | --- | --- |
| A load of the top level (open, Back, Open) | top | First rows, then sorted rows, as step 3 | Bumped; every open folder is retired and cleared |
| The user opens a folder | that folder | Its sorted rows, once | Not changed; the folder has its own token |
| The user closes a folder | that folder and inside it | The outline without them | Not changed; their tokens and watches end |
| A signal from a watch | the folder's key | Its sorted rows, if changed | Read, never changed |
| A click on a header, or Keep Folders on Top | every listed level | All rows, once, in the new order | Read; a move retires it |
| A signal while the top level is loading | any | Nothing; owed, paid when the load settles | |
| Back or Forward to an entry with open folders, setting on | each remembered folder, shallowest first | Its sorted rows, once per folder, after the top level settles | Bumped by the move; the restore reads it and never changes it |

A session, in outline (directional, not an implementation):

```text
open(key): mark open; start the folder's listing task with (generation, token)
  listing: items = try await reader.items(in: folder)         stop unless still wanted
           sorted = try await arrange(items, sort, hidden)    stop unless still wanted
           publish the folder's rows; start its watch if watching
close(key): remove it and every key beneath it; end their tasks and watches; drop their selection
signal(key): mark key dirty; the answerer takes keys one at a time
  refresh(key): the same pass as step 4, for that folder; publish with the key
load(): generation += 1; clear open folders' tasks; (open folders stay open: they are listed again
        after the top level settles, one at a time, with the same rules)
```

### Assumptions

These are unconfirmed bets. Each names what changes if the user decides otherwise.

- **Quality bar 6.** The text of quality bar 6 is not in the repository (step 1's plan said the same), and the Claude Doc that holds it could not be read during planning. R1 to R32 are assumed to cover it.
- **Open folders are remembered per history entry, and the setting is on by default** (R33 to R36), at the user's request. All open folders are kept, with no cap; an entry's memory is the names of its open folders and lasts as long as the history does, at most 100 entries. Only Back and Forward restore (R35); a place reached by Open or Enclosing Folder starts closed.
- **The remembered folders open one at a time, shallowest first** (KTD20). An entry with many open folders is restored as fast as they list, one after another.
- **The setting is read when the move is made and is global** (R36), not per window or tab, and is kept in the standard user defaults under a name that no other part of the app uses.
- **The Settings window holds one checkbox** (R37). Its wording, "Open folders again when going back or forward", is a first draft and is not final copy.
- **"Keep Folders on Top" is off by default** (R12), which is what the list does today (`FileItemSort.foldersFirst` defaults to false).
- **A symbolic link to a folder is not opened in place** (R1), the same as Open today.
- **No placeholder while a folder is being listed** (R3). A folder that takes long to list shows an open triangle and nothing under it until it settles; a spinner row would be added if that reads as broken.
- **The sort and folders-first belong to the tab** (R13), as the selection and history do.
- **A close with a selected item inside moves the selection to the folder** (R8), so keyboard focus is not left on a row that is gone.
- **All five columns are shown** (R11). Hiding some is part of view settings (step 10); a narrow window scrolls horizontally, as it does now.
- **A folder of 10,000 items opens in well under 0.2 s off the main actor**, from step 3's measurements (listed in 45 ms, sorted in 31 ms). A larger one takes longer and is not judged (R29).
- **A stream per open folder is cheap enough.** No limit on streams per process was looked up while planning. U3's test opens fifty folders at once, and a stream that cannot start is logged and leaves that folder without live updates (step 4's R20).
- **No spoken announcement is added for opening, closing or refreshing** (R25); the system describes an outline row and its state.
- One new end-to-end launch is added and the existing launches are changed to query an outline (U6).

### Open Questions

None blocks the plan. Each is behavior that planning read about and did not run; the named test settles it, and the fallback is already chosen.

- **Does reading `.totalFileAllocatedSizeKey` and `.addedToDirectoryDateKey` with the others change the time to first rows of a 10,000-item folder?** U1's measurement decides. If it adds more than 20 ms, KTD15's fallback applies and the plan is revised before U3.
- **How long does `NSOutlineView.reloadData()` take with 100,000 top-level rows, and does it keep the scroll offset, first responder and the open rows?** U1's probe decides. If the time is more than a frame (about 16 ms) or the offset is lost, KTD12's per-folder reload carries the step and the root is reloaded only on a load.
- **Does `outlineView(_:typeSelectStringFor:item:)` apply in a view-based outline on macOS 15, 26 and 27, with the Name column not first?** U5's test decides. If it does not, the controller handles the key itself with a short-lived buffer.
- **How does `XCUIApplication` see the outline?** The end-to-end tests use `app.tables[...]` today. U6's first test finds out whether the outline is an `outline`, a `table` or both on each macOS, and the tests use whichever query is stable.
- **Does a SwiftUI view hosted in an AppKit window, with an identifier from `apply(_:)`, show up to `XCUIApplication` by that identifier on macOS 15, 26 and 27, and does the audit pass on it?** U4's end-to-end test decides. If the identifier is not found, the checkbox is found by its title, which is fixed text, and the plan records the exception.
- **What does VoiceOver say for a row's level and state, and when a folder opens?** U6's by-hand check records it.

### Risks

| Risk | Mitigation |
| --- | --- |
| The outline view materializes an item object for every top-level row on a reload, and a 100,000-item folder pays for it on the main actor. | U1 measures it before anything is built. Fallbacks: reload only changed folders (KTD12), and have the data source answer lazily; a result above one frame is a stop condition. |
| The two new keys slow listing. | Measured first (U1); the fallback is KTD15's second listing mode. |
| An open folder's refresh races a move, a load, a close and another refresh. | Every arrival checks the tree's generation and the folder's token after every wait, and refreshes run one at a time (KTD4, KTD8). U2 holds each stage with a gate and moves, closes and reloads at it. |
| Two files with the same name in different open folders select each other. | Selection is looked up by key (KTD2); U2 has the scenario. |
| Many open folders mean many streams, and one that fails to start leaves a folder stale. | A watch that cannot start is logged and the folder works without live updates (step 4's R20); the look at every open covers the gap. A test opens many folders at once. |
| An outline reload loses VoiceOver's place or re-reads rows. | R5 of step 4 (no publish without a visible change) and per-folder reloads keep reloads rare; judged by hand in U6, and a failure is a stop condition. The VoiceOver check that step 4 skipped is still open and is repeated here. |
| UI tests find the list by type and break on the outline. | U6 starts with the query probe; the helper that finds the list is one function the tests share. |
| `swift-format` and the accessibility check reject a pattern the outline needs. | `scripts/check-accessibility.sh` forbids setting an identifier or a label outside `Accessibility.swift`; every new column and cell goes through an `AccessibilityElement`. |
| A restore applies stale keys: a folder renamed or replaced by a file since the entry was written. | A key that does not resolve to a folder in its parent's rows is dropped without a message (KTD20); U4 has the scenarios. |
| A restore races the user's own first actions on the arrival. | The user's open, close and selection win and the restore stops asking about keys they changed (R38, KTD20, KTD21); U4 holds each stage with a gate. |
| An entry with many open folders makes Back feel slow. | One at a time, shallowest first, each published as it lists, so the top level is shown at once and deeper levels fill in; revisit in parallel if measured slow. |
| The first settings window and the first SwiftUI in the app change build or audit behavior on the three macOS versions. | The window is small and its test runs in the macOS 15 workflow; the accessibility check is extended so SwiftUI cannot skip the convention. |
| The development Mac is busy when `make perf` runs and shows false regressions. | Check `uptime` first and repeat a flagged result once, as in `docs/solutions/2026-10-11-live-updates-notes.md`. |

---

## Implementation Units

### U1. The two new keys, and the probes that decide the rest

- **Goal:** `FileItem` carries Size on Disk and Date Added, the sort can order by them, and the questions about cost and `NSOutlineView` are answered before the model changes.
- **Requirements:** R11, R22, R23, R28
- **Dependencies:** none
- **Files:**
  - `Packages/FileSystemCore/Sources/FileSystemCore/FileItem.swift`
  - `Packages/FileSystemCore/Sources/FileSystemCore/FileItemSort.swift`
  - `Packages/FileSystemCore/Tests/FileSystemCoreTests/FileItemTests.swift` (new or the existing item tests)
  - `Packages/FileSystemCore/Tests/FileSystemCoreTests/FileItemSortTests.swift`
  - `UITests/PerformanceTests.swift`
  - `Packages/BrowserUI/Tests/BrowserUITests/OutlineBehaviorTests.swift` (new)
- **Approach:**
  1. Add `allocatedSize` and `dateAdded` to `FileItem`, to `resourceKeys` and to `init(url:resourceValues:)`, with the same rules as `size` (a file only). Add `sizeOnDisk` and `dateAdded` to `FileItemSort.Key` with the same nil rules as the existing keys (a folder has no size and sorts first).
  2. Run the listing performance tests with and without the two keys on the reference Mac and write both sets of numbers into the lessons note. Add the 10,000-item first-rows run to the record.
  3. Write the kept probes of KTD18 as tests: a root `reloadData()` of an outline with 100,000 top-level rows (time, scroll offset, first responder, open rows), and a per-folder `reloadItem` of one open folder.
- **Execution note:** Run step 2 and the probes first and stop if they hit the stop conditions in the Goal Capsule, before any model change.
- **Patterns to follow:** `FileItem(url:resourceValues:)` and `FileItem.resourceKeys`; the sort's thread-recording test; step 3's probe of `reloadData` (`plans/phase-1a-step-03-fast-first-rows.md`, KTD9).
- **Test scenarios:**
  - A file's `allocatedSize` and `dateAdded` are read through the listing; a folder's, a package's and a symbolic link's are nil.
  - Sorting by `sizeOnDisk` and by `dateAdded` orders ascending and descending, with the name as the tie-break and nil values first; `foldersFirst` groups folders in either direction.
  - A sparse file has an allocated size far below its logical size (the fixture builder has one).
  - Equal listings that differ only in `dateAdded` or `allocatedSize` are different for `differs(from:)`.
- **Verification:** The numbers of step 2 are in the plan's stop-condition range or the plan is revised. The probes run on macOS 27 locally; the kept ones run on macOS 26 in CI and on macOS 15 by hand.

### U2. The tree in the model

- **Goal:** `BrowserModel` can open and close folders in place, list and arrange them off the main actor, keep a selection across levels, and apply one sort to all of them, under the rules of steps 3 and 4.
- **Requirements:** R2 to R10, R16, R18 to R20, R29
- **Dependencies:** U1
- **Files:**
  - `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`
  - `Packages/BrowserUI/Sources/BrowserUI/OpenFolder.swift` (new)
  - `Packages/BrowserUI/Tests/BrowserUITests/BrowserModelTreeTests.swift` (new)
  - `Packages/BrowserUI/Tests/BrowserUITests/StubReader.swift`
- **Approach:**
  1. Add the open folders, their keys and states (KTD1, KTD5), `open(_:)` and `close(_:)` (KTD3), the per-folder listing (KTD4), `arrangeTree` and the sort setter (KTD6), and the generalized `matching` (KTD2).
  2. `load()` keeps its behavior for the top level. After it settles, open folders that were open before it are listed again, one at a time, so a reload keeps what was open (R5). A move closes everything (R5, R20).
  3. The `Publish` enum gains cases for a folder's rows and for a re-sort; `onChange` is unchanged and a new `lastChangedFolder` says which key a folder publish was about.
  4. Opening and closing are `openFolder(_:)` and `closeFolder(_:)`, because `open(_:)` already means opening an item as a move. A sort change is `changeSort(to:)`, which re-arranges every listed level in one off-main pass; assigning `sort` directly still only affects the next load.
  4. `StubReader` gains per-folder gates so a test can hold one open folder's listing while another is released.
- **Execution note:** Write each scenario first and see it fail against a model without the behavior. The existing `BrowserModelTests` and `BrowserModelWatchTests` are the characterization and stay green throughout (R30).
- **Patterns to follow:** `reloadingKeepsTheRowsUntilTheSortedResultReplacesThem`, `whileTheSortIsHeldTheMainActorIsFreeAndANewerLoadWins` and `arrangeHeldOnce(at:)` for holding a stage; `aMoveRetiresTheLoadInFlightBeforeTheNextLoadStarts` for a move with no load after it; the two-sends-no-await tests of the check-then-act note for commands.
- **Test scenarios:**
  - Opening a folder lists it, sorts it, and publishes its rows once; the top-level rows, selection and state are untouched; history is unchanged.
  - Opening a folder with the same name as one in another open folder keeps the two lists apart.
  - Open sent twice with no await between lists the folder once; Close sent right after Open leaves it closed and publishes nothing for it when released.
  - A folder that fails to list stays open with `.failed(reason)`; a second open of it does nothing; a later listing that succeeds publishes its rows.
  - Closing a folder removes the keys beneath it, ends their tasks, and drops their selected items from the selection; if one was selected, the folder is.
  - A selection that holds `a/x` and a top-level `x` keeps both through a refresh of either folder, and selecting `x` in one open folder does not select `x` in another.
  - A selection given as a URL with the location's spelling and one with the listing's spelling both find the same item at every level; a URL under neither finds the top-level item of that name.
  - The sort changes: every listed level is re-arranged, one publish is made, the selection stays, `foldersFirst` groups at every level in both directions, and a move while the pass is held at level two publishes nothing.
  - A move while an open folder's listing is held at the reader, and separately at the sort: nothing is published, the folder is no longer open, and its watch has ended.
  - A load of the top level while a folder is open lists the top level, then lists the open folder again; what was selected inside it is still selected; a signal during the load is owed and paid once per key.
  - Hidden items are filtered at every level when `showsHiddenFiles` is off. A change of the flag takes effect at the next load, as it does for the top level, and the open folders stay open and are listed again with it (the model keeps only visible rows, so it cannot re-filter without a listing).
  - While the sort of an open folder is held, the test, which runs on the main actor, reads the model and sends it a move.
  - Every existing test in `BrowserModelTests` and `BrowserModelWatchTests` passes unchanged.
- **Verification:** No scenario waits on time; each waits on a gate, a hook, or the stub's end-of-stream. Each has been seen to fail once.

### U3. Live updates for the open folders

- **Goal:** Every open folder is watched and kept current by step 4's rules, and a refresh of one level changes only that level.
- **Requirements:** R17, R18, R20, R21, R27
- **Dependencies:** U2
- **Files:**
  - `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`
  - `Packages/BrowserUI/Tests/BrowserUITests/BrowserModelTreeWatchTests.swift` (new)
  - `Packages/BrowserUI/Tests/BrowserUITests/StubWatcher.swift`
  - `Packages/BrowserUI/Tests/BrowserUITests/LiveUpdateTests.swift`
- **Approach:**
  1. Replace the single session of `BrowserModel` with a session per watched key (KTD7), one dirty set and one answerer (KTD8). A move ends every session; opening a folder while watching starts its session; closing ends it.
  2. `refresh` takes a key. The top-level folder is the key `[]` and behaves exactly as step 4's refresh does.
  3. `StubWatcher` records which folders were asked for, per folder, and lets a test await the end of each folder's stream.
- **Execution note:** Step 4's watch scenarios are the characterization: each is re-run with the folder as key `[]` before the new ones are added.
- **Patterns to follow:** `BrowserModelWatchTests` (held refreshes, owed signals, stream ends), `LiveUpdateTests.watchingModel(on:)` and its wait for quiet.
- **Test scenarios:**
  - Opening a folder while watching asks the watcher for that folder once; closing it ends the stream; a move ends every stream and asks for the new folder's.
  - A signal for an open folder with a changed listing publishes that folder's rows once; the top-level rows, other folders and the selection are untouched; the publish names the key.
  - A signal whose listing is the same publishes nothing.
  - Signals from two folders while a refresh is held are answered one at a time, one refresh each, with no overlap.
  - A signal for an open folder while the top level loads is owed, and is paid once when the load settles.
  - An open folder that is deleted: its parent's refresh removes it and its subtree and their watches end; its selection is dropped. A signal for the vanished folder that was in flight publishes nothing.
  - A folder that cannot be listed on a signal shows `.failed(reason)` once; the same failure again publishes nothing; a later successful listing publishes the rows.
  - Many folders (fifty) opened in a row each start a watch; one whose stream cannot start leaves the others working and the browser unharmed.
  - Real stream, in `LiveUpdateTests`: a file created inside an open folder of a fixture shows in that folder's rows within 1 s, with the selection and the open state kept.
- **Verification:** No scenario of the stub layer waits on time. The real-stream tests pass ten runs in a row on the development Mac before the pull request is opened.

### U4. History remembers what is open, and a setting for it

- **Goal:** Back and Forward open again the folders that were open in the place returned to, as the user's setting says, and the setting has a window to be changed in.
- **Requirements:** R33 to R38
- **Dependencies:** U2, U3
- **Files:**
  - `Packages/BrowserUI/Sources/BrowserUI/BrowserHistory.swift`
  - `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`
  - `Packages/BrowserUI/Sources/BrowserUI/BrowserSettings.swift` (new)
  - `Packages/BrowserUI/Sources/BrowserUI/SettingsView.swift` (new)
  - `Packages/BrowserUI/Sources/BrowserUI/Accessibility.swift`
  - `App/SettingsWindowController.swift` (new), `App/MainMenu.swift`, `App/AppDelegate.swift`
  - `scripts/check-accessibility.sh`, `scripts/test-source-checks.sh`
  - `Packages/BrowserUI/Tests/BrowserUITests/BrowserHistoryTests.swift`
  - `Packages/BrowserUI/Tests/BrowserUITests/BrowserModelRestoreTests.swift` (new)
  - `Packages/BrowserUI/Tests/BrowserUITests/BrowserSettingsTests.swift` (new)
  - `Packages/BrowserUI/Tests/BrowserUITests/SettingsViewTests.swift` (new)
- **Approach:**
  1. Add `openFolders` to `BrowserHistory.Entry` and the three history calls (KTD19). The model captures the open keys in the same places it captures the selection for a move.
  2. Add the restore task, started after a Back or Forward load settles when the setting is on (KTD20, KTD21), and the two-part selection restore.
  3. Add `BrowserSettings` (KTD22) and give the model one through its initializer, with the standard defaults supplied by the real initializers and a suite supplied by tests.
  4. Add the Settings window, its menu item and its accessibility element, and extend the accessibility check (KTD23).
- **Execution note:** Write each model scenario first and see it fail against a model that does not restore. The history tests are the characterization for the entry change and stay green throughout.
- **Patterns to follow:** `BrowserHistory.Entry`'s `selection` through `visit`, `goBack` and `goForward`; `InitialLocation.resolve(defaults:)` and its tests for a suite of defaults; the held-stage tests of U2; the must-fail cases in `scripts/test-source-checks.sh`.
- **Test scenarios:**
  - History: an entry keeps the open keys it was given, and an entry made without them has none; going back and forward moves them with the selection; the limit of 100 drops them with the entry.
  - A move captures the keys open at that moment, and opening or closing afterwards in the new folder changes nothing in the entry left.
  - Back with the setting on: the top level settles, then the remembered folders open shallowest first, each published once; the selection inside them returns as their rows appear; the load counter is read and never changed by the restore.
  - Back with the setting off: the outline is closed and the top-level selection is restored by name as before. An entry made while the setting was off still holds the keys, so turning the setting on and then going Back restores them. (A Back consumes its entry, so going Back to the same entry a second time is not a thing.)
  - Forward restores the same way as Back. Open, Enclosing Folder and a new tab start closed whatever the setting says.
  - A remembered key whose folder was deleted, renamed, or replaced by a file is skipped, its children are skipped with it, and nothing is shown for it.
  - A folder that cannot be listed during a restore shows the status row of KTD5 and the rest of the restore goes on.
  - The restore is held at the first folder's listing: a move retires it and nothing is published into the new folder; a second Back sent with no await ends on the right folder with its own restore; a load of the same folder retires it and the load's rows stand.
  - While a restore is held at a deeper folder, the user closes its parent: the restore opens nothing under it. The user opens a remembered folder, then the restore reaches its key: the folder is not listed twice.
  - A selection the user makes during a restore is the selection kept; the remembered one is not applied over it.
  - The setting is read when the move is made: changing it between the move and the settle changes the next arrival and not this one.
  - `BrowserSettings`: unset defaults give true; a stored false gives false; a value written is read back from a suite; two suites do not see each other.
  - The accessibility check rejects a source file that calls `.accessibilityIdentifier(` or `.accessibilityLabel(` outside the helper, under a path with a space, and passes with the helper; `AccessibilityElement.all` holds the checkbox with a unique identifier and a label.
  - The Settings view hosts in a window and writes nothing until changed. Whether the checkbox is found by its identifier cannot be asked in process: SwiftUI builds its accessibility tree only when assistive technology asks, and an in-process search of the hosted view found nothing. That is U6's end-to-end question.
  - The restore is retired by a move even when the new place has a folder of the same name as a key still to be opened, and the user's own open of a remembered folder is not listed again by the restore.
  - Every existing test in `BrowserHistoryTests`, `BrowserModelTests` and `BrowserModelWatchTests` passes unchanged.
- **Verification:** No scenario waits on a clock. Each has been seen to fail once. The window and menu item are built and checked end to end in U6.

### U5. The outline

- **Goal:** The list is an `NSOutlineView` that draws the model, opens and closes folders, sorts by its headers, shows five columns, and keeps the selection, scroll offset and focus through every kind of publish.
- **Requirements:** R1 to R4, R6, R10 to R12, R14, R15, R18, R24, R25, R30
- **Dependencies:** U2, U3
- **Files:**
  - `Packages/BrowserUI/Sources/BrowserUI/BrowserViewController.swift`
  - `Packages/BrowserUI/Sources/BrowserUI/OutlineNode.swift` (new)
  - `Packages/BrowserUI/Sources/BrowserUI/Accessibility.swift`
  - `Packages/BrowserUI/Sources/BrowserUI/PaneViewController.swift`
  - `App/` (the View menu and its delegate)
  - `Packages/BrowserUI/Tests/BrowserUITests/BrowserViewControllerTests.swift`
  - `Packages/BrowserUI/Tests/BrowserUITests/OutlineViewTests.swift` (new)
  - `Packages/BrowserUI/Tests/BrowserUITests/AccessibilityTests.swift`
- **Approach:**
  1. Apply KTD10 to KTD14 and KTD16. `Column` gains `sizeOnDisk` and `dateAdded`, with titles, widths, accessibility elements, spoken missing-value text and sort keys. The status row of R4 is a second node kind.
  2. `AccessibilityElement` gains the two cells and the folders-first menu item's title is not a view, so it is declared as a constant beside the others and listed in `all` only if it is a view.
  3. `modelDidChange()` reads the kind of publish and the key and does the least reload that is right (KTD12). Scroll to the selection happens for a load, a re-sort and an open, never for a refresh (step 4's KTD13).
  4. The View menu gets "Keep Folders on Top", wired through the responder chain to the showing browser.
  5. `PaneViewController` needs no change beyond the types; its watch rules are the model's now.
- **Patterns to follow:** step 4's `applyModelSelection(scrollingToIt:)`, `browserShowingFirstRows(of:heldAt:)`, `theListKeepsItsScrollOffsetWhenItSettlesWithNothingSelected` and `keyboardFocusStaysWhereItIsThroughBothArrivals`; `AccessibilityTests` for the audit of a new screen.
- **Test scenarios:**
  - The list is an outline with identifier `file-list` and label `Files`, and has five columns titled Name, Size, Size on Disk, Date Modified and Date Added.
  - A folder row has a disclosure triangle and a file row has none; a package and a symbolic link have none.
  - Opening a folder from the model shows its rows indented under it; a refresh of the top level keeps it open; a refresh of its own folder leaves the top-level rows' scroll offset, selection and the first responder unchanged.
  - A selected row inside an open folder is selected at its new row after the top level gains a row above it; the table's selection change was not written back as the user's.
  - Closing a folder whose item was selected selects the folder.
  - Clicking a header sorts the model and shows the indicator; clicking again reverses it; the selected row is scrolled into view; every level is in the new order.
  - Keep Folders on Top toggles the model's sort, shows a checkmark when on, is validated off for a pane with no browser, and acts on the showing tab only.
  - Type-to-select: typing the start of a name selects the first matching visible row; a name inside a closed folder is not found; a pause starts a new search.
  - A missing size, size on disk and date added show dashes and are spoken as "No size", "No size on disk" and "No date added"; a folder's are the same.
  - A status row is not selectable and speaks its reason.
  - Open sent for a folder while an open folder's listing is held: the browser moves there, the outline is closed, and it ends loaded.
  - Every existing test in `BrowserViewControllerTests`, `PaneViewControllerTests`, `BrowserToolbarTests` and `AccessibilityTests` passes, except those that count columns or name the table type, which change as the plan lists.
- **Verification:** These tests pass on macOS 27 locally, on macOS 26 in CI and on macOS 15 in the manual run. The scroll scenario is seen to fail with a scroll into view left in for a refresh.

### U6. The running app

- **Goal:** The end-to-end tests prove the outline in the running app, and a person has checked what a test cannot.
- **Requirements:** R1, R10, R12, R14, R17, R24, R25, R29, R30, R34, R36, R37
- **Dependencies:** U5
- **Files:**
  - `UITests/BrowsingTests.swift`
  - `UITests/HistoryTests.swift`
  - `UITests/TabsTests.swift`
  - `UITests/AccessibilityTests.swift`
  - `UITests/PerformanceTests.swift`
  - `UITests/ListViewTests.swift` (new)
- **Approach:**
  1. Replace the `app.tables[...]` queries with one shared helper that finds the list by its identifier and by whichever element type the first test of this unit shows to be stable.
  2. `ListViewTests` is three new launches on a fixture with nested folders and files of different sizes: opening in place with sorting, Keep Folders on Top and typing; Open on a nested folder; and Back with the setting. The Settings window's audit closes the main window first, because `XCUIApplication` is the only thing that can be audited and the main window overlaps Settings.
  3. The accessibility audit covers the outline with a folder open.
- **Patterns to follow:** `HistoryTests.row(_:in:)`; `waitForRowCount` in `BrowsingTests`; the audit's retry and its narrow handler for system chrome.
- **Test scenarios:**
  - `ListViewTests`, one launch: the folder `Sub` is opened by its triangle and its rows appear indented; Right Arrow opens another and Left Arrow closes it; the runner creates a file in the open folder and it appears; Date Added is clicked and the rows reorder; Keep Folders on Top is chosen from the View menu and folders group first; typing a name selects its row; Command-Down on a folder enters it and the outline is closed there.
  - `ListViewTests`, restore: a folder is opened, another folder is entered, and Back shows the first with the same folder open and the same item selected. Settings is opened with Command-comma, the checkbox is cleared, the window is closed, and the same Back shows the folder closed. The checkbox is set again and the change holds after the app is relaunched.
  - The accessibility audit passes with a folder open, and on the Settings window, on every macOS version CI runs.
  - Existing end-to-end tests pass with the new query.
  - By hand, with VoiceOver on, in a folder with two open levels: what a row says for its level and its state, what is said when a folder is opened and closed, and that a refresh made from Terminal in an open folder is not announced and does not move VoiceOver. This is also the check that step 4 skipped; its seven items are repeated here for the top level and recorded.
  - By hand, without VoiceOver: a folder of 10,000 items is opened, the window answers a click meanwhile, and the time to its rows is written into the lessons note.
- **Verification:** The end-to-end suite grows by one launch. The by-hand results go into the lessons note, with the open Questions answered.

### U7. Documents and the curriculum page match the finished step

- **Goal:** The documents describe the app after U1 to U6, and the step has its teaching page.
- **Requirements:** R32
- **Dependencies:** U1 to U6, and the review step's fixes
- **Files:**
  - `ARCHITECTURE.md`
  - `README.md`
  - `CLAUDE.md`
  - `docs/curriculum/phase-1-step-05-list-view.md` (new)
  - `docs/curriculum/README.md`
  - `docs/solutions/<date>-list-view-notes.md` (new)
- **Approach:**
  1. `ARCHITECTURE.md`: add the tree to the model's description and a section on how a folder is opened in place and watched, beside "How a change on disk reaches the list"; say in "Tabs" that sort and folders-first belong to the tab; add the two keys to what a listing reads. Add what a history entry remembers, how a restore runs after Back or Forward, and the Settings window and its setting, where the app's structure is described.
  2. `README.md`: the status paragraph says folders open in place, columns sort, and Back and Forward open again what was open, with a Settings window to turn that off.
  3. `CLAUDE.md`: the status line says step 5 (list view, this plan's path) is done and step 6 is next, and says whether the VoiceOver checks of steps 4 and 5 were done.
  4. The curriculum page follows `docs/curriculum/README.md` and is written after the lessons note, from this plan, that note and the test results. Its index row goes in the Phase 1 table, and "Ideas that keep coming back" gains step 5 where a lesson recurs.
- **Test expectation:** none -- documents. `make lint` runs the governance check over them.
- **Verification:** Each document names only code that exists. The curriculum page states no fact that is not in the plan, the lessons note or a test result, and says what was left open.

---

## Verification Contract

| Gate | Where | Proves | Needs the user at the Mac |
| --- | --- | --- | --- |
| U1's measurements and probes | Local, reference Mac | The new keys and the outline cost what the plan assumes, before the model is changed | Yes, for the reference Mac's numbers |
| `make lint` | Local, then CI | Governance files and Swift formatting | No |
| `make test` | Local, then CI | U1 to U5's unit tests, `LiveUpdateTests` with the 1 s bound for an open folder (run alone, after the other suites: `TIMING_SUITES` in the `Makefile`), the source checks | No. Use `rtk proxy make test` for full output. |
| The real-stream tests, ten runs in a row | Local | They are stable before anything is built on them | No |
| `make uitest` | Local | The new launch, the changed queries and every existing test | Yes, to approve the authentication prompt. If it cannot be approved, the pull-request run is the proof. |
| `make perf` | Local, on the reference Mac | R28: first rows still met with the two keys read | Yes |
| VoiceOver and by-hand checks (U6) | Local | R25, and the step 4 checks that were skipped | Yes |
| Pull-request CI on `macos-26` | GitHub | Everything automated, on a second macOS and in a virtual machine | No. Watch it with `gh run watch`. |
| macOS 15 workflow, started by hand | GitHub, before the merge | AppKit and FSEvents behavior on the minimum macOS: the outline tests, the real-stream tests and every end-to-end test | No. `gh workflow run macos-15.yml --ref phase-1a/list-view`, on the same pushed commit. |

Everything local is finished before the first push. Plan one pull-request run and one macOS 15 run.

---

## Definition of Done

- U1 to U7 are complete, and every scenario listed under them exists as a test or, for the by-hand checks, has been done and written down (or has been named as skipped, with the date, in the lessons note and on the curriculum page).
- `make lint` and `make test` pass on the final tree.
- With the user at the reference Mac: `make perf` reports the first-rows target met with the two new keys read.
- The six Open Questions have answers in the lessons note.
- The review step has run over the whole step diff and its findings are fixed or answered.
- The lessons step has recorded what the step taught in `docs/solutions/`.
- `docs/curriculum/phase-1-step-05-list-view.md` exists and `docs/curriculum/README.md` lists it.
- `CLAUDE.md` says step 5 is done and step 6 is next.
- No abandoned attempt remains in the diff, and no probe file is in the repository other than the kept probes of KTD18.
- The branch `phase-1a/list-view` holds one commit named `Phase 1 step 5: list view`.
- A pull request is open, its CI run is green, the macOS 15 run started by hand on the same commit is green, and it is merged only then.
- The pull request's diff touches nothing under `.github/workflows/` and does not change existing numbers in `docs/performance/baseline.json`.

---

## Sources

- `plans/phase-1a-browse.md`: the step 5 row, and the order notes that put fast first rows and live updates before the outline.
- `plans/phase-1a-step-04-live-updates.md`: KTD1 (one stream per folder, so step 5 can ask once per open folder), KTD8 to KTD12 (the session, the pass, the counter, the owed signal), "Scope Boundaries" (watching open folders is this step's), and "Considered and not built" (a table reload keeps the scroll offset and focus; step 5 replaces the table).
- `plans/phase-1a-step-03-fast-first-rows.md`: the first-rows target and its measurements (10,000 items listed in 45 ms and sorted in 31 ms), and the probe of `reloadData`.
- `plans/phase-1a-step-01-navigation-history.md`: quality bar 6 is not in the repository.
- `Packages/BrowserUI/Sources/BrowserUI/BrowserHistory.swift`: an entry holds a location and a selection, and `visit`, `goBack` and `goForward` take the selection of the place being left.
- `Packages/BrowserUI/Sources/BrowserUI/InitialLocation.swift` and `App/MainMenu.swift`: the only existing use of `UserDefaults` takes the defaults object as an argument; the app has no Settings window or View menu yet.
- `CLAUDE.md`: settings are SwiftUI hosted in AppKit.
- `docs/solutions/2026-10-11-live-updates-notes.md`: the load counter is read and never changed by a refresh; give the C API ownership of a callback; wait for quiet in a real-stream test; check `uptime` before believing a performance regression.
- `docs/solutions/2026-10-10-a-load-that-publishes-twice.md` and `docs/solutions/2026-10-10-check-then-act-across-a-task-boundary.md`: check after every wait, retire at the move, change state as the command arrives.
- `docs/solutions/2026-10-09-navigation-history-notes.md`: a selection is matched by name because a listing spells a folder differently from its location; programmatic selection needs the flag; ask macOS 15 and macOS 26 before trusting AppKit.
- `docs/solutions/2026-10-09-accessibility-notes.md`: cells that show changing text get an identifier only; the audit's findings differ between macOS versions; give overlaid text an opaque background.
- `docs/solutions/2026-10-09-performance-baseline-notes.md`: a performance test needs no registration; record a new baseline only on the reference Mac.
- Current source read for this plan: `FileItem`, `FileItemSort` and `differs(from:)`; `DirectoryReader` and `DirectoryReading.items(in:)`; `BrowserModel` (`load()`, `prepareToShow(selecting:)`, `matching(_:in:)`, the watch session); `BrowserViewController` (columns, cells, `modelDidChange()`, `applyModelSelection`); `Accessibility.swift` and `scripts/check-accessibility.sh`; `UITests/AccessibilityTests.swift` (the `app.tables` queries).
