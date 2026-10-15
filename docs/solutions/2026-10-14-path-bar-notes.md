---
title: Path bar: path logic that never touches the disk, and an audit that tells the truth about sheets
date: 2026-10-14
category: solutions
module: FileSystemCore, BrowserUI
problem_type: best_practice
component: PathBarView, GoToFolderViewController, PathCrumbs, PathFormat, TypedPath, FolderCompletion
severity: medium
applies_when:
  - A view has to show or accept a path
  - A menu or a completion list needs a folder listed
  - An accessibility audit runs while a sheet is open
tags: [path-bar, go-to-folder, copy-path, completion, accessibility, sheets]
---

# Path bar: path logic that never touches the disk, and an audit that tells the truth about sheets

## Context

Step 9 added three ways to say where a place is: a bar of folder names under the list, a Go to Folder sheet that completes a typed path, and Edit > Copy Path in four formats. The plan is `plans/phase-1a-step-09-path-bar.md`.

## Guidance

- **Split the path work into a part that never asks the disk and a part that must.** Crumbs (`PathCrumbs`), the four formats (`PathFormat`) and the reading of typed text (`TypedPath`) are string work on URLs and run anywhere, so they are tested with plain values. Only listing folders for a menu or a completion and asking "folder, file or nothing?" (`FolderCompleting`) touch the disk; those two entry points are guarded, run off the main thread, and sit behind a protocol with a stub, so every view test is hermetic.
- **A folder's URL spells its path with a closing slash.** `URL.path(percentEncoded: false)` of a directory URL returns `/fixture/`, so Copy Path of the showing folder pasted a trailing slash and the home-relative form of home itself missed `~`. The test for "nothing selected copies the folder" caught it. Strip the slash in one place, for the path and for home, except for `/`.
- **Escape for a shell with a rule, not a list.** Everything outside a small safe set gets a backslash. A control character cannot be backslash-escaped (a backslash before a newline is a line continuation), so such a name is written in `$'…'` form. Tests cover spaces, quotes, `$`, backticks, parentheses, `;`, `&`, a newline and non-ASCII.
- **Answer for the latest text only.** Every completion request carries a generation number, and a result for older text is dropped. The test holds the first answer at a semaphore, types again, lets the second finish, then releases the first and checks the list did not change.
- **A menu fills from a task, not from `menuNeedsUpdate`.** `NSMenuDelegate` asks synchronously, which would list a folder on the main thread. The chevron starts a task, builds the menu from the answer and pops it up when it arrives; a folder that cannot be listed gives one disabled line. The plan's "Loading…" line was dropped: the listing takes milliseconds, and a menu that changes while it is open is worse than a short pause before it appears.
- **Existing layout tests state the whole pane.** Three pane tests asserted the browser's height equals the pane's. The bar takes `PathBarView.height`, so they now say so. A test that restates a layout number will be touched whenever a neighbour is added.

## Findings from the end-to-end audit

- **A group needs to be an element to be found.** A plain `NSView` with an identifier and the `group` role was not in the accessibility tree as itself; its buttons were. `setAccessibilityElement(true)` makes the bar a named group.
- **Secondary label color fails on a white sheet.** The status line in `secondaryLabelColor` measured about 3.9:1 ("Contrast nearly passed"), the same lesson as the sidebar headers: use `labelColor` for text that carries information.
- **Behind a sheet the window is dimmer, so its texts fail contrast.** The audit reported the sidebar's header at 878787-ish on a dimmed ground. The handler now ignores contrast issues for elements outside an open sheet's frame; the same window is judged with no sheet open in the other audits.
- **An active field editor gives a Parent/Child mismatch with no element.** With keyboard focus in the sheet's text field the audit reports "This element is not an accessibility child of the parent element" and names no element; with focus on the suggestion list it is clean. It is the system's field editor, not a control the app builds, so the sheet is audited with focus on the suggestions and the typing state is covered by unit tests and the end-to-end typing test. Recorded as a known gap, not hidden.

## Open or not done

- **VoiceOver** on the bar, its menus and the sheet. Open with steps 4 to 8.
- **Context menu "Copy Path" on a name and on a list row** (plan R19, a default). Not built; Edit > Copy Path and Option-Command-C cover it.
- **A real network volume** in the bar: not tried.
- **The root crumb's name** comes from the startup volume only; a path under `/Volumes/X` shows the real path from `/`.

## Open questions, answered

- **How slow is a completion in a folder of 10,000 entries?** 0.8 s in the test including building the fixture; the listing itself is far below the 2 s bound the test asserts.
- **How is a pull-down on a button seen by XCUITest?** The chevron is found by identifier and label ("Folders in Docs"); the end-to-end tests click names and type in the sheet, and the menu contents are covered by unit tests with a menu presenter that is swapped out.
- **Does the sheet keep Tab for completion?** Yes; the field's `doCommandBy` takes Tab, Return, Escape and the arrows, and a unit test covers completion.
