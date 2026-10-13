# Phase 1, step 6: a photograph album

- **Commit:** `Phase 1 step 6: icon view`
- **Plan:** `plans/phase-1a-step-06-icon-view.md`
- **Engineering note:** `docs/solutions/2026-10-13-icon-view-notes.md`

## The album and the index

Imagine two ways to look through a box of photographs. One is an index: a typed list of every picture's file name, in order. It is exact, and you can sort it, but you cannot tell what is in the box. The other is an album: each page shows the pictures themselves, with the name written under each.

Until this step, Cairn had only the index. This step adds the album. A folder can now be shown as a grid, each file drawn as a picture above its name, and you can switch between the two with a keystroke without losing your place.

## What changed

1. **A second way to show the same folder.** View > as Icons (Command-2) and as List (Command-1). The folder, what is selected, how it is sorted and where you have been are the same in both. Only how it is drawn changes.
2. **A picture appears at once, then a better one.** Every item shows its type's usual icon immediately. The real picture, a photograph's actual image or a document's first page, is made in the background for the items you can see, and replaces the usual one when it is ready.
3. **A memory for pictures.** A picture that was made is kept, up to a limit, and is made again only if the file has changed.
4. **Files that are not on this Mac.** Some files live in a cloud service and only appear in the folder. Drawing such a file could make the Mac download it. Cairn shows these with a small cloud mark and never asks for their picture.
5. **The same keyboard.** Arrow keys move in two directions, typing selects by name, and Open enters a folder.

## Words you will meet

- **Thumbnail.** A small picture of a file's contents.
- **Cache.** A short-term memory of results, so that the same work is not done twice.
- **Placeholder.** A file that appears in a folder but whose contents have not been downloaded.
- **Decoration.** Part of the picture on screen that carries no meaning of its own, and that a screen reader should skip.
- **In flight.** Started and not yet finished.

## Decisions, and what they teach

### A picture first, and a better one later

The grid has to feel complete at once. So each cell is given the usual icon for its kind of file immediately, which is a simple lookup that does not touch the disk, and only afterwards asks for the real picture. A person scrolling fast sees a full page of sensible pictures that sharpen, never a page of blanks.

**Lesson:** show something true immediately, and improve it when you can.

### Ask for what is on screen, and no more

A folder can hold a hundred thousand files, and a hundred thousand pictures would take a very long time and a lot of memory. A cell asks for its picture only when it is about to be shown and withdraws the request when it scrolls away. In a test, laying out a hundred thousand items made only a hundred and forty cells.

**Lesson:** work out what is visible and do that, not what exists.

### The limit came from a graph

How many pictures should be made at the same time? Too few and the page fills slowly; too many and nothing gets faster. A measurement with a hundred different photographs gave: one at a time, 1.4 seconds; two, 0.8; four, 0.45; eight, 0.42; sixteen, 0.41. Four is where the curve bends. Going higher buys almost nothing.

A trap in that measurement: running the same photographs again was much faster, because the system keeps its own memory of pictures it has made. Each run needed fresh files.

**Lesson:** choose a limit from a measurement, and check that the measurement is measuring what you think.

### The one piece of information that cost ten times

Whether a file is in the cloud could be read directly, as a single extra fact for each item. It looked free. Listing ten thousand files went from six hundredths of a second to over half a second, nine times slower, and a hundred thousand files from half a second to five. It was taken out the same hour. A cheaper rule is used instead, from two numbers that were already being read: a file that claims a size but has no space on disk is a placeholder.

The cheaper rule can be wrong for one rare kind of file, a "sparse" file, which also claims space it does not use. That is written down.

**Lesson:** every extra fact read for every item must be measured. The one you are sure is free is the one to measure first.

### Two guards on the thing that must never happen

Downloading a file because a picture was requested would be a real harm. So there are two guards: the cell does not ask, and the loader refuses if asked. A test fails if either is removed. Nobody could test what would happen if a placeholder were asked for, because a test cannot make one, so the guards have to be right on their own.

**Lesson:** when you cannot test the harm, make it impossible by two independent routes, and test both.

### One thing for the screen reader to say

A screen reader reads what is on screen as separate things. A cell was a picture, a cloud mark and a name, so it said "image" with no description for the picture. The fix was to make the whole cell one thing that says "alpha.txt, file", or "cloud.png, file, online only", and to tell the system its parts are decoration.

**Lesson:** decide what one thing the person should meet, and make that the thing.

## What the checks found

Beyond the ten-times slowdown, the accessibility audit found the undescribed picture, and finding cells by their spoken text changed how the end-to-end tests look for them. Both are fixed and tested.

## Left undone, and said so

- **The VoiceOver checks** of steps 4, 5 and 6 are still open. The cell's spoken text is tested; listening to it has not been done.
- **A real cloud folder.** Whether the size rule agrees with the cloud service on real placeholders needs a person with such a folder.
- **A folder of real photographs, by eye.** A probe scrolled six hundred and showed real pictures in all visible cells, with the longest pause about two frames, but a person has not looked.
- **No size control.** The pictures are one size. A slider is another control, with its own spoken name and state.

## Questions to think about

1. The cache keeps a picture until it is too old by count or size. What is a better rule for a person who goes back and forth between two folders?
2. A sparse file looks like a placeholder to the cheap rule. What would you want shown for it, and what would it cost to know for sure?
3. A cell is one thing to a screen reader. What would you lose if each cell were a picture, a mark and a name?

## Where to look next

- `Packages/BrowserUI/Sources/BrowserUI/ThumbnailLoader.swift`, the limit, the order and the refusal
- `Packages/BrowserUI/Sources/BrowserUI/ThumbnailCache.swift`, the memory and its bounds
- `Packages/BrowserUI/Sources/BrowserUI/IconItem.swift`, one cell
- `Packages/FileMetadata/Sources/FileMetadata/QuickLookThumbnailer.swift`, the system's generator
- `ARCHITECTURE.md`, "How a folder is shown as icons"
