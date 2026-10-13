# Phase 1, step 7: following the path

- **Commit:** `Phase 1 step 7: column view`
- **Plan:** `plans/phase-1a-step-07-column-view.md`
- **Engineering note:** `docs/solutions/2026-10-13-column-view-notes.md`

## The family tree

Imagine a family tree drawn as a row of columns. The first column lists the oldest generation. Pick a person, and the next column lists their children. Pick one of them, and the next column lists theirs. Pick a person with no children and, in the last column, you see a card about them: a photograph and the facts.

That is how many people prefer to browse files, and it is the third way Cairn can show a folder. The first was a list, the second an album of pictures. This is the family tree.

## What changed

1. **A row of columns.** View > as Columns (Command-3). Selecting a folder shows its contents in the next column to the right, and so on as far as you go.
2. **A card for a file.** Select a file and the last column shows its picture, its name, what kind of thing it is, its size, the space it takes on disk, and when it was changed and added. A file that is not on this Mac says so and is never fetched to draw the picture.
3. **The same folder underneath.** What is selected, how it is sorted, where you have been and the live updates are shared with the other two ways. Switching keeps your place.
4. **The keyboard.** Right goes into a folder's column, Left comes back, Up and Down move within one, typing selects, and Open enters a folder.

## Words you will meet

- **Path.** The chain of folders from where you are to the one you have selected.
- **Preview.** A look at a file without opening it.
- **Echo.** A change made by the program that comes back to it as if someone else had made it.
- **Guard.** A check that stops something happening in the wrong situation.
- **Probe.** A quick experiment, to find out how something behaves before you build on it.

## Decisions, and what they teach

### The path was already there

When the list learned to open folders in place (step 5), the program started keeping a record of which folders were open, each one listed and watched for changes. A column view needs exactly that: the open folders on the way to your selection. So this step added no new record. It added one rule: when switching to columns, keep the open folders that lead to what is selected, and close the others.

**Lesson:** before building, look at what you already have. The right structure may have been built for a different purpose.

### A click is a request, not a fact

When you select a folder in a column, the control changes at once. But the program's record has to change too, and when it does it tells everyone, including the control that just asked. A control that obeys every announcement can end up reacting to its own request, which asks again, which is announced again.

The cure is to know which announcements are your own echo. A flag marks the time the program is acting on your behalf, and its announcements in that time are not treated as news. A test takes the flag away. The result is not a failed check but a crash: the program loops until it runs out of room.

**Lesson:** when two things must stay in step and either may change first, decide which one is the source, and be able to tell your own echo from a real change.

### Try the old part before you build on it

The column control is one of the oldest in the system. Before building, a small experiment gave it a hundred thousand names. It turned out to be lazy: it asks for the names it is about to draw, selecting a folder took about a millisecond, and a hundred thousand names took about a third of a tenth of a second to appear the first time.

**Lesson:** a quick experiment with the real part answers questions that reading about it cannot.

### One picture, described in two places

The accessibility check said the preview's picture had no description. The picture already had one. It had been given to the view that shows the picture, and the check reads the description from the picture itself.

In the album (step 6) the opposite was right: the picture there was decoration and the cell around it said everything, so the picture was hidden from the screen reader. Here the picture is the point, so it is described. Which one is right depends on what the picture means.

**Lesson:** a thing's description can live in more than one place, and "decoration or meaning?" decides what to do with it.

### Name what the system builds for you

The control made a list for each column and did not name it. The check complained, so the program now finds those lists and names them by their position, Column 1, Column 2, through the same one place every control in the program is named.

**Lesson:** you are answerable for the parts a system control makes for you, too.

## What the checks found

The accessibility check found two things (the unnamed lists and the picture's description), and the probes found that the control is lazy and fast enough. Removing the guard against echo crashed the test run, which is how it was known to matter.

## Left undone, and said so

- **VoiceOver.** The facts are words, the columns and the picture have names, and the automatic check passes, but nobody has listened to it. That is open from steps 4 to 7.
- **Remembered widths.** The columns are the control's default width. Remembering them is step 10's.
- **A folder of real photographs, by eye.** The picture pipeline was exercised with six hundred photographs in step 6, but the preview at its larger size has been tested with stand-ins.

## Questions to think about

1. In the column view, selecting a folder opens it, and selecting a file previews it. What should happen when you select two folders at once?
2. The flag stops the program reacting to its own announcements. What could go wrong if it were left set for too long?
3. A person with a screen reader meets the picture as one thing: "Preview of inner.txt". What would you change if the picture were a chart?

## Where to look next

- `Packages/BrowserUI/Sources/BrowserUI/ColumnBrowserController.swift`, the selection as a request
- `Packages/BrowserUI/Sources/BrowserUI/PreviewViewController.swift`, the card
- `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`, `pruneOpenFolders`
- `ARCHITECTURE.md`, "How a folder is shown as columns"
