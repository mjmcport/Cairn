---
title: Phase 1A Step 7 Column View - Plan
type: feat
date: 2026-10-13
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Phase 1A Step 7 Column View - Plan

## Goal Capsule

- **Objective:** A tab can show its folder as columns. Selecting a folder shows what it holds in the next column to the right, and so on as deep as the person goes. Selecting a file shows a preview in the last column: a large picture where there is one, and its name, kind, size, dates and whether it is on this Mac. Everything the list and the icon view already do for the folder (selection, sort, hidden files, history, live updates, keyboard) works the same.
- **Means:** An `NSBrowser` driven by the model's tree of open folders, so the columns to the right of a selection are the open folders on its path (KTD1 to KTD4), a preview view controller for the last column built on the icon view's thumbnail loader (KTD5 to KTD7), and a third view mode with its View-menu command (KTD8 to KTD9).
- **Authority:** R1 to R26 come from the step's row in `plans/phase-1a-browse.md` ("`NSBrowser` with a preview column"). Where a KTD and an R disagree, the R wins. Requirements marked "default" are unconfirmed bets listed under Assumptions.
- **Execution profile:** Almost all in `BrowserUI`: a model rule for a third mode and for the open chain, an `NSBrowser` controller, a preview controller, a menu item, tests, and an end-to-end launch. `NSBrowser` is the oldest control in AppKit; how it behaves with an item-based delegate, in an audit, and with a large folder is read about, not measured, so U1 is a probe unit.
- **Stop and tell the user when:**
  - the `NSBrowser` cannot be made to follow the model's open chain without a loop of selection and reload that U1's probe cannot break;
  - the audit finds something in the browser's own columns that cannot be fixed from the app (a system control's description);
  - a column with 100,000 items takes more than one frame to appear or blocks the main actor for more than one frame in a probe, and a limit on the column does not fix it;
  - a real-stream or timing test fails some of the time: do not loosen or drop it;
  - UI automation is needed and the authentication prompt has not been approved;
  - a unit test fails on macOS 15 or macOS 26 only;
  - a fix would need a change under `.github/workflows/`.
- **Who finishes:** The implementer lands U1 to U6 on branch `phase-1a/column-view`, runs the lessons and curriculum steps, makes the commit or commits, opens the pull request, starts the macOS 15 run by hand, and asks the user before merging.

---

## Product Contract

### Summary

Phase 1A step 7 adds the column presentation. View > as Columns (Command-3) shows the showing tab's folder as a row of columns. The first column lists the folder. Selecting a folder in a column makes the next column list it, and the open folders on that path are the model's own open folders, so what the list shows open is what the columns show. Selecting a file shows its preview in the column after it. Nothing is listed again by a switch of mode.

### Problem Frame

Three things in the current source shape the work:

- **The model already holds a tree of open folders, listed and watched.** Step 5 built it for the outline, and the icon view (step 6) shows only its top level. A column view shows a *path* through the same tree: the chain of folders from the shown folder to the selected one. The model needs no new data, only a rule for which open folders belong to the path.
- **A selection in a column is a navigation in the model's tree.** Selecting a folder must open it (so it is listed and watched) and close the folders that were open beside or beyond another branch. Doing that from the browser's selection callback, while the browser also reloads from the model, is the loop to avoid.
- **A preview needs a large picture and a few facts.** The icon view's loader and cache make pictures of a fixed size. A preview asks for a larger one, once, for one file.

### Requirements

**The mode**

