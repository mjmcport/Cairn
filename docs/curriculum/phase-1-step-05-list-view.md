# Phase 1, step 5: a drawer without leaving the room

- **Commit:** `Phase 1 step 5: list view`
- **Plan:** `plans/phase-1a-step-05-list-view.md`
- **Engineering note:** `docs/solutions/2026-10-12-list-view-notes.md`

## The filing cabinet

Picture a filing cabinet in a small office. To see what is in a drawer you have two choices. You can carry the whole drawer to another desk, work there, and carry it back. Or you can pull the drawer open where it stands, with the cabinet still in front of you and every other drawer still where it was.

Until this step, Cairn only knew how to carry the drawer. Opening a folder meant going into it: the window changed to show that folder and nothing else, and to see the folder you came from you pressed Back. This step teaches the list to pull a drawer open in place. A folder gets a small triangle. Click it, and what is inside appears just underneath, indented a little, while the rest of the list stays exactly where it was.

## What changed

1. **The list became an outline.** Folders have triangles, and what they hold is listed beneath them. A folder inside a folder opens the same way, as deep as you like.
2. **Everything that was true of one folder became true of each open one.** Each open folder is listed in the background, sorted, watched for changes made by other programs, and kept up to date, just as the top level was in step 4.
3. **Two new columns, and headers that sort.** Size on Disk (what a file really takes up, which can differ a lot from its size) and Date Added (when it arrived in its folder). Clicking a column header sorts every level at once.
4. **Keep Folders on Top** in the View menu groups folders ahead of files at every level, and **typing** selects the row whose name starts with the letters you type.
5. **Going Back reopens what was open.** When you leave a folder and come back with Back or Forward, the folders you had open are opened again, unless you have turned that off in the new Settings window.

## Words you will meet

- **Outline.** A list whose rows can have rows beneath them, such as an index with sub-entries.
- **Handle.** The thing a list holds to stand for one row, so it can tell later that it is the same row.
- **Key.** Here, the names you pass through to reach a folder, such as Sub, then Deep.
- **Token.** A number that says which opening of a folder a piece of work belongs to.
- **Setting.** A choice the person using the program can change, and which the program remembers.

## Decisions, and what they teach

### Name a place by the names on the way to it

The list needs to say "this exact row" in many places: which rows are selected, which folders are open, which ones to reopen on Back. The obvious label is the file's address on disk. But the same folder can be reached by two spellings of its address, because of shortcuts the system keeps, and a row's address as listed is not always the address of the folder that was opened. So the list names a row by the names on the way down from the folder you are looking at: Sub, then Deep, then notes.txt.

**Lesson:** when two different labels can mean the same thing, pick the one that cannot be spelled two ways.

### Two files with the same name

Names alone would not do either. Many folders have a `notes.txt`. If selecting `Sub/notes.txt` also selected the top-level `notes.txt`, the list would be wrong in a way nobody would notice until it mattered. The lookup therefore tries the exact address first, then the path of names below the folder, and only for something from outside the list falls back to a name at the top. And a path that is *below* the folder but cannot be found is never allowed to fall through to the top.

**Lesson:** a fallback is fine; a fallback that catches things it was not meant for is a bug.

### A second kind of arrival, the same rules

Step 3 taught the list to ask "is this still wanted?" after every pause, and step 4 added a third way for rows to arrive. An open folder is a fourth. Rather than build a new set of rules, each open folder carries a token beside the counter the whole list already had, and checks both after every wait. A refresh of one folder reads the counter and never changes it, so a file appearing in a folder can never cancel a navigation.

One slip is worth telling. When a reload listed an open folder again, a change signal that had arrived during the reload was paid a second time by that same listing, so the folder was listed three times instead of two. A test that counted listings found it.

**Lesson:** a signal that has been answered has to be forgotten, not just skipped.

### The list only asks for what it draws

