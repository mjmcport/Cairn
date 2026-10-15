# Phase 1, step 9: an address read from the country down

- **Commit:** `Phase 1 step 9: path bar`
- **Plan:** `plans/phase-1a-step-09-path-bar.md`
- **Engineering note:** `docs/solutions/2026-10-14-path-bar-notes.md`

## An address read from the country down

A postal address starts small and ends large: a flat, a street, a town, a country. Each part sits inside the next. If you are lost, you do not need the whole address in your head. You need to know which part to step back to.

A folder's address works the same way. `/Users/matthew/Documents/Taxes` is a folder inside a folder inside a folder. Until this step Cairn showed only the last part, "Taxes", in the title, and the only way up was one step at a time. This step lays the whole address out as a row of names under the list, and adds two more ways to use an address: to type one, and to copy one.

## What changed

1. **The path bar.** A row of names, from the disk down to the folder you are in. Click a name and you are there, and Back brings you home. Next to each name is a small arrow that lists the folders inside it. When the row is too long, the early names fold into a "…" button.
2. **Go to Folder.** A sheet opens with Shift-Command-G. Type a path, with `~` for your home folder if you like, and the folders that fit what you have typed are offered. Tab finishes the name, Return goes there. If you type a file's path you land in its folder with the file selected.
3. **Copy Path.** Four ways to write the same address: plain, with its spaces protected for a terminal, as a web-style `file://` link, and short, starting from `~`. It copies the selected items, or the folder you are in.

## Words you will meet

- **Path.** The address of a file or folder: the names of the folders you pass through, separated by slashes.
- **Breadcrumb.** One name in a row that shows how you got somewhere, after the trail of crumbs in a fairy tale.
- **Completion.** Offering the rest of a word from the first letters.
- **Escaping.** Writing a character so that a program reads it as part of a name and not as an instruction.
- **Sheet.** A small panel that slides from a window's title bar and holds your attention until you finish with it.

## Decisions, and what they teach

### Do the thinking where the disk cannot be hurt

Turning an address into its parts, writing it four ways and reading what someone typed are all just text. None of it needs to look at the disk. So that part was written to be pure: give it text, get text back, and test it with a hundred small examples in a moment. The few things that must look at the disk, listing the folders inside one and asking whether a path is a folder, are the only guarded ones, and they run away from the main thread so the window never waits.

**Lesson:** separate the part that only thinks from the part that must touch the world, and test the first one hard.

### An answer for yesterday's question is wrong

You type "D", then "Do". The answer for "D" may take longer than the answer for "Do". If the late answer were shown, the list would jump back to something you no longer asked for. Each request gets a number, and an answer whose number is out of date is thrown away.

**Lesson:** when answers can arrive out of order, label each question.

### The small bug the test found

The first version of Copy Path pasted `/Users/me/Docs/` with a slash on the end, because a folder's address in the system's own form carries one. Nobody would have noticed in a quick try, but the test of "nothing selected copies the folder" read the pasteboard and said no. One place now removes the slash, and one test pins it.

**Lesson:** read back the actual result, not the one you meant.

### Text that was too pale

The line under the suggestions ("2 folders match.") was drawn in the system's secondary grey. The audit measured it a little below the contrast people with weaker eyesight need. Plain label colour fixed it. The same thing had happened to the sidebar's headings in the last step.

**Lesson:** if one grey failed once, check every grey.

### Be honest about what the audit cannot see

While you are typing, the system puts an invisible editing view over a text field. The accessibility audit complains about it in a way that names no element, and only while you are typing. It is the system's part, not Cairn's. The sheet is audited with focus on the list of suggestions, the typing is covered by other tests, and the gap is written down.

**Lesson:** a known gap, written down, is better than a test quietly loosened.

## What was left undone, and said so

- **VoiceOver** has not been listened to on the bar or the sheet; that check is open from steps 4 to 8.
- **A right-click "Copy Path"** on a name was planned as a default and not built; the menu command and its shortcut do the job.
- **Network volumes** were not tried.

## Questions to think about

1. Why does the bar list the folders inside a name, and not the folders beside it? What would you want if you were lost?
2. A path can contain a new line. Why is that a problem for a terminal, and how did the program solve it?
3. If you could change one of the four copy formats, which would you change and why?

## Where to look next

- `Packages/FileSystemCore/Sources/FileSystemCore/PathFormat.swift`, the four ways of writing an address
- `Packages/FileSystemCore/Sources/FileSystemCore/TypedPath.swift`, reading what was typed
- `Packages/BrowserUI/Sources/BrowserUI/PathBarView.swift`, the row of names
- `Packages/BrowserUI/Sources/BrowserUI/GoToFolderViewController.swift`, the sheet
- `ARCHITECTURE.md`, "How the path bar works"
