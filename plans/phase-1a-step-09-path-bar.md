---
title: Phase 1A Step 9 Path Bar - Plan
type: feat
date: 2026-10-14
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Phase 1A Step 9 Path Bar - Plan

## Goal Capsule

- **Objective:** Each tab shows where it is as a row of folder names under the file list. Clicking a name goes there; a menu on each name lists the folders inside it. Go to Folder (Shift-Command-G) takes a typed path and offers matching folders as it is typed. Copy Path puts the selected items' paths, or the folder's, on the pasteboard in four formats.
- **Means:** Pure path logic with no UI in `FileSystemCore` (KTD1 to KTD4): the crumbs of a location, the four formats, the reading of a typed path and the folders that complete it. A path bar view, a Go to Folder sheet and Edit and Go menu items in `BrowserUI` and `App` (KTD5 to KTD8). Navigation goes through the move the sidebar already uses.
- **Authority:** R1 to R22 come from the step's row in `plans/phase-1a-browse.md`. Where a KTD and an R disagree, the R wins. Requirements marked "default" are unconfirmed bets listed under Assumptions.
- **Execution profile:** New files in `FileSystemCore` and `BrowserUI`, edits to `PaneViewController`, `MainMenu`, `Accessibility.swift`, tests, an end-to-end launch. Nothing was run while planning: what `contentsOfDirectory` costs for a completion on a large folder, and how an `NSMenu` on a button reads in XCUITest, are read about, not measured, so U1 and U5 carry probes.
- **Stop and tell the user when:**
  - a completion or a menu of subfolders lists a folder on the main thread, and moving it off does not fix it;
  - a typed path would be acted on without the person pressing Return, or Copy Path would write anything but the chosen format to the pasteboard;
  - a real-stream or timing test fails some of the time: do not loosen or drop it;
  - UI automation is needed and the authentication prompt has not been approved;
  - a unit test fails on macOS 15 or macOS 26 only;
  - a fix would need a change under `.github/workflows/`.
- **Who finishes:** The implementer lands U1 to U6 on branch `phase-1a/path-bar`, runs the lessons and curriculum steps, commits, opens the pull request, starts the macOS 15 run by hand, and asks the user before merging.

---

## Product Contract

### Summary

Phase 1A step 9 adds the three ways to say where a place is. The path bar shows the showing tab's location as clickable folder names from the volume down. Go to Folder takes a path by typing. Copy Path takes a path out. All three use the move of step 8: the tab goes there as one history step, and Back returns.

### Problem Frame

- **A location is only shown as a title.** The window and tab say the last folder's name. Nothing shows the folders above it except Enclosing Folder, one step at a time.
- **There is no way to type a place.** The sidebar offers favorites; a folder elsewhere takes many clicks.
- **A path cannot leave the app.** There is no Edit menu and no command that puts a path on the pasteboard.
- **A virtual location has no folders.** A tag or Recents (step 8) is not a path; the bar must say so, not invent one.

### Requirements

**The path bar**

- R1. The pane shows a bar under the file list with one name for each folder from the volume's root to the showing tab's folder. The last name is the showing folder and is marked as current.
- R2. Clicking a name moves the tab to that folder (history, title, toolbar and sidebar follow, Back returns). Clicking the current one does nothing.
- R3. Each name has a menu that lists the folders inside that name's folder, as names; choosing one moves the tab there (default: children, not siblings).
- R4. Listing for a menu is off the main thread and bounded. A folder that cannot be listed shows one disabled line saying so.
- R5. The bar follows the showing tab: switching tabs, Back, Forward, the sidebar and a folder opened in the list all update it.
- R6. In a virtual location the bar shows that place's name alone, with no folders.
- R7. Long paths shrink from the left: names that do not fit collapse into one "…" menu that lists them in order.
- R8. The bar can be hidden and shown (View > Hide Path Bar, default shown).

**Go to Folder**

- R9. Go > Go to Folder… (Shift-Command-G) opens a sheet with a text field holding the showing folder's path.
- R10. A leading `~` is the home folder; a relative path is relative to the showing folder; `..` and `.` and a trailing `/` are understood.
- R11. As the person types, the folders that begin with the last component of the text are offered, off the main thread; the list is at most 20 entries, folders first by name, hidden folders only when the typed component begins with `.`.
- R12. Down and Up choose an offered folder, Tab completes the text to it, Return goes to the typed place, Escape closes the sheet. Nothing moves until Return.
- R13. A place that does not exist, or is a file, keeps the sheet open and says why in words. A file goes to its enclosing folder with the file selected (default).
- R14. An accessibility label and a status text announce how many folders are offered.

