---
title: Walking skeleton notes
date: 2026-10-09
step: Phase 0 step 5
tags: [appkit, concurrency, xcuitest, enumeration]
---

# Walking skeleton notes

## What we learned

- **`FileManager`'s enumerator cannot be iterated in an `async` function.** Swift 6 marks `NSEnumerator` iteration unavailable there. Do the loop in a synchronous helper and call `Task.checkCancellation()` inside it; the check works in synchronous code that runs within a task.
- **A window does not follow its content view controller's `title` once it is on screen.** The window opened untitled until the controller set `view.window?.title` itself, in `viewDidAppear` and on every change.
- **Awaiting the model directly in a view-controller test races the controller's own load.** `viewDidLoad` starts a load; a second `load()` from the test bumps the generation and one of the two returns early. Tests await `controller.loadTask?.value` instead.
- **A nonisolated XCTest `tearDown` cannot touch `XCUIApplication`** under Swift 6. Terminate the app in `addTeardownBlock { @MainActor in app.terminate() }` from the main-actor launch helper.
- **Launch arguments of the form `-Key value` land in `UserDefaults`.** `-OpenFolder <path>` needs no argument parsing, and `-ApplePersistenceIgnoreState YES` stops window restoration from interfering with UI tests.
- **XCUITest reaches an `NSTableView` as `app.tables[identifier]`**, with `tableRows.count` for rows and `staticTexts[name]` for cells. Row counts need a wait, because loading is asynchronous.
- **UI tests can build fixtures in the runner process.** The runner and the app share the user's temporary directory, and neither is sandboxed.

## What to carry forward

- Keep logic in `BrowserModel` and static helpers, where Swift Testing can reach it without a window.
- Every new asynchronous model action goes through `BrowserViewController.run`, which cancels the previous one.
