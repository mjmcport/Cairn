# Phase 1, step 3: fast first rows

- **Commit:** `Phase 1 step 3: fast first rows` (pull request #10)
- **Plan:** `plans/phase-1a-step-03-fast-first-rows.md`
- **Engineering note:** `docs/solutions/2026-10-10-a-load-that-publishes-twice.md`

This page is for readers who are new to software engineering. It explains what the step changed, which decisions were made and why, and what is worth learning from it. You do not need to read the code first.

## The problem in plain words

Cairn is a file manager. When you open a folder, it has to do two jobs before the list looks right: read the folder's contents from the disk, and put them in order.

Before this step Cairn did both jobs in full and only then showed anything. For a folder with 10,000 files that took 0.266 seconds. The project's own quality rule says rows must appear within 0.2 seconds, so the app was failing its own rule. With 100,000 files it was worse: the window froze for about two seconds while it sorted.

## What changed

1. **Show something early.** The part of the app that reads a folder now hands over the first 2,000 files as soon as it has them, and the complete list afterwards. The window shows those first files straight away, unsorted, and then settles into sorted order.
2. **Sort faster.** The sort was doing the same small piece of work, extracting a file's name, hundreds of thousands of times. Now it extracts each name once.
3. **Sort in the background.** The sort no longer runs on the main thread, so the window keeps responding while a big folder is put in order.
4. **Make the rule checkable.** The 0.2 second limit is written in a file, and the command `make perf` measures the app and says whether the limit was met.

The result on the reference Mac: first rows in 0.026 seconds, about ten times faster than before and well inside the limit.

## Words you will meet

- **Main thread.** The one line of work that draws the window and reacts to clicks and keys. If slow work runs there, the app appears frozen.
- **Background work.** Work done away from the main thread, so the window stays responsive.
- **Stream.** A way to hand over results in pieces over time instead of all at once.
- **Race.** A bug that depends on which of two things happens first. Races are hard to find because they often do not happen when you are looking.
- **Baseline.** A saved set of measurements that later measurements are compared against.
- **Regression.** Something that used to work, or used to be fast, and got worse.

## Decisions and why they were made

### Measure before changing anything

The earlier baseline showed where the time went: 0.054 seconds to read the folder and 0.144 seconds to sort it. That one fact shaped the whole step. Reading was already fast, so the gain had to come from not making the user wait for the sort.

**Lesson:** guessing where a program is slow is wrong surprisingly often. Measure first, then spend effort where the time is.

### Perceived speed matters as much as total speed

Showing the first rows early does not make the whole job finish sooner. It makes the wait feel short, because the user has something to look at and act on. The step did both: it shortened the wait and also made the total work faster.

**Lesson:** ask "what is the user waiting for?" before asking "how do I make this faster?".

### Why 2,000 files, and not 100 or 10,000

The number came from measurement. A folder of 2,000 files can be read and fully sorted in about 16 milliseconds, which is one screen refresh. Below that size, showing unsorted rows first would only make the list flicker for no benefit. So small folders behave exactly as before, and only large ones get the two-stage display.

**Lesson:** a number in the code should have a reason you can state. Here the reason is written down next to the decision.

### Do the repeated work once

The old sort compared two files by rebuilding both names every time. Sorting 10,000 files takes roughly 187,000 comparisons, so the same names were rebuilt again and again. The new sort prepares each name once and then compares the prepared values. That alone made sorting about five times faster.

**Lesson:** when something is slow, look for work that is repeated inside a loop and could be done once outside it.

### Keep slow work off the main thread

Even a faster sort takes a third of a second for 100,000 files. Doing it in the background means the user can still scroll, click and press keys in the meantime.

**Lesson:** the main thread is for the interface. Anything that can take noticeable time belongs elsewhere.

### A two-stage load needs a "still wanted?" check at every stage

This was the hardest part of the step. Once a load shows results twice and waits in between, the user can leave the folder during a wait. The old load then wakes up and, unless it checks, puts the wrong folder's files on screen.

The fix is simple to describe: every load gets a number, and before it shows anything it checks that its number is still the current one. The check is made after every piece that arrives, after the reading is finished and after the sort. Moving to another folder changes the current number at once, which retires any load still running.

Three separate versions of this bug were found, each by a test that failed first.

**Lesson:** whenever code waits and then acts, ask what may have changed during the wait. This kind of bug does not crash and logs no error; the user just sees the wrong thing.

### "Ended early" must never look like "empty"

If the reading stops before it is finished, the app could mistake that for a folder with nothing in it. An empty-looking folder that is not empty is dangerous in a file manager. So an unfinished read is treated as an error and reported as one.

**Lesson:** make failures loud. A quiet wrong answer is worse than an error message.

### Tests that control the order of events

To test "the user leaves while the sort is running", a test must be able to pause the sort. The code was shaped to allow that: the test swaps in a sort that waits at a gate until the test opens it. No test uses a timer or a "wait half a second and hope".

**Lesson:** tests that depend on timing fail at random. Design the code so a test can decide the order of events.

### Every test was seen to fail first

Each new test was run once against code without the fix, to confirm it fails. A test that has never failed might not be checking anything.

**Lesson:** a passing test proves something only if you have seen it fail for the right reason.

### A performance rule a machine can check

"Rows within 0.2 seconds" used to be a sentence in a document. Now it is a file that a command reads and judges. Speed depends on the computer, so the rule is only judged on the Mac that recorded the baseline; on other machines the time is shown without a verdict.

**Lesson:** a rule nobody checks slowly stops being true. Turn important rules into automatic checks, and be honest about where the check is valid.

### Do not write down a number you did not measure

The step was finished and reviewed a day before its speed could be measured, because the measurement needs a person to approve a prompt on the Mac. The baseline file was left untouched until the real run happened, and the documents said so in the meantime.

**Lesson:** it is fine to say "not measured yet". It is not fine to fill the gap with an estimate that looks like a measurement.

## What the review found

Nine automated reviewers, each looking for a different kind of problem, read the change. None found a defect that had to be fixed. One raised a low-confidence concern: a short moment after the user moves to a new folder in which an old load was still considered current. A test confirmed it was real, and it was fixed.

**Lesson:** a second pair of eyes is worth it even when it finds one thing. Take small doubts seriously enough to test them.

## What was left undone, and said so

- A check with VoiceOver, the screen reader, that the list is not read out twice. It needs a person and was postponed.
- The four automatic accessibility audits do not complete on the development Mac. They run in continuous integration instead.

**Lesson:** a list of what was not done is part of the work. It lets the next person trust everything else.

## Questions to think about

1. The app now shows unsorted rows for a moment. What could go wrong if the user clicks a row just before the list re-sorts? How would you want the app to behave? (The plan's answer is under "KTD8".)
2. Why is a timer-based test ("wait 0.5 seconds, then check") a poor way to test a race?
3. The 0.2 second rule is judged on one specific Mac. What are the costs of that choice, and what would be the costs of judging it everywhere?

## Where to look next

- `Packages/FileSystemCore/Sources/FileSystemCore/DirectoryReader.swift`: reading in two stages.
- `Packages/FileSystemCore/Sources/FileSystemCore/FileItemSort.swift`: the faster sort.
- `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`: the load and its "still wanted?" checks.
- `docs/performance/README.md`: the measurements and the target.
