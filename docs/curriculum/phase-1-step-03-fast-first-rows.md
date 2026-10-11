# Phase 1, step 3: the first rows, at once

- **Commit:** `Phase 1 step 3: fast first rows` (pull request #10)
- **Plan:** `plans/phase-1a-step-03-fast-first-rows.md`
- **Engineering note:** `docs/solutions/2026-10-10-a-load-that-publishes-twice.md`

## The bread basket

A good restaurant does not bring your meal any sooner than the kitchen can cook it. What it does is bring bread and water within a minute of your sitting down. The total time until the main course is unchanged, and yet the evening feels entirely different, because you were never left looking at an empty table wondering whether anyone had noticed you.

Waiting is strange in this way. A fifth of a second feels instantaneous. A whole second is long enough to wonder if something has broken. And a wait with nothing to look at feels far longer than the same wait with something in front of you.

Back in Phase 0, step 7 measured how long Cairn took to show a folder of 10,000 files: 0.266 seconds. The project's own standard is 0.2. Step 5 had admitted the cause in advance: Cairn read the entire folder, then sorted the entire folder, and only then showed anything. This step brings the bread.

## What changed

1. **Show something early.** The reader now hands over the first 2,000 files as soon as it has them, and the complete list after. The window shows the early ones immediately, then settles into sorted order.
2. **Sort faster.** The sort had been repeating one small chore hundreds of thousands of times. Now it does it once per file.
3. **Sort in the background,** so the window stays responsive while a very large folder is put in order.
4. **Make the standard checkable.** The 0.2-second limit is written in a file, and `make perf` measures the app and gives a verdict.

The result on the reference Mac: first rows in 0.026 seconds. About ten times faster, and well inside the limit.

## Words you will meet

- **Main thread.** The one line of work that draws the window and answers your clicks (the cashier from Phase 0, step 6).
- **Background work.** Work done away from the main thread.
- **Stream.** Handing over results in pieces as they become ready, instead of all at once.
- **Race.** A bug that depends on which of two things happens first.
- **Baseline** and **regression.** A recorded measurement, and a later result that is worse.

## Decisions, and what they teach

### The measurement chose the strategy

The baseline said: 0.054 seconds to read the folder, 0.144 to sort it. Reading was already quick. The delay was the sort. So the plan almost wrote itself: do not make the user wait for the sort.

Without those two numbers, the natural guess would have been to speed up the disk reading, which was not the problem.

**Lesson:** measure, then aim. Phase 0's patient step 7 is what made this step short.

### How it feels, and how long it takes

Showing first rows early does not finish the whole job sooner. It changes what the wait feels like. The step did both things: it made the wait feel short, and it also made the total work faster.

**Lesson:** ask "what is the person waiting for?" before asking "how do I make this faster?".

### Why 2,000

Not a round number plucked from the air. Measurements showed that a folder of 2,000 files can be read *and fully sorted* in about 16 thousandths of a second, the time a screen takes to redraw once. Below that size, showing unsorted rows first would produce only a flicker. So small folders behave exactly as they always did, and only large ones get the two-stage treatment.

**Lesson:** a number in a program should have a reason someone can state.

### The chore that was done 187,000 times

To compare two files, the old sort worked out each one's name from scratch. Sorting 10,000 files takes roughly 187,000 comparisons, so the same names were worked out over and over. Imagine alphabetizing a stack of letters by opening each envelope every time you compare two. The new sort reads each name once, writes it on the outside, and sorts by that. Sorting became about five times faster.

**Lesson:** when something is slow, look for a small job being repeated inside a big loop.

### Is this still wanted?

The hard part. Once a load shows its results twice, with waiting in between, a person can leave the folder during the wait. The old load then wakes up and, unless it stops to check, puts the *previous* folder's files into the window you are now looking at.

Step 5 met a mild form of this and solved it with a ticket number. Here there were more waits, and so more places to forget to check. Each load holds a number; moving to another folder changes the current number at once; and before a load shows anything, at every stage, it asks whether its number is still current.

Three distinct versions of this bug were found, each one by a test that failed first. One of them is a surprise worth knowing: when a stream of results is cancelled, it does not announce a failure. It simply ends, looking exactly like a stream that finished normally.

**Lesson:** every time code waits and then acts, ask what may have changed while it waited. These bugs raise no alarm. The person simply sees the wrong thing.

### "Stopped early" must never look like "empty"

Because a cancelled stream ends quietly, an interrupted read could be mistaken for a folder with nothing in it. In a file manager, showing a full folder as empty is the kind of mistake that makes someone think their files are gone. An unfinished read is therefore treated as an error and reported as one.

**Lesson:** make failure loud. A quiet wrong answer is worse than an honest error.

### Tests that hold time still

How do you test "the person leaves while the sort is running"? You need to stop the sort halfway. The code was shaped to allow it: a test can substitute a sort that waits at a gate until the test opens it. No test says "wait half a second and hope".

**Lesson:** tests that depend on timing fail at random. Design the code so the test can decide the order of events.

### A standard a machine can judge

"Rows within 0.2 seconds" had been a sentence. Now a command reads it from a file and judges it. Since speed depends on the computer (step 9 learned that the hard way), the verdict is given only on the Mac that recorded the baseline. Elsewhere the time is shown with no judgement.

**Lesson:** turn important standards into automatic checks, and be honest about where the check is valid.

### Not writing down an unmeasured number

The work was finished and reviewed a day before its speed could be measured, because the measurement needs a person at the Mac to approve a security prompt. In that day, the baseline file was left untouched and the documents said plainly that it had not been re-recorded.

**Lesson:** "not measured yet" is a fine thing to say. A guess dressed as a measurement is not.

## What the review found

Nine reviewers read the change. None found a defect that had to be fixed. One raised a doubt it was not sure of: a brief moment, just after moving to a new folder, in which an old load was still considered current. A test was written, the doubt turned out to be real, and it was fixed.

**Lesson:** take small doubts seriously enough to test them.

## Left undone, and said so

- A check with VoiceOver that the list is not read out twice as it settles. It needs a person, and was postponed.
- The automatic accessibility audits do not complete on the development Mac. The shared examiner runs them.

## Questions to think about

1. The app now shows unsorted rows for a moment. What should happen if you click a row just before the list re-sorts? (The plan's answer is under "KTD8".)
2. Why is "wait half a second, then check" a poor way to test a race?
3. The 0.2-second standard is judged on one particular Mac. What does that choice cost? What would judging it everywhere cost?

## Where to look next

- `Packages/FileSystemCore/Sources/FileSystemCore/DirectoryReader.swift`, reading in two stages
- `Packages/FileSystemCore/Sources/FileSystemCore/FileItemSort.swift`, the faster sort
- `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`, the load and its "still wanted?" checks
- `docs/performance/README.md`, the measurements and the target
