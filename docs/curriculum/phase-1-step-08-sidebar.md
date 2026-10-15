# Phase 1, step 8: the directory in the lobby

- **Commit:** `Phase 1 step 8: sidebar`
- **Plan:** `plans/phase-1a-step-08-sidebar.md`
- **Engineering note:** `docs/solutions/2026-10-13-sidebar-notes.md`

## The directory in the lobby

In the lobby of a big building there is a board that lists the places people want most: the front desk, the café, the library, the garage. You do not wander the corridors to find the café. You read the board and go.

A file manager had no such board. To reach the Documents folder you started where you were and walked, folder by folder. This step puts the board on the left of the window.

## What changed

1. **Four lists.** Favorites are places you chose, and you can add one or take one away. Locations are the disks that are plugged in, each with a small eject button where a disk can be ejected. Cloud lists your iCloud Drive and the folders other cloud services keep. Tags lists the labels you have put on files.
2. **Recents.** The first favorite shows the files you used in the last week, whichever folder they are in.
3. **A click goes there.** Choosing an item shows it in the tab you are in, and Back takes you home. Hold Command and it opens in a new tab.
4. **Places that are not folders.** A tag, or Recents, is not one folder. It is a question ("which files have this label?") with an answer that is a list of files from many folders. It looks and behaves like any other list.

## Words you will meet

- **Bookmark.** A note that follows a folder when it is moved or renamed, instead of pointing at a fixed address.
- **Virtual place.** A place that has no folder of its own: a list made by asking a question.
- **Index.** The system's catalogue of what is on the disk, which answers questions like "which files have this tag?" without opening every folder.
- **Source.** Something the program asks for facts, such as the list of disks.
- **Hermetic.** A test that depends on nothing but what it makes itself.

## Decisions, and what they teach

### A place is an address

The browser already knew how to move between folders, keep a history and show a title, all by holding an address. Rather than teach it a second idea, a tag was given an address of its own kind, `cairn-tag:Red`, and one small piece decides who answers: a folder address goes to the folder reader and the other kind goes to the question reader. The rest of the program did not change, and Back worked at once.

**Lesson:** when something new looks different, check whether it can be made to look the same where it matters.

### A favorite follows the folder

If a favorite remembered a folder as text, moving the folder would break it. A bookmark remembers the folder itself. A favorite whose folder is gone is not quietly dropped: it stays, greyed, and says "not found", because a thing that vanishes without a word is worse than a thing that says it is lost.

**Lesson:** say what is wrong instead of hiding it.

### The button acts on its own row

Ejecting a disk is the one thing in this step that cannot be undone by a click. So the button belongs to a row and acts on that row's disk, nothing ejects without a press, and a failure says why and leaves the disk where it is. A test presses the button of one of two disks and checks which one was asked.

**Lesson:** where a mistake costs the most, make the wrong action hard to reach, and prove it.

### The test found what the plan did not

Three things were wrong that no unit test saw. The sidebar took width, so a column of the list was drawn outside the window. The headings of the lists were light grey on light grey, which many people cannot read. And when the window opened, the keyboard was in the sidebar, not the list, so the arrow keys moved the wrong thing. They were found because a test used the program the way a person does, with the keyboard and a screen-reader audit.

**Lesson:** a new part changes the parts around it. Test the whole.

### A test should not depend on what you did yesterday

The first audit of Recents failed because the person running it had used an app lately, and its row was cut by the window's edge. A test that depends on the tester's week is not a test. Two switches now point the program at the test's own folder and its own favorites.

**Lesson:** give a test its own world.

## What the review found

The same folder, added twice, was stored twice, because it can be spelled two ways (`/var` and `/private/var`) and a text comparison called them different. The check now resolves the spelling away from the main thread. The name "Recents" was also the same place as a tag called Recents until the kind of address became part of the comparison.

## Left undone, and said so

- **VoiceOver.** The names and states are words and the audit passes, but nobody has listened. That is open from steps 4 to 8.
- **Ejecting a real disk, and a real cloud folder.** Tested with stand-ins; to be done by hand.
- **Live tags.** A tag changed elsewhere appears when you go back to it, not while you look.
- **Remembering the sidebar.** Its width and any collapsed lists are step 10's.

## Questions to think about

1. A tag lists files from many folders, and two of them can have the same name. What should "select this file" mean, if names are not unique?
2. Why is it all right for Recents to list files but not to open folders in place?
3. If you could add one place to the sidebar for every person, which would it be, and what would it cost to keep it right?

## Where to look next

- `Packages/FileSystemCore/Sources/FileSystemCore/VirtualLocation.swift`, the address of a place that is not a folder
- `Packages/FileSystemCore/Sources/FileSystemCore/MetadataQueryReader.swift`, the question reader and the composite
- `Packages/BrowserUI/Sources/BrowserUI/SidebarViewController.swift`, the list and the eject button
- `ARCHITECTURE.md`, "How the sidebar works"