The list view does not ask the program for every row. It asks for the rows it is about to draw. A folder row far down a long list may never have been asked for, and a cache of "the rows I have given out" had nothing to open for it. The fix was to make the missing handle from what the program already knows.

**Lesson:** a cache of what a system has asked for is not a list of everything that exists.

### A test that measures its neighbours

The step 4 test that checks a change shows within one second began to fail, reading 1.2 to 3 seconds. Run alone it still read a hundredth of a second. The test and many others run together in one process and share one thread that draws everything. The new tests, which draw real windows, kept that thread busy, so the clock test was measuring how busy its neighbours were, not how fast the code was.

The bound was not loosened. The tests that assert on a clock are now named in the `Makefile` and run alone, after the rest.

**Lesson:** a test that measures time is measuring its surroundings too. Give it a quiet room, not a looser stopwatch.

### A failure that never reports

While checking that the new tests really fail when the code is broken, a deliberately broken version made one test wait for something that would never happen. It did not fail; it simply never finished, and everything queued behind it. Every wait in the test helpers now has a bound and reports when it is exceeded.

**Lesson:** a hang is a failure with the report missing. Give every wait an end.

### Before blaming yourself, check the old version

The accessibility audit began to fail on a name's contrast in some full runs. It looked like the new outline. So the same suite was run on `main`, which has the old table, in a separate checkout. It failed the same way, twice out of two. The problem was already there on this Mac, and the step did not cause it.

**Lesson:** a measurement of the old version is the cheapest way to know whose problem a new failure is.

### Remembering, and letting a person change their mind

What was open is stored with each place in the history, always. Whether it is used is decided when you go back, by a setting that defaults to on. Storing always means that if you turn it on later, places you left while it was off are still remembered. The setting is read at the moment you press Back, not when the folders finish opening.

A small window, Cairn > Settings, holds the one checkbox. It is the first window of its kind in the app, and the first use of SwiftUI there.

**Lesson:** record the facts always; decide at the last moment what to do with them.

### What a test can see

A unit test could not find the checkbox in the Settings window: the system builds the description that assistive technology reads only when assistive technology asks for it. The end-to-end test, which asks the way a screen reader does, found it at once, by name. The audit also reported an unnamed group that was not the checkbox but the box around it, so that box got a name too.

**Lesson:** test a thing from the same side it will be used from.

## What the checks found

The tests, and breaking the code on purpose to see them fail, turned up three things worth keeping: the owed signal paid twice, a guard that a test did not isolate, and a test that read the wrong notification name. The guard, a token that makes a stale listing publish nothing, turns out to be redundant with cancellation when a folder is closed. It stays, because a relisting after a reload is not preceded by a close. The note says so.

## Left undone, and said so

- **The VoiceOver checks were skipped again.** What a screen reader says for a row's level and open state, and when a folder opens, has not been listened to. The program is built to say nothing by itself during a refresh, but that is a design, not an observation.
- **An audit that fails sometimes.** On the macOS 27 development Mac the populated-folder accessibility audit fails in some full runs, here and on `main`. It was recorded and not fixed.
- **A 100,000-item folder.** It opens in about 1.3 seconds, and the main thread was not held by the program's own work during a sample, but a quarter-second of late ticks in the measurement was not explained.
- **Not remembered across a quit.** What is open is kept with the history for as long as the window lives, and no longer. Remembering across quits is a later step.

## Questions to think about

1. The list names a row by the names on the way down. What would go wrong if two folders on the way down could have the same name? (Think about what a file system allows.)
2. A refresh of one open folder is not allowed to cancel a navigation. Is the opposite also true: should a navigation be allowed to cancel a refresh? Why?
3. The setting is the same for every window and tab. When would you want it to differ?

## Where to look next

- `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`, the open folders, their watches and the restore
- `Packages/BrowserUI/Sources/BrowserUI/BrowserViewController.swift`, the outline
- `Packages/BrowserUI/Sources/BrowserUI/OpenFolder.swift`, the key
- `ARCHITECTURE.md`, "How a folder opens in place"
