# Phase 0, step 4: a laboratory of files

- **Commit:** `Phase 0 step 4: fixture builder`
- **Plan:** `plans/phase-0-step-04-fixture-builder.md`
- **Engineering note:** `docs/solutions/2026-10-09-fixture-builder-notes.md`

## The controlled experiment

A sleep researcher who wants to know what caffeine does to sleep does not simply ask people how they slept. She controls the room, the light, the bedtime and the dose, changes one thing, and measures. Without that control, any result could be explained by a dozen other causes.

A file manager has to be tested against files. But whose files? Your Documents folder differs from mine, changes every day, and holds things neither of us wants a test to touch. So before Cairn could be tested at all, it needed a way to conjure a small, exactly known world of files, use it, and sweep it away.

## What was added

A **fixture builder**: a tool, used only by tests, that reads a short description of a folder tree and creates it for real in a temporary place. A test can ask for, in a few lines:

- ordinary files with given contents or a given size;
- hidden files, of both kinds macOS has;
- folders, shortcuts to other files (links), and application bundles;
- files with tags, unusual permissions, or the "downloaded from the internet" mark;
- names in many alphabets, and a name of the maximum allowed length;
- a folder of 10,000 files, or 100,000.

## Words you will meet

- **Fixture.** A known setup prepared for a test.
- **Edge case.** An unusual situation at the boundary of what a program must handle.
- **Symbolic link.** A small file that points to another file, like a signpost.
- **Sparse file.** A file that claims a large size while using almost no disk space.

## Decisions, and what they teach

### Real files, not pretend ones

Tests could have used a simulated disk, a piece of code that only acts like one. It would have been faster. But a file manager's whole job is dealing with the real file system and its many peculiarities, and a simulation only contains the peculiarities its author thought of.

**Lesson:** test against the real thing wherever the real thing's quirks are the point.

### Check the instrument with a different instrument

How do you test the tool that builds test files? Not by asking the tool whether it did its job. Each test reads the result back through the operating system's own low-level calls, a completely separate route. If you weigh something and want to check the scale, you do not use the same scale again.

**Lesson:** verify a result by a path that does not share the mistakes of the path that produced it.

### Go looking for the strange cases

Most files are dull. Bugs live among the rest: the name with an accent that can be stored two different ways, the folder you are not permitted to open, the link that points at nothing. The builder makes every one of these easy to create, so that testing them takes one line instead of an afternoon.

**Lesson:** if the awkward case is hard to set up, it will not be tested. Make it easy.

### A gigabyte that weighs nothing

Testing with a 1 GB file would normally mean writing a gigabyte to disk, slowly, every time. A sparse file reports that size while occupying under a megabyte. The test confirms both facts.

**Lesson:** look for the cheap way to create an expensive condition.

### Leave nothing behind

Every tree is built in a temporary folder and removed afterwards, even one that contains a folder nobody is allowed to open, and even when building fails halfway. A test that leaves debris changes the conditions for the next test, and the experiment is no longer controlled.

**Lesson:** a test should leave the world exactly as it found it.

### Order of construction

The builder works in three passes: contents first, then links, then permissions. Why? You cannot put files into a folder after locking it, and a link may point at a file that appears later in the description.

**Lesson:** when steps depend on each other, the order is part of the design.

## Questions to think about

1. Why would a test that uses your real Desktop folder pass today and fail next week?
2. Name three unusual file names that might confuse a program.
3. The builder's tests avoid using the builder to check itself. Where else in life do we insist on an independent check?

## Where to look next

- `Packages/TestSupport/`
