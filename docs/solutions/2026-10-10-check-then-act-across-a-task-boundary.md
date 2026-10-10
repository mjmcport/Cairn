---
title: A command that checks state now and changes it in a task can strand the browser
date: 2026-10-10
category: solutions
module: BrowserUI
problem_type: logic_error
component: BrowserViewController
symptoms:
  - The browser stays in its loading state with an empty list after two quick Back commands
  - A second command cancels the first and then does nothing
root_cause: async_timing
resolution_type: code_fix
severity: medium
tags: [swift-concurrency, main-actor, navigation, cancellation, check-then-act]
---

# A command that checks state now and changes it in a task can strand the browser

## Problem

`BrowserViewController` handled Back like this: check `model.canGoBack` when the command arrives, then start a task that calls `model.goBack()`. The check and the history move were on the same actor but in different turns of it. A second Back that arrived before the first task had started passed the same check, cancelled the first task, and its own `goBack()` then found no history left. The first task still moved the history and began a load that was already cancelled, and a cancelled load publishes nothing. The window was left loading, with no rows.

Forward, Enclosing Folder one level below the root, and Open followed by Back had the same shape.

## Symptoms

- With one entry of history, sending `goBack(_:)` twice without awaiting between them ends with `state == .loading` and `items == []`.
- No error is logged: every step is individually correct.

## What Didn't Work

- **Guarding the command with a read-only check** (`canGoBack`, `enclosingFolder != nil`). That fixed an earlier bug, where a command with nothing to do cancelled a load in flight, but it only moved the stale read from the model to the controller.
- **Relying on the main actor.** Both halves run on the main actor, so there is no data race, and the compiler has nothing to say. The problem is ordering between two turns of one actor.

## Solution

Make the check and the state change one synchronous step, and leave only the slow work in the task.

`BrowserModel` has a synchronous half for every move, which changes the history and what is waiting to be selected and reports whether anything changed:

```swift
@objc public func goBack(_ sender: Any?) {
  guard model.moveBack() else { return }
  run { await $0.load() }
}
```

`moveBack()`, `moveForward()`, `moveToEnclosingFolder()` and `move(to:)` are the synchronous halves. The async `goBack()`, `goForward()`, `navigateToEnclosingFolder()` and `navigate(to:)` remain for callers that await, and are now a move followed by `load()`.

## Why This Works

The task only ever lists `history.current`. Whatever commands arrive before it starts have already moved the history, so the last task to run loads the place the user ended on, and a command with nothing to do returns before it can cancel anything.

## Prevention

- A new navigation command in the controller (tabs, the sidebar and the path bar are next) calls a synchronous `move…` and then `run { await $0.load() }`. It does not put the move inside the task.
- Test a command by sending it twice with no `await` between. `BrowserViewControllerTests` has this for Back, Forward, Enclosing Folder, and Open then Back; each was seen to fail against the old ordering.
- The general rule: when a handler reads state to decide whether to start a task, the state change that makes the decision true belongs in the handler, not in the task.

## Related Issues

- `docs/solutions/2026-10-09-navigation-history-notes.md`
- `docs/solutions/2026-10-09-walking-skeleton-notes.md` (model actions go through `run`)