**Copy Path**

- R15. Edit > Copy Path has four formats: Path (`/Users/me/My Folder`), Escaped Path (`/Users/me/My\ Folder`, safe to paste in a shell), File URL (`file:///Users/me/My%20Folder`) and Home-Relative Path (`~/My Folder`; the plain path when outside home).
- R16. The command copies the selected items; with none selected it copies the showing folder; in a virtual location with none selected it is disabled. Several items give one path a line, in list order.
- R17. Option-Command-C copies the plain path (Finder's key for it).
- R18. The pasteboard gets plain text only for the three text formats and a URL type as well for File URL.
- R19. A context item "Copy Path" on a name and on a list row: not built (see the lessons note); Edit > Copy Path and Option-Command-C cover it.

**The rest**

- R20. Every control has an accessibility identifier and spoken label through `AccessibilityElement`; the accessibility audit passes with the bar showing and with the sheet open.
- R21. Everything earlier is unchanged: tabs, the sidebar, keyboard focus after a move, first rows within 200 ms.
- R22. The bar adds no file-system call on the main thread; every listing entry point starts with `MainThreadGuard.assertOffMainThread()`.

### Success Criteria

- Clicking a name two levels up shows that folder, and Back returns.
- Typing `~/Doc` offers Documents; Return on `~/Documents` goes there.
- Copy Path of a file named `a b.txt` pastes `/…/a\ b.txt` in the escaped format.

### Scope Boundaries

Out of scope:

- **Editing the path in place in the bar** (a bar that turns into a field); Go to Folder is the typing route.
- **Dragging a name to move or copy files,** and a drop on a name.
- **Recent folders list** in the sheet; history is the sidebar's Recents and Back.
- **Network paths and `smb://` addresses** (Connect to Server).
- **Reveal and Show Original** for aliases and symlinks; the path shown is the one the tab has.
- **A saved width, visibility across a quit:** step 10.

Considered and not built:

- **A toolbar path pop-up like Finder's title menu.** The bar is always visible and keyboard-reachable; a second route is a second thing to keep in step.
- **Completion in a native `NSComboBox`.** Its data source is synchronous and would list on the main thread.

---

## Planning Contract

### Key Technical Decisions

**Path logic (`FileSystemCore`, no UI)**

- KTD1. **`PathCrumbs.crumbs(for:)` is pure.** It turns a location URL into `[Crumb]` (title, URL, isCurrent) by walking `deletingLastPathComponent` with no file-system call; the first crumb is `/` named by the volume's name where the caller supplies one, else "Macintosh HD" (default). A virtual URL gives one crumb.
- KTD2. **`PathFormat` is an enum of four cases with `string(for:home:)`.** Pure string work on `URL.path`, with the shell-escaping done by a single function whose tests cover spaces, quotes, `$`, backticks, parentheses, newlines and non-ASCII.
- KTD3. **`TypedPath.resolve(_:relativeTo:home:)` is pure** and returns the URL and whether the text ended in `/`. Existence is checked separately.
- KTD4. **`FolderCompletion` lists and checks existence, guarded, off the main thread.** `FolderCompleting` is a protocol with a stub; `DirectoryFolderCompleter` reads `contentsOfDirectory` with `.isDirectoryKey` and `.isHiddenKey`, caps at 20 after sorting, and `exists(_:)` returns `.folder`, `.file` or `.missing`. Each entry point starts with the guard.

**Views (`BrowserUI`, `App`)**

- KTD5. **The bar is a `PathBarView` of buttons in a stack.** Each crumb is a button: a click navigates, a separate small chevron button starts a task that lists the folders and then pops up the menu, so listing is never on the main thread. No "Loading…" line: the menu appears when the answer arrives.
- KTD6. **The pane owns the bar,** below the browser container, so every view mode shares one; it asks the showing browser for its location and tells it to `show(_:)`, as the sidebar does (step 8 KTD7).
- KTD7. **Go to Folder is a sheet of the window,** `GoToFolderViewController`, with a text field, a suggestion table and a status line. A new request cancels the one before it; a result for stale text is dropped.
- KTD8. **Copy Path is a selector on `BrowserViewController`,** reached through the responder chain like the Go commands, so it works from the list, icons and columns. One selector with `tag` carrying the format, so the menu has four items and one action.

### High-Level Technical Design

```
Location (URL) --PathCrumbs--> [Crumb] --PathBarView--> buttons
  click crumb -----------------------------> Pane.show(url) -> browser.move
  chevron -> task: FolderCompleter.children(of:) -> NSMenu items -> Pane.show

Go > Go to Folder -> sheet --typed text--> TypedPath.resolve --FolderCompleter--> suggestions
  Return -> exists? .folder -> show ; .file -> show(enclosing)+select ; .missing -> message

Edit > Copy Path > 4 formats -> selection (or folder) -> PathFormat -> NSPasteboard
```

### Assumptions

- **Quality bar for step 9 is blank in the roadmap table**; R1 to R22 are taken to cover it.
- **A menu on a name lists the folders inside it,** not its siblings. Finder's path bar offers neither; Windows' breadcrumb offers children.
- **The root crumb is the volume name,** read once off the main thread when the bar is created, "Macintosh HD" when unknown. Paths under `/Volumes/X` start at `/` too: the bar shows the real path, not a volume-relative one.
- **The bar sits at the bottom of the pane,** where Finder puts its own.
- **Escaped Path escapes with backslashes** (`\ `), not single quotes, matching what Terminal's own drop does.
- **Option-Command-C is free** (no Copy of files exists yet; Phase 1B's file Copy is Command-C).
- **Hidden folders are offered only when asked for by a leading `.`**
- **A file typed in Go to Folder reveals the file** in its folder.

### Open Questions

None blocks the plan.

- **How slow is a completion in a folder of 10,000 entries?** U1 measures; the cap of 20 is applied after a read of names only, and the stop condition above holds.
- **How is a pull-down menu on a button seen by XCUITest and the audit?** U5 decides; the fallback is a context menu on the crumb with the same items.
- **Does a sheet's text field keep Tab for completion without losing keyboard focus order?** U3's test decides.

### Risks

| Risk | Mitigation |
| --- | --- |
| A completion lists a huge folder on the main thread. | Guarded off-main function, a test that the guard fires, a timing check in U1. |
| A fast typist gets suggestions for older text. | Each request carries a generation; stale results are dropped; tested with a gate. |
| The escaped format is wrong for an odd name and a shell runs something. | One tested function; characters outside a safe set are all backslash-escaped. |
| The bar competes with the list for vertical space and keyboard focus. | Fixed height, not in the key-view loop's first stop; U2's tests restate step 1 and 2's focus behavior. |
| A long path overflows the pane. | Left collapse into one "…" menu (R7) with a test at three widths. |
| The 1x contrast false positive appears on bar text. | The audit handler re-measures from pixels (existing). |

---

## Implementation Units

### U1. Path logic

- **Goal:** Crumbs, formats, typed-path resolution and folder completion exist and are tested without a window.
- **Requirements:** R1, R6, R10, R11, R15, R22
- **Dependencies:** none
- **Files:** `Packages/FileSystemCore/Sources/FileSystemCore/PathCrumbs.swift`, `PathFormat.swift`, `TypedPath.swift`, `FolderCompletion.swift`, tests of each
- **Test scenarios:**
  - Crumbs of `/Users/me/Docs` are `/`, `Users`, `me`, `Docs`, the last current; of `/` one crumb; of a virtual URL one crumb with the tag's name.
  - Each format of a path with spaces, quotes, `$`, a newline and `é`; a path under home gives `~/…` and one outside gives the plain path; File URL percent-encodes.
  - `~`, `~/x`, `../y`, `./z`, `a/b/` and an empty string resolve as specified.
  - Completion of `Do` in a fixture offers only folders that begin with it, folders first, capped at 20, hidden ones only for `.`; a file is not offered; `exists` gives folder, file and missing.
  - The guard fires for completion and existence on the main thread.
  - Timing: completing in a 10,000-entry fixture returns within a bound that is recorded (U1 probe).

### U2. The path bar view and the pane

- **Goal:** The bar shows crumbs and navigates.
- **Requirements:** R1 to R8, R21
- **Dependencies:** U1
- **Files:** `PathBarView.swift` (new), `PaneViewController.swift`, `Accessibility.swift`, tests
- **Approach:** The pane creates the bar, updates it from `showTabs()` and from the browser's location callback, and shows or hides it from a view-menu command. Menus fill from a task through `FolderCompleting`.
- **Test scenarios:**
  - The bar's names follow a move, Back, a tab switch and a sidebar choice.
  - Clicking a middle crumb moves the tab, one history step; the current crumb does nothing.
  - The chevron's menu lists the children, off the main thread (a gated stub proves it), and "Loading…" shows until then; a failing list gives a disabled line.
  - A virtual location shows one name and no menu.
  - Narrow widths collapse the left names into "…".
  - Every control has its identifier and label.

### U3. Go to Folder

- **Goal:** The sheet takes a typed path with completion.
- **Requirements:** R9 to R14
- **Dependencies:** U1, U2
- **Files:** `GoToFolderViewController.swift` (new), `PaneViewController.swift`, `MainMenu.swift`, tests
- **Test scenarios:**
  - The field starts with the showing folder's path; typing offers matches; a stale result is dropped.
  - Down, Up, Tab and Return behave as in R12; Escape closes with no move.
  - A missing path keeps the sheet and shows the message; a file goes to its enclosing folder with the file selected.
  - The suggestions' count is in the status text.

### U4. Copy Path

- **Goal:** Four formats from the selection or the folder.
- **Requirements:** R15 to R19
- **Dependencies:** U1
- **Files:** `BrowserViewController.swift`, `MainMenu.swift` (Edit menu), tests
- **Test scenarios:**
  - Each format of one selected item, of several (newline-separated, list order), and of the folder with none selected, read back from a stub pasteboard.
  - Disabled in a virtual location with no selection; enabled with one.
  - The three text formats write one string; File URL also writes a URL.
  - Option-Command-C is the plain path.

### U5. The running app

- **Goal:** End to end in the real app, audited.
- **Requirements:** R2, R9, R12, R15, R20, R21
- **Dependencies:** U2 to U4
- **Files:** `UITests/PathBarTests.swift`, `UITests/AccessibilityTests.swift`
- **Test scenarios:**
  - Click a crumb; the list shows that folder.
  - Open the sheet, type a path, Return; the tab is there; Back returns.
  - Copy Path and read the pasteboard.
  - The audit passes with the bar showing, and with the sheet open.
- **By hand:** VoiceOver on the bar, its menus and the sheet (the checks of steps 4 to 8 are still open).

### U6. Documents

- **Goal:** The step is written down.
- **Requirements:** the loop in `CLAUDE.md`
- **Dependencies:** U1 to U5
- **Files:** `docs/solutions/2026-10-14-path-bar-notes.md`, `docs/curriculum/phase-1-step-09-path-bar.md`, `docs/curriculum/README.md`, `ARCHITECTURE.md`, `README.md`, `CLAUDE.md`
- **Approach:** Lessons note with what the units found; a curriculum page that opens from an ordinary-life image (a street address read from the country down); status and layout rows updated.

---

## Verification Contract

| Gate | Where | Proves |
| --- | --- | --- |
| U1's timing probe | Local, reference Mac | Completion in a large folder is bounded |
| `make lint`, `make test`, `make build` | Local, then CI | Unit tests, source checks |
| `make uitest` | Local | The new launches, the audits and every existing test |
| `make perf` | Local | First rows still met |
| Pull-request CI on `macos-26` | GitHub | Everything automated, on a second macOS |
| macOS 15 workflow, started by hand | GitHub, before the merge | AppKit behavior on the minimum macOS |

---

## Definition of Done

- U1 to U6 are complete, and every scenario exists as a test or has been done by hand and written down, or named as skipped.
- `make lint`, `make test`, `make build`, `make uitest` and `make perf` pass.
- The Open Questions have answers in the lessons note.
- `CLAUDE.md` says step 9 is done and step 10 is next.
- A pull request is open, its CI is green, the macOS 15 run on the same commit is green, and it is merged only with the user's approval.

---

## Sources

- `plans/phase-1a-browse.md`: the step 9 row.
- `plans/phase-1a-step-08-sidebar.md` and `docs/solutions/2026-10-13-sidebar-notes.md`: navigation by `show(_:)`, virtual locations, off-main discovery, the audit's contrast re-check.
- `docs/solutions/2026-10-10-check-then-act-across-a-task-boundary.md`: a navigation command moves synchronously, then loads in a task.
- `docs/solutions/2026-10-09-main-thread-guard-notes.md`: guard first, a test on the main actor.
- Current source read for this plan: `PaneViewController` (layout, `showTabs`, responder chain), `BrowserViewController` (`show`, selection), `BrowserModel` (`move`, virtual locations), `MainMenu`, `Accessibility.swift`.
