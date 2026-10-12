# Phase 1, step 4: a list that keeps up

- **Commit:** `Phase 1 step 4: live updates`
- **Plan:** `plans/phase-1a-step-04-live-updates.md`
- **Engineering note:** `docs/solutions/2026-10-11-live-updates-notes.md`

## The departures board

A railway station has a board that lists the next trains. Imagine a board that was written once, in the morning, in chalk. It is accurate at the moment the station master finishes. After that, trains are delayed and platforms change, and the board goes on saying what was true at breakfast. Nobody would call that a departures board. They would call it a poster.

Until this step, Cairn's list of files was a poster. It listed a folder when you opened it, and then it said the same thing for as long as you looked. If another program added a file, renamed one or deleted one, you saw it only after you left the folder and came back.

This step turns the poster into a board.

## What changed

1. **Cairn asks the Mac to tell it.** macOS has a service, called FSEvents, that reports changes to folders. Cairn now listens to it for the folder that is on screen.
2. **Changes are gathered, then answered once.** The Mac collects changes for about a third of a second. If fifty files appear at once, Cairn is told once, not fifty times.
3. **Cairn looks at the folder again, quietly.** It reads the whole folder in the background, sorts it, and compares the result with what is on screen. If nothing you can see has changed, it does nothing at all.
4. **Your place is kept.** The row you selected stays selected, the list stays scrolled where it was, and keyboard focus does not move.
5. **Only what you are looking at is watched.** A tab that is not showing, and a window that is closed, watch nothing. A tab that comes back brings itself up to date.

In the tests, a new file showed in the list between about a hundredth of a second and a third of a second after it was created. The standard was one second.

## Words you will meet

- **FSEvents.** The service in macOS that reports changes to the file system.
- **Signal.** A short message, "something changed here, look again". It does not say what.
- **Refresh.** Reading a folder again and updating the list, as opposed to a **load**, which is what happens when you open a folder.
- **Coalescing.** Gathering several events that arrive close together into one.
- **Callback.** A piece of code that you hand to a system so it can call you back when something happens.

## Decisions, and what they teach

### Be told "something changed", not "this changed"

The Mac can report either the folder that changed or each file inside it. Cairn takes the first. A message that says "look at this folder again" is cheap, and the code that looks at a folder already knows every rule about hidden files, shortcuts and files that vanished while it was reading. Working out the change file by file would have meant writing those rules a second time.

The cost is that a folder with a hundred thousand files takes longer than a second to re-read. The plan says so, and says what would change it.

**Lesson:** when two ways of doing something both work, prefer the one that reuses a rule you already trust, and write down what that choice costs.

### A third way for rows to arrive

Step 3 taught the list to ask "is this still wanted?" after every pause, because a slow load could wake up and fill the window with the folder you had just left. Step 3 also named what was coming: live updates are a third way for rows to arrive, and they need the same question.

So a refresh carries a number, as a load does, and checks it after each wait. But the rule is one-sided. A refresh may be cancelled by a move or a load. A refresh may never cancel a load. Otherwise a file arriving at the wrong moment could abort your navigation.

**Lesson:** a new source of change should fit the rules that already exist, and the rules should say who is allowed to cancel whom.

### The first rows are never replaced

While a large folder is still being listed, Cairn shows its first rows. If a change arrives then, a refresh would be reading the same folder a second time and showing a different picture of it. So the signal is set aside. When the load finishes, it pays what was owed with one refresh.

**Lesson:** when two things want to update the same screen, decide the order in advance and make one of them wait.

### Nothing changed, nothing published

Most refreshes find the list exactly as it was, for instance when a file changed inside a subfolder you have not opened. Reloading the table anyway would make the screen redraw and, for a person using VoiceOver, might make it read the same row out again. So the comparison is done in the background, and nothing is published unless a visible row is different.

**Lesson:** doing nothing is a feature. Make the quiet case really quiet.

### A folder that goes away is an ordinary failure

If the folder you are looking at is deleted, there is no special "gone" path. The refresh tries to read it, the read fails, and the list shows why, in the same way it does for any folder it cannot read. The watch stays, so if the folder comes back, it is listed again.

**Lesson:** a new situation is often an old one in different clothes. Look for the existing path before building a new one.

### A promise is not an owner

Here is a bug that review found, and no test had. Cairn hands the Mac a pointer to its watching object, and the Mac calls back with it whenever something changes. The first version did not tell the Mac to keep the object alive. It promised instead that the object would stay alive until the watch was stopped, and that nothing would be called after that.

The promise held almost always. But the Mac could, at the very moment Cairn stopped the watch, already have a call on its way. That call would arrive at an object that was gone. It would be rare, it would depend on timing, and it would crash.

The fix was to ask the Mac to hold the object itself for as long as the watch exists. Its ownership is then not a promise made by the programmer, it is a fact in the system.

**Lesson:** when another system calls you back later, make it share ownership. "It will not happen" is not the same as "it cannot happen".

### A test that passed for the wrong reason

The test for "within a second" passed on the first run, showing the file in 1.3 thousandths of a second. That was suspiciously quick: the Mac itself gathers changes for up to a third of a second. The likely cause was a stray message left over from building the test's own folder, which prompted a refresh that happened to run after the file was written.

The test now waits for a full second of silence before it touches the disk, so that the only change left to notice is its own. The readings afterwards ranged from 0.015 to 0.31 seconds, which fits the Mac checking on its own third-of-a-second rhythm.

**Lesson:** a measurement that is better than it should be deserves suspicion at least as much as one that is worse.

### The same computer, a different answer

The performance check is run on the reference Mac. The first time, six of seven measurements looked far worse than the baseline, up to three times slower, including ones this step never touched. A minute later, the same run had all six within a few percent. The Mac was busy with its own background work: its load was above eight.

The step's own number, the time to first rows, was within its limit on both runs. The baseline file was left alone.

**Lesson:** record the conditions of a measurement along with the number, and run it again before believing a bad one.

## What review found

Reading the change against the plan turned up the ownership problem above and the weak timing test. Both were fixed and nothing else needed changing.

## Left undone, and said so

- **The VoiceOver checks were skipped.** The plan asked for a person to listen to VoiceOver while files were created, renamed and deleted from Terminal, and to record what it says when the item under its cursor disappears. That has not been done. Cairn is built so that it should say nothing by itself during a refresh, but that has not been confirmed by listening.
- **A folder of a hundred thousand files will not meet the one-second bound.** The plan works out that it takes a little over a second, and names the larger change that would be needed.
- **Network shares are not covered.** FSEvents does not report changes that another computer makes on a share. Those get their own treatment later in Phase 1.
- **Other versions of macOS.** The tests that use a real FSEvents stream have run only on the development Mac so far (macOS 27). They are to run on macOS 26 in the shared examiner and on macOS 15 by hand before the step is merged.

## Questions to think about

1. Cairn re-reads a folder with ten thousand files in a fraction of a second. At what size would you stop doing it that way, and what would you do instead?
2. A file is being written steadily by another program, a hundred times a second. What does the person see, and what is the right thing for them to see?
3. Why is it better for the refresh to be unable to cancel a load than for the load to be unable to be interrupted by a refresh?

## Where to look next

- `Packages/FileSystemCore/Sources/FileSystemCore/FolderWatcher.swift`, the listener and its three signals
- `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`, the watch session and the refresh, beside the load
- `Packages/BrowserUI/Sources/BrowserUI/PaneViewController.swift`, which decides who is watching
- `ARCHITECTURE.md`, "How a change on disk reaches the list"
