# Phase 0, step 7: a number instead of a feeling

- **Commit:** `Phase 0 step 7: performance baseline`
- **Plan:** `plans/phase-0-step-07-performance-baseline.md`
- **Engineering note:** `docs/solutions/2026-10-09-performance-baseline-notes.md`

## The slow drift

Ask people how well they slept and their answers are famously unreliable. Sleep laboratories exist because measurement and impression part ways. We are poor judges of slow change in particular: nobody notices a child growing, only the pencil marks on the door frame.

Software slows the same way. No single change makes an app sluggish. Each adds a few thousandths of a second, each is individually defensible, and a year later the app that once felt instant feels heavy, and nobody can say when it happened. This step makes the pencil mark on the door frame.

## What was added

- **Timed tests** for three jobs, each on a folder of 10,000 files and one of 100,000: listing the folder, sorting it by name, and reading extra details about every file.
- **One timed test of the real app:** how long from asking for a 10,000-file folder until rows appear.
- **A baseline file** holding the results, together with a description of the Mac that produced them.
- **A command, `make perf`,** that measures again and compares with the baseline.

## Words you will meet

- **Performance.** How fast a program does its work.
- **Baseline.** A recorded measurement that later ones are compared against.
- **Regression.** Something that became worse than it used to be.
- **Benchmark.** A repeatable timed test.

## What the measurements said

| Job | 10,000 files | 100,000 files |
| --- | --- | --- |
| List the folder | 0.054 s | 0.502 s |
| Sort by name | 0.144 s | 1.985 s |
| Read extra details for every file | 0.428 s | 5.405 s |
| Time until rows appear in the app | 0.266 s | not measured |

Three discoveries came straight out of that table.

**Sorting cost more than reading.** One might have guessed that fetching from the disk is the slow part. It was not. Putting names in order took nearly three times as long.

**The details are expensive.** Reading every file's extra details costs about ten times the listing. So those details should be fetched only for the files you are actually looking at.

**The app was missing its own target.** The project's goal is rows on screen within 0.2 seconds. The measurement said 0.266.

## Decisions, and what they teach

### Measure first

Every one of those three findings would have been a guess without the numbers, and at least one guess would have been wrong.

**Lesson:** intuition about where time goes is unreliable, even for experienced people. Measure before you decide what to fix.

### Record the bad news

The step did not fix the 0.266 seconds. It wrote the number down, said plainly that it misses the target, and left the repair for later. That may feel unsatisfying. But a baseline is supposed to be a truthful photograph of where things stand, and the photograph is what made the later fix (Phase 1, step 3) easy to aim and easy to prove.

**Lesson:** an honest measurement of a problem is progress, even before the problem is solved.

### A time means nothing without the machine

The baseline file records the exact Mac it came from. When these tests were later run on a rented cloud computer, they came out 40 to 85 percent slower, and nothing about the code had changed. Comparing times across different machines is like comparing two runners' times on different tracks.

**Lesson:** always record the conditions of a measurement along with the result.

### Measure the app's own stopwatch

Timing the app from outside would include the testing tool's own delays. So the app marks the start and end of each folder load itself, and the test reads those marks. The same marks show up in Apple's profiling tools, which helps a developer investigate later.

**Lesson:** measure as close to the thing itself as you can, so you are not timing your instrument.

### Warn before you block

For now, a slower result is reported, not treated as a failure. Timing varies a little from run to run, and a check that cries wolf gets ignored or switched off. The numbers were given time to prove stable first.

**Lesson:** a new alarm should earn trust before it is allowed to stop work.

## Questions to think about

1. Why might a developer's fast computer hide a speed problem that users will feel?
2. If each of fifty changes slows an app by 1 percent, how much slower is it at the end? Who was responsible?
3. What else would you want recorded alongside a timing, besides the model of computer?

## Where to look next

- `docs/performance/README.md` and `docs/performance/baseline.json`
- `scripts/performance.py`
