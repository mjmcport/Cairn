---
title: Icon view: measure each addition to a listing, and keep a cell to one spoken element
date: 2026-10-13
category: solutions
module: BrowserUI, FileMetadata, FileSystemCore
problem_type: best_practice
component: ThumbnailLoader, IconItem, FileItem
severity: medium
applies_when:
  - Anything new is read for every item of a listing
  - Pictures of files are made for a view that scrolls
  - A view has a decorative image inside an element that already speaks
tags: [nscollectionview, quicklook, thumbnails, performance, accessibility, cloud]
---

# Icon view: measure each addition to a listing, and keep a cell to one spoken element

## Context

Step 6 added the icon presentation: View > as Icons shows the folder as a grid of pictures and names, from the same model as the list. Pictures are made off the main actor for what is on screen, cached, and never made for a file that is online only. The plan is `plans/phase-1a-step-06-icon-view.md`.

## Guidance

- **Measure each new value read for every item of a listing, and measure the one you think is free.** The iCloud `ubiquitousItemDownloadingStatus` is a single resource key and says outright that a file is a placeholder. Reading it in the listing took 10,000 items from 0.058 s to 0.53 s and 100,000 from 0.55 s to 5.4 s, nine and ten times. It was removed the same hour. "Online only" now comes from two values the listing already reads, a size and no allocated blocks, and the status is a function a caller with few items may pass.
- **Choose a limit from a curve, not from a feeling.** With distinct files for every run (the system caches thumbnails it has made, so a repeat is a cache hit), 100 thumbnails took 1.43 s one at a time, 0.77 s two, 0.45 s four, 0.42 s eight and 0.41 s sixteen. Four in flight is the knee.
- **Give a cell a picture at once and make it better later.** The generic icon is a lookup by the item's content type, with no file access, so every cell is complete the moment it exists. A thumbnail replaces it when it arrives, and a cell that is reused or scrolled away cancels its request.
- **Refuse in two places what must never happen.** A thumbnail request for an online-only file can download it. The cell does not ask, and the loader refuses as well, and a test fails if either guard is removed. Whether a request for a real placeholder would download it was not probed: a test cannot make a placeholder, so the guard has to hold on its own.
- **A collection view with a fixed item size is nearly free.** 100,000 items laid out in 3.7 ms with 140 cells made, and a reload took 1.2 ms. A reload clears the selection, so the controller applies the model's afterwards, as the list does.
- **A cache keyed by what makes a picture valid needs no invalidation.** The key is the item's path, modified date, size and the pixel size asked for. A changed file has another key and its old picture simply cannot be found; bounds in entries and in bytes with least-recently-used eviction keep it from growing. 100,000 pictures passed through a 500-entry cache and it never went over.
- **Hand the audit one element per cell.** The audit reported the picture, an image with no label. Marking the picture as not an element did not stop it (the image view overrides that). Telling the cell it has no accessibility children did: VoiceOver now meets one element that says "alpha.txt, file" or "cloud.png, file, online only". The cost is that tests find a cell by that spoken label, not by a static text inside it.
- **`NSCollectionView` has neither type-to-select nor a double-click action.** A subclass forwards typed characters and `clickCount == 2`, and the typeahead rule is a value type with no clock, so it is tested without a window.
- **Timing and responsiveness were measured with a ticker.** Scrolling 601 real photographs in 1.95 s left the longest gap of the main actor at 34 ms, once, and every one of the 160 visible cells had its real picture.

## What was measured

Reference Mac, macOS 27.

- **First rows of the 10,000-item folder** with the value read: 0.028 s (baseline 0.026 s, target 0.2 s). `docs/performance/baseline.json` was not re-recorded.
- **Listing:** 10,000 items 0.058 s and 100,000 items 0.552 s, with `isOnlineOnly` computed from the sizes.
- **Quick Look:** the first picture of a cold request 0.06 s; the generic folder and text icons 0.04 to 0.08 s.
- **End to end:** `make uitest` 29 tests, 0 failures, including five launches of the icon view and the audit with the icon view showing.

## The plan's Open Questions

1. *What does a thumbnail request for a dataless file do?* **Not answered.** A test cannot make a placeholder. The app never asks, with two guards.
2. *How fast, and with how many in flight?* About 220 per second at four, 240 at eight (above).
3. *Does `isOnlineOnly` from the sizes agree with iCloud's status on a real folder?* **Not answered:** it needs an iCloud folder with online-only files, which is a by-hand check. A sparse file looks the same to the rule.
4. *Cost of a collection view with 100,000 items?* 3.7 ms to lay out, 140 cells, 1.2 ms to reload.
5. *Does selection by index path survive a reload?* No: a reload clears it, and the controller applies the model's selection again.
6. *What does VoiceOver say for a cell, and does the audit pass?* The audit passes. VoiceOver was **not listened to**; the cell's spoken text is tested.

## What is not done

- The VoiceOver checks of steps 4, 5 and 6.
- The by-hand checks of a folder of photographs and of a real folder with online-only files.
- A scroll measurement in a release build; the probe ran as a debug test.
- A cache shared between tabs. Each browser has its own loader and cache (up to 2,000 pictures and 64 MB each), so a window with several tabs of photographs holds several.

## Related

- `docs/solutions/2026-10-12-list-view-notes.md`
- `docs/solutions/2026-10-11-live-updates-notes.md`
- `docs/solutions/2026-10-09-accessibility-notes.md`
