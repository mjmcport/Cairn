---
title: Navigation history notes
date: 2026-10-09
step: Phase 1A step 1
tags: [appkit, navigation, selection, toolbar]
---

# Navigation history notes

## What we learned

- **Folder URLs differ by a trailing slash.** An item URL from the enumerator ends in `/`; `URL(filePath:)` without a directory hint does not. Comparing URLs directly made "the folder just left" fail to match its own row. Compare places by the text of the path, with the trailing slash removed and `.` and `..` resolved (`BrowserHistory.placeKey`). Do not use `standardizedFileURL` for this: for a path under `/private` it asks the disk whether the path exists, which is a file-system call on the main thread.
- **A listing spells a folder differently from the location that was opened.** `DirectoryReader` follows symbolic links, so a location under `/var` or `/tmp` lists items under `/private/var` or `/private/tmp`. Fixture roots are under `/var`, not `/private/var`, so every fixture test sees this. Comparing full paths as text therefore cannot match a remembered selection to listed items. A selection belongs to one folder, so `BrowserModel.matching` matches by item name.
- **Programmatic selection fires `tableViewSelectionDidChange`.** Without a guard flag, restoring a selection from the model wrote it straight back. Set the flag around `selectRowIndexes`.
- **A standard toolbar item with no target is validated through the responder chain** by `validateUserInterfaceItem` on whoever handles its action, the same method menus use. An item that holds a view is not validated by the system. `ToolbarButtonItem` overrides `validate()` to ask the same method, so one implementation still enables the menu items and the buttons, and `BrowserViewController` validates the toolbar whenever its model changes, because a load finishes without an event.
- **A standard `NSToolbarItem` gives its button a label but no accessibility identifier.** Its `label` is what VoiceOver speaks, and a test could find the button only by that label. In an in-process probe on macOS 27 the button reported an empty identifier. The Back and Forward items therefore hold a real `NSButton` that takes a declared `AccessibilityElement` through `apply(_:)`, and the UI test finds the buttons by identifier. That query compiled but had not run when this was written.
- **A toolbar item passes its target, action and enabled state on to the control it holds, but not its tooltip.** Set the tooltip on the button as well, and give the item a `menuFormRepresentation` for the overflow menu and text-only mode.
- **An `NSToolbar` does not retain its delegate.** The app delegate keeps the `BrowserToolbar` object.
- **Text over a striped table can fail the contrast audit** depending on where the stripes fall, and adding the toolbar moved them. Give overlaid text an opaque background.
- **`swift-format` re-indents code to match its braces.** A block inserted after a type's closing brace is silently re-indented as top-level code; the compiler errors are the first sign.

## What to carry forward

- Tabs (step 2) get one `BrowserModel` each. The toolbar and menus already reach the focused browser through the responder chain.
- Any new navigation path must go through `BrowserModel` so history and selection stay consistent. In `BrowserViewController` a command makes the move as it arrives (`move(to:)`, `moveToEnclosingFolder()`, `moveBack()`, `moveForward()`) and only the listing goes into the task (`run { await $0.load() }`). A command that checked first and moved inside the task let a second command, sent before the task started, pass a check that was no longer true and cancel the first: Back twice with one place to go back to left the browser loading. The async `navigate(to:)`, `goBack()` and `goForward()` are for a caller that awaits them.
- **Ask macOS 15 before trusting an AppKit lookup.** `NSApp.target(forAction:to:from:)` given a toolbar item found the browser on macOS 26 and 27 for a window that was not key, and returned nothing on macOS 15, where the item's view was also not yet in the window. Two unit tests failed only on the macOS 15 runner. The item now falls back to the window whose toolbar holds it (`ToolbarButtonItem.window(of:)`). Run the macOS 15 workflow by hand (`gh workflow run macos-15.yml --ref <branch>`, about 20 to 30 billed minutes) before merging a step that leans on AppKit behaviour.
- **macOS 26 differs too, in the other direction.** In step 2 a unit test passed on macOS 15 and 27 and failed on the macOS 26 runner: a toolbar button asked `window?.contentViewController` for the browser, and on macOS 26 the button's view is not in the browser's window until the toolbar has been laid out. Anything in a toolbar item that needs the browser's window asks for the window whose toolbar holds it (`ToolbarButtonItem.window(of:)`, `window(holding:)`), never for the view's own window.

