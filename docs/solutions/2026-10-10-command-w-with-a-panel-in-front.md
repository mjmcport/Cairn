---
title: A menu command sent while a panel is in front reaches the main window first
date: 2026-10-10
category: solutions
module: BrowserUI
problem_type: logic_error
component: PaneViewController
symptoms:
  - Command-W with the About panel in front closed a tab and left the panel open
  - The app delegate's handler for the command was never called
root_cause: wrong_api
resolution_type: code_fix
severity: medium
tags: [appkit, responder-chain, key-window, main-window, menus, tabs]
---

# A menu command sent while a panel is in front reaches the main window first

## Problem

Step 2 gave Command-W to File > Close Tab, with a nil target so the command travels the responder chain. The plan put the "close whatever else is in front" case in the app delegate, on the reasoning that a panel such as About has no pane in its chain, so the command would fall through to the end. It did not. With the About panel in front, Command-W closed a tab in the browser window behind it and the panel stayed open.

## Symptoms

- The end-to-end test opened About, pressed Command-W, and found the panel still showing.
- `AppDelegate.closeTab` was not called.

## What Didn't Work

- **Handling the command only at the end of the chain** (the app delegate). The About panel becomes the key window, but the browser window stays the main window. For a nil-target action the application tries the key window's responders, then the main window's, and only then itself and its delegate. The pane in the main window answers first.

## Solution

The handler that can be reached from the main window checks which window is in front before it acts:

```swift
@objc public func closeTab(_ sender: Any?) {
  if let keyWindow = NSApplication.shared.keyWindow, keyWindow !== view.window {
    keyWindow.performClose(sender)
    return
  }
  close(showingBrowser)
}
```

The app delegate keeps its own `closeTab`, with validation, for the case where no pane is in the chain at all: the About panel in front after the last browser window has closed.

## Why This Works

"In front" for the user is the key window. A handler in the main window cannot assume it is the key one, so it compares and passes the command on. The delegate's handler covers the only remaining case, a key window with no main window behind it.

## Prevention

- A nil-target command that should act on what is in front has to ask for the key window in every handler a main window can reach, not only in the last one.
- Test both arrangements end to end: a panel in front of a browser window, and a panel in front with no browser window. `UITests/TabsTests.swift` does both in `testClosingTabsAndTheWindow`. A unit test cannot stand in for them, because a test process does not get a key window.
- The same applies to any later command that should mean "this window": dual panes and a second browser window will both add handlers that a main window can reach.

## Related Issues

- `docs/solutions/2026-10-09-navigation-history-notes.md` (toolbar validation and the responder chain)
- `docs/solutions/2026-10-10-check-then-act-across-a-task-boundary.md`
