---
title: Sidebar: a place is a URL, and an end-to-end test finds what a unit test cannot
date: 2026-10-13
category: solutions
module: FileSystemCore, BrowserUI
problem_type: best_practice
component: SidebarViewController, WindowContentViewController, CompositeReader, MetadataQueryReader
severity: medium
applies_when:
  - A browser has to show a place that is not a folder
  - A new view takes width, focus or a first-responder slot from an existing one
  - A test would otherwise list whatever the person used yesterday
tags: [sidebar, nsoutlineview, spotlight, nsmetadataquery, accessibility, hermetic-tests]
---

# Sidebar: a place is a URL, and an end-to-end test finds what a unit test cannot

## Context

Step 8 put a sidebar to the left of the pane: Favorites (Recents first, then bookmarks the person manages), Locations (volumes, with eject), Cloud (iCloud Drive and `~/Library/CloudStorage`) and Tags. The plan is `plans/phase-1a-step-08-sidebar.md`.

## Guidance

- **A place that is not a folder is still a URL.** A tag or the recents has a scheme of its own (`cairn-tag:`, `cairn-recents:`), so history, tabs, the title and Back needed no new idea. One composite reader sends a file URL to the folder reader and a virtual URL to a query reader that yields the same two events. The browser, the sort and the thumbnails did not change; the model got three rules (no enclosing folder, no folders open in place, nothing watched).
- **Give the history key the scheme.** `placeKey` compared paths only, so the tag "Recents" and the recents were one place, and `/Red` and the tag "Red" were too. The scheme is part of the key for anything that is not a file URL.
- **A favorite is a bookmark, and the same folder has two spellings.** Adding a folder twice stored it twice, because `/var/…` and the resolved `/private/var/…` are not equal under the model's text-only comparison (deliberately, so the main thread never asks the disk). The check resolves symbolic links off the main actor. Do the comparison where the disk may be asked.
- **Probe the system source before building.** Mounted volumes: 1.8 ms, 10 with hidden ones and 1 without. A wildcard tag query written `== '*'` returns nothing; `LIKE '*'` with the tag attribute as a value list returns every tag in use with its count in 26 ms. A recents query sorted by last-used date returned 50 in 74 ms. A predicate built with the `$time.today(-7)` variable took the test process down, so Recents computes its own date.
- **`NSMetadataQuery` is not `Sendable`.** One small runner owns the query, hands its result to a continuation exactly once (the finished notification or the timeout, whichever first) and removes its observer. Strict concurrency is a warning-as-error here, so the capture warnings had to go.
- **The model builds the sidebar; the view draws it.** `SidebarBuilder.sections` is a function of what the sources answered and is tested without a window or a disk. The eject button acts on its own row's volume, and a test presses one of two and asserts which was asked.

## What the end-to-end tests found that the unit tests did not

- **The window was too narrow.** The sidebar takes width from a window the list's columns had been fitted to, so Date Added was drawn outside the window (1358 against 1305). The window opens at 1100 now, which leaves the pane about 900.
- **Header text failed contrast.** A source list's group header was drawn at `878787` on `EDEDED`, about 3:1. Assigning the label as the cell's `textField` hands its colour to the system; leaving it unassigned and setting the label colour ourselves passes. The measured-contrast re-check in the audit handler cannot rescue a real 3:1.
- **Keyboard focus started in the sidebar.** A window gives its first key view the focus when nothing has it, and the sidebar is first. The keyboard-only test (down, down, Command-O) failed. The window content now puts focus in the list when it appears.
- **A test that lists the person's Recents is not a test.** The audit with Recents showing failed on a row for an app in this person's recents, clipped by the window's bottom edge. Two launch arguments, in the manner of `-OpenFolder`, keep tests on their own data: `-FavoritesSuite` (favorites in a suite of the test's own) and `-SearchScope` (Spotlight restricted to the fixture folder).
- **A typed setter has a floor.** `URLResourceValues.tagNames` can be set only on macOS 26; `NSURL.setResourceValue(_:forKey:)` works on 15.

## What was measured

- **First rows of the 10,000-item folder:** 0.025 s (target 0.2 s), unchanged by the split view and the default reader.
- **End to end:** `make uitest` 39 tests, 0 failures, including an audit with the sidebar showing, one with Recents chosen, a tag found through Spotlight and added/removed favorites kept across a relaunch.
- **Unit:** FileSystemCore 107, BrowserUI 378 and the timing suite alone, 4.

## The plan's Open Questions

1. *What do the tag and recents queries return?* Above. Tags are the tags in use; Finder's own list is a private preference and is not read, so a tag no file carries is not listed.
2. *Can a query's live updates feed the refresh path?* **Not built.** KTD11's fallback was taken: a virtual location is a one-shot query, read again when the tab goes there. A tag you change elsewhere does not appear until you go back.
3. *What do volumes look like?* Hidden volumes are skipped; ejectable or removable gets the button.
4. *Does a split view keep the toolbar, title and focus?* Title and toolbar yes. Focus no, until the window content restored it (above).
5. *How does XCUITest see a source list?* An `outline` with the identifier `sidebar`; its rows' names are static texts found by value; the eject button is a button named "Eject <volume>".
6. *What does VoiceOver say?* **Not listened to.**

## What is not done

- The VoiceOver checks of steps 4 to 8.
- An eject of a real disk image by hand, and a listing of a real cloud service's folder by hand. The tests use stubs; the app lists `~/Library/CloudStorage` entries as folders and downloads nothing.
- Live updates of a tag or the recents.
- Collapsible sections and the sidebar's width across a quit: step 10's.
- Tags that no file carries, and tag colours.

## Related

- `docs/solutions/2026-10-13-column-view-notes.md`
- `docs/solutions/2026-10-13-icon-view-notes.md`
- `docs/solutions/2026-10-12-list-view-notes.md`
- `docs/solutions/2026-10-09-accessibility-notes.md`