- R1. View > as Columns and Command-3 choose the columns for the showing tab, checked and enabled like as List and as Icons. The mode belongs to the tab and is not remembered after a quit (step 10's).
- R2. Switching to columns keeps what is selected: the folders that lead to the selected item stay open and are shown as columns, other open folders are closed. Switching away to the list leaves the open folders open; switching to icons closes them as before.
- R3. Switching lists nothing again, changes nothing about where the browser is, and takes no longer than drawing what is on screen.

**The columns**

- R4. The first column lists the folder being shown, with the same names, order, hidden-file filter and sort as the list. Each item has its type's icon and its name; a folder shows that it has contents to show.
- R5. Selecting a folder shows its items in the next column, through the model: the folder is opened (listed and watched) and the folders opened beside or beyond another branch are closed. A folder that cannot be listed shows why, in its column.
- R6. Selecting a file, or several, in a column shows a preview to its right: one file's picture and facts, or the count and total size of several.
- R7. Selection works as in the list: click, Command-click, Shift-click within a column, and the keyboard: Up and Down within a column, Right into the selected folder's column, Left back to the one before. The model's selection is what is selected in the last column.
- R8. Opening a folder (double-click or Open) enters it as a move, as in the other presentations, and the columns start again at that folder. Opening a file does nothing yet.
- R9. Typing selects the first name in the column that starts with what was typed, as in the other presentations (default).

**The preview**

- R10. A file's preview shows a picture no larger than its column, its name, its kind, its size, its size on disk, and the dates it was modified and added, as text that is spoken as words.
- R11. The picture is made through the icon view's loader, off the main actor, and the preview shows the type's usual icon at once.
- R12. A file that is online only shows the usual icon with a cloud mark, says that it is online only, and no picture is requested of it. Nothing in this step downloads a file.
- R13. A preview of several items does not make a picture of each.

**Fits the rest**

- R14. The first rows, the settled list, a refresh from a watch and a reload reach every open column by the rules of steps 3 to 5. A refresh publishes only when visible rows changed, and does not move the selection, scroll any column or take keyboard focus.
- R15. A change to the folder of a column by another process shows in that column within the bound of step 4.
- R16. A selection that disappears (the file was deleted) falls back to its folder, as closing does, and the preview goes with it.
- R17. A column of 100,000 items appears and scrolls without the main actor being away for more than a frame beyond the cost of the rows drawn (default: measured in U1).

**Standing rules and proof**

- R18. No file-system call on the main thread. Anything new that touches the file system starts with the guard and has a test that it fires.
- R19. Every new control, column and preview text takes an `AccessibilityElement` through `apply(_:)` or `applyIdentifier(of:)` and is in `AccessibilityElement.all`; the preview's texts speak their content.
- R20. The code compiles under Swift 6 strict concurrency with warnings as errors and runs on macOS 15.
- R21. Unit tests use stubs and gates and never wait on a clock. A test that asserts on a clock is in a suite named in `TIMING_SUITES`.
- R22. Existing unit and end-to-end tests pass.
- R23. The accessibility audit passes with the columns showing and with a preview showing, on every macOS version CI runs, and the keyboard alone can switch the mode, move through the columns and open a folder.
- R24. The step adds no networking, no telemetry and no dependency.
- R25. `ARCHITECTURE.md`, `README.md` and the status line in `CLAUDE.md` describe the app as it is after this step; the curriculum page, its index row and the lessons note are in the step's commit.
- R26. The step lands through a pull request merged only when CI and a macOS 15 run started by hand are green, and with the user's approval.

### Success Criteria

- Selecting folders in turn opens columns to the right, and arrow keys move through them.
- Selecting a photograph shows its picture and facts, and a file that is online only shows that it is, without being downloaded.
- Switching between list, icons and columns keeps what is selected.

### Scope Boundaries

Out of scope for this step:

- **A text or document preview of a file's contents beyond its thumbnail.** The preview is a picture and facts.
- **Column widths that are remembered**, and per-folder view settings: step 10's.
- **Sort headers over the columns.** Sorting is by View > Keep Folders on Top and by the list's headers; the browser has none.
- **Dragging, renaming in place and file operations.**
- **Playing audio or video in the preview.**
- **A control to choose which facts the preview shows.**

Considered and not built:

- **A hand-made row of table views.** `NSBrowser` already does the column scrolling, the Left and Right keys and the preview column; replacing it is a large piece of work for the same result.
- **Making the preview a quick look panel.** It is a separate window with its own life; the step 7 row asks for a preview column.
- **A new tree in the model for the columns.** The open folders already are the path.

---

## Planning Contract

### Key Technical Decisions

**The browser (`BrowserUI`)**

- KTD1. **The columns are a view of the model's open chain.** Column 0 lists `model.items`. Column *n* lists `model.children(of:)` for the open folder selected in column *n−1*. The browser asks the model, never keeps a copy, and a handle is an object with the identity of the item's key, as in step 5 (`OutlineNode` is reused).
- KTD2. **A selection is a request to the model, and the model's state is what is drawn.** When the person selects, the controller computes the path from the browser's index paths, asks the model to open the folders on it and close the others, sets the model's selection, and does not reload the columns that the model's publish will reload. Reloading from the model never writes back (the `isApplyingModelState` flag).
- KTD3. **The model gets one rule for the path, not new state.** `pruneOpenFolders(keeping:)` closes every open folder that is not an ancestor of a given selection and opens none. Switching to columns calls it with the selection. The controller opens the selected folder itself, because selecting a folder in a column means showing it.
- KTD4. **Items use the delegate's item-based API.** `rootItem(for:)`, `numberOfChildrenOfItem`, `child(_:ofItem:)`, `isLeafItem` and `objectValueForItem`. A folder is not a leaf; a file is. A folder column that is still listing is empty and is reloaded by the publish that brings its rows.

**The preview**

- KTD5. **One preview controller, configured per selection.** `NSBrowser` asks for a view controller for a leaf item; the preview is a small controller with a picture view and four or five labels, built in code, and updated for a new item without being rebuilt.
- KTD6. **The picture is the icon view's pipeline at a larger size.** `ThumbnailLoader.picture(for:pointSize:scale:)` already keys by size, so a 192-point preview and a 64-point cell do not collide. The type's usual icon (`GenericIcons`) is shown at once.
- KTD7. **Online-only is checked where it already is.** The preview does not ask for a picture of an item whose `isOnlineOnly` is true, and the loader refuses it as well.

**The mode (`BrowserUI`, `App`)**

- KTD8. **`ViewMode.columns`.** The same publish kind (`.mode`) and the same command pattern as step 6 (`showAsColumns(_:)`, validated and checked), with Command-3 in the View menu.
- KTD9. **Switching shows one of three views.** The controller hides the other two and reloads the one shown, as step 6 does for two.

**Proof**

- KTD10. **Unit tests drive a real `NSBrowser` in a window** with a stub reader, a stub watcher and the stub provider of step 6. The end-to-end launch asks the running app, and an audit covers the columns and the preview.

### High-Level Technical Design

What a selection does:

```text
the person selects an item in column k
  1. path = the keys of the selected item in each column up to k
  2. close every open folder that is not on the path           (model)
  3. if the item is a folder: open it                          (model; listed and watched)
  4. model.selection = the selected items of column k          (state; no publish)
  5. the model publishes the opened or closed folder
  6. the controller reloads the column that folder fills, and the preview
     for a file; nothing writes back
```

Which view shows what:

| Mode | The model's tree shown as | A folder is |
| --- | --- | --- |
| list | an outline of every open folder | opened in place by its triangle |
| icons | the top level only | entered |
| columns | the open chain as columns | opened by selecting it, entered by Open |

### Assumptions

- **No quality bar is stated** for this row of the roadmap, as for step 2. R1 to R26 are the whole of it.
- **The preview shows a picture and facts only** (Scope Boundaries). A file that is not a picture shows the type's icon, or the system's own thumbnail where one is made.
- **Switching to columns keeps the open folders that lead to the selection** and closes the others (R2), so a nested selection stays visible. With nothing selected the columns show the folder alone.
- **Columns are one width, the browser's default,** until step 10.
- **Selecting several items is allowed only in the last column,** as `NSBrowser` does.
- **The column view has no sort headers.** Sorting still follows the model.
- **Type-to-select works within the column that has focus.**

### Open Questions

None blocks the plan. Each is behavior that planning read about and did not run; the named probe settles it, and the fallback is already chosen.

- **Does an item-based `NSBrowser` call for children lazily, and can it be reloaded one column at a time as the model publishes?** U1's probe decides; the fallback is `loadColumnZero()` with the selection reapplied.
- **How is an `NSBrowser` seen by XCUITest and the audit?** U1's probe decides; the cell or the column may need names through `AccessibilityElement`.
- **What does a column of 100,000 items cost?** U1's probe decides whether a limit is needed.
- **Does the preview controller get recreated or reused by the browser?** U1's probe decides whether KTD5's update path is needed or a new controller is cheap.
- **Does Left and Right move keyboard focus between columns without help, and does typing select in the focused column?** U1 and U4's tests decide.
- **What does VoiceOver say for a column, a row and the preview?** The by-hand check decides; steps 4 to 6's checks are still open.

### Risks

| Risk | Mitigation |
| --- | --- |
| Selection and reload loop through the model and the browser. | The `isApplyingModelState` flag as in steps 5 and 6; a test sends the same selection twice and counts publishes. |
| The browser reloads whole when only a column changed and loses the scroll of the others. | Reload by column (KTD2); U1 measures; a test checks the offset of a column that did not change. |
| A refresh moves the selection or steals focus. | The rules of step 4 apply: a publish names the folder; tests assert offset, selection and first responder. |
| The preview's picture is requested for an online-only file. | Two guards (KTD7), tested as in step 6. |
| The audit cannot see inside the browser's columns, or flags system parts. | U1 probes; the handler's narrow exceptions are the model; a stop condition if it cannot be fixed from the app. |
| The cache's per-tab size (64 MB) grows with a preview size. | A preview picture is one at a time and larger; bound as is; recorded. |

---

## Implementation Units

### U1. The probes

- **Goal:** The questions about `NSBrowser` are answered before the controller is built on them.
- **Requirements:** R3, R5, R17, R19
- **Dependencies:** none
- **Files:** `Packages/BrowserUI/Tests/BrowserUITests/BrowserBehaviorTests.swift` (new, kept), throwaway UI probe
- **Approach:** An in-process probe of an item-based `NSBrowser` in a window with 100,000 items in a column: time to the first column, to a selection, to a column reload; whether `numberOfChildren` is lazy; what the preview callback does on each selection. A throwaway UI test shows how XCUITest and the audit see the browser.
- **Test scenarios:** the kept probes assert the behaviors the controller relies on (lazy children, reload of one column keeps the others' offsets, selection index paths after a reload).
- **Verification:** The numbers are inside the stop conditions or the plan is revised.

### U2. The mode and the open chain in the model

- **Goal:** The model has a third mode and a rule for which open folders belong to a selection's path.
- **Requirements:** R1 to R3, R16
- **Dependencies:** U1
- **Files:** `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`, `Packages/BrowserUI/Tests/BrowserUITests/BrowserModelModeTests.swift`
- **Test scenarios:**
  - `setViewMode(.columns)` keeps the open folders that lead to the selected item, closes the others, keeps the selection, and publishes once.
  - With several selected items in different folders, or none, it closes every open folder, and the selection falls back as a close does.
  - Switching from columns to list leaves the open folders open; to icons closes them.
  - A selected item that is deleted by a refresh falls back to its folder.
  - Every existing mode test passes.

### U3. The preview

- **Goal:** A controller that shows one file's picture and facts, or a count for several.
- **Requirements:** R6, R10 to R13, R19
- **Dependencies:** U1
- **Files:** `Packages/BrowserUI/Sources/BrowserUI/PreviewViewController.swift` (new), `Accessibility.swift`, `Packages/BrowserUI/Tests/BrowserUITests/PreviewViewControllerTests.swift` (new)
- **Test scenarios:**
  - A file shows its name, kind, size, size on disk and both dates as words; a missing value is spoken in words, not as dashes.
  - The type's usual icon is shown at once and the picture replaces it when it arrives; a changed item shows no picture of the previous one.
  - An online-only file shows the cloud mark and says so, and the provider is never asked.
  - Several items show a count and a total, and make no pictures.

### U4. The columns

- **Goal:** An `NSBrowser` that follows the model's open chain and writes the person's selection back to it.
- **Requirements:** R4 to R9, R14, R15, R17
- **Dependencies:** U2, U3
- **Files:** `Packages/BrowserUI/Sources/BrowserUI/ColumnBrowserController.swift` (new), `BrowserViewController.swift`, `Packages/BrowserUI/Tests/BrowserUITests/ColumnViewTests.swift` (new)
- **Test scenarios:**
  - The first column lists the folder; hidden items are absent; a folder is not a leaf and a file is.
  - Selecting a folder opens it in the model and fills the next column; selecting a sibling closes the first folder's column and opens the second.
  - Selecting a file shows its preview; selecting two shows a count.
  - A refresh in the folder of a column changes that column only; offsets, selection and focus are kept.
  - A folder that cannot be listed shows why in its column.
  - Selecting the same item again publishes nothing and does not loop.
  - Typing selects; Open on a folder enters it as a move and the columns start again.
  - Every existing view test passes.

### U5. The command and the running app

- **Goal:** View > as Columns, and the end-to-end proof.
- **Requirements:** R1, R7, R8, R23
- **Dependencies:** U4
- **Files:** `App/MainMenu.swift`, `Packages/BrowserUI/Sources/BrowserUI/BrowserViewController.swift`, `UITests/ColumnViewTests.swift` (new), `UITests/AccessibilityTests.swift`
- **Test scenarios:**
  - The command is enabled and checked for the mode; it acts on the showing tab only.
  - One or more launches: the folder is shown as columns; a folder is selected and its contents appear to the right; a file is selected and its preview appears; keyboard arrows move between columns; a folder is entered with Open.
  - The audit passes with the columns and with a preview showing.
  - By hand: a folder of photographs; a file that is online only; VoiceOver.

### U6. Documents

- **Goal:** The documents describe the app after U1 to U5.
- **Requirements:** R25
- **Dependencies:** U1 to U5
- **Files:** `ARCHITECTURE.md`, `README.md`, `CLAUDE.md`, `docs/curriculum/phase-1-step-07-column-view.md`, `docs/curriculum/README.md`, `docs/solutions/<date>-column-view-notes.md`

---

## Verification Contract

| Gate | Where | Proves |
| --- | --- | --- |
| U1's probes | Local, reference Mac | `NSBrowser` behaves as the controller assumes and costs what it should |
| `make lint`, `make test`, `make build` | Local, then CI | Unit tests, source checks, the timing suites alone |
| `make uitest` | Local | The new launches, the audits and every existing test |
| `make perf` | Local | First rows still met |
| Pull-request CI on `macos-26` | GitHub | Everything automated, on a second macOS |
| macOS 15 workflow, started by hand | GitHub, before the merge | AppKit behavior on the minimum macOS |

---

## Definition of Done

- U1 to U6 are complete, and every scenario exists as a test or has been done by hand and written down, or named as skipped.
- `make lint`, `make test`, `make build`, `make uitest` and `make perf` pass.
- The Open Questions have answers in the lessons note.
- No abandoned attempt remains in the diff, and no probe file is in the repository other than probes kept as tests.
- `CLAUDE.md` says step 7 is done and step 8 is next.
- A pull request is open, its CI is green, the macOS 15 run on the same commit is green, and it is merged only with the user's approval.

---

## Sources

- `plans/phase-1a-browse.md`: the step 7 row.
- `plans/phase-1a-step-06-icon-view.md` and `docs/solutions/2026-10-13-icon-view-notes.md`: the third presentation of the same model, the loader and its cache, online-only guards, and one spoken element per cell.
- `plans/phase-1a-step-05-list-view.md` and `docs/solutions/2026-10-12-list-view-notes.md`: the tree of open folders, selection by key, a view asks for what it draws, tell the view at the move, the audit's 1x contrast estimate.
- Current source read for this plan: `BrowserModel` (open folders, selection, `ViewMode`, publish kinds), `BrowserViewController` (the outline and the icon view, `modelDidChange`), `ThumbnailLoader`, `GenericIcons`, `Accessibility.swift`.
