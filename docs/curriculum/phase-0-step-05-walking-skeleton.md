# Phase 0, step 5: the walking skeleton

- **Commit:** `Phase 0 step 5: walking skeleton`
- **Plan:** `plans/phase-0-step-05-walking-skeleton.md`
- **Engineering note:** `docs/solutions/2026-10-09-walking-skeleton-notes.md`

## A thin rope across the canyon

There are two ways to build a bridge. You can finish one tower completely, every rivet and coat of paint, before starting the other. Or you can first get a single thin rope across the gap, then use it to pull over a thicker one, and build outward from a connection that already exists.

The second way finds out early whether the two sides can be joined at all. Engineers who build software call that first rope a walking skeleton: the thinnest possible version of the program that works from one end to the other. Until now Cairn was parts on a bench. In this step it stands up.

## What was added

Cairn can now do one small, complete thing: open on a folder, show what is inside in a list with name, size and date, let you step into a subfolder, and step back out. To do that, every layer had to connect for the first time:

- a **reader** that asks the disk what a folder contains;
- a **sorter** that puts names in the order Finder would;
- a **model** that holds what the window should currently show;
- a **view** that draws it and listens for your keys and clicks.

It cannot copy, rename or delete. That is deliberate.

## Words you will meet

- **End to end.** Through every layer, from the disk to the screen.
- **Asynchronous.** Started now and finished later, without making everything else wait.
- **Model** and **view.** The model holds the facts; the view shows them. Keeping them apart lets each be tested alone.
- **Unit test** and **end-to-end test.** The first checks one part by itself. The second drives the real app as a person would.

## Decisions, and what they teach

### Thin and whole beats thick and partial

A perfect disk reader with no window to show its results proves little. A crude reader wired all the way to a crude window proves that the design holds together. Problems that only appear where layers meet were found in week one instead of month six.

**Lesson:** connect everything thinly first. Thicken afterwards.

### Never make the interface wait for the disk

Reading a folder is usually instant, and occasionally very slow: a sleepy external drive, a network share. If the part of the program that draws the window stops to wait, the whole app freezes and the spinning beach ball appears. So reading happens elsewhere, and the window is told when the answer is ready.

**Lesson:** slow things must not stand in the path of things that need to be quick. Step 6 turns this from good intention into an enforced rule.

### A late answer to an old question

Here is a subtle trap. You open a huge folder, grow impatient, and open a small one instead. The small one's contents arrive first. Then the huge one's contents arrive, late, and replace what you are looking at. You are now staring at the wrong folder.

The fix is almost childishly simple: number each request, and ignore any answer whose number is not the latest. It is like a waiter who brings a dish to a table whose diners have changed; a ticket number settles it.

**Lesson:** whenever an answer can arrive late, check that the question is still the one being asked. This idea returns, with more teeth, in Phase 1.

### Let the user change their mind

A listing in progress can be cancelled, and there is a test that cancels one partway through a 100,000-file folder. Work that cannot be stopped keeps consuming effort for a result nobody wants.

**Lesson:** anything that can take a while should be stoppable.

### Decide what to say when there is nothing to show

An empty folder shows a sentence saying so. A folder that cannot be read shows why. A blank window would leave the user wondering whether the app is broken, still working, or finished.

**Lesson:** "nothing" and "something went wrong" are states too, and each deserves its own design.

### Sorting the way people expect

Is `file10` before or after `file2`? A naive sort says before, because `1` comes before `2`. Every person says after. Cairn sorts as Finder does, treating the digits as numbers.

**Lesson:** "correct" is defined by what the person expects, not by what is easiest to compute.

### Say what you are not doing yet

The plan records that the whole folder is loaded before any of it is shown, that this will be too slow for large folders, and that fixing it is Phase 1 work. Step 7 measures exactly how slow. Phase 1 step 3 fixes it.

**Lesson:** a known shortcut, written down, is a plan. An unrecorded one is a surprise.

## Questions to think about

1. What would be the risk of perfecting file copying before the app could display a folder?
2. Can you think of a time an app showed you stale information because something arrived late?
3. Why does an empty state need words, when it could simply be empty?

## Where to look next

- `Packages/FileSystemCore/Sources/FileSystemCore/DirectoryReader.swift`
- `Packages/BrowserUI/Sources/BrowserUI/BrowserModel.swift`
- `UITests/BrowsingTests.swift`, the first tests that drive the real app
