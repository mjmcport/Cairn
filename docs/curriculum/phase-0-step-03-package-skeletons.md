# Phase 0, step 3: drawing the rooms before building them

- **Commit:** `Phase 0 step 3: package skeletons`
- **Plan:** `plans/phase-0-step-03-package-skeletons.md`

## Why bodies have organs

A living body could, in principle, be one undivided mass of cells that all do a bit of everything. None is. Hearts pump, lungs exchange gases, and each can be examined, understood and even replaced without redesigning the others. The boundaries between them are what make something so complicated possible to study at all.

Large programs survive the same way. This step divides Cairn into five parts before a single feature exists, and, more importantly, decides which parts are allowed to know about which.

## What was added

Five packages, each a small self-contained library with its own tests:

| Package | Its one job |
| --- | --- |
| FileSystemCore | Reading what is on the disk |
| FileMetadata | The details about a file: dates, tags and the like |
| FileOperations | Changing things: copy, move, rename, delete |
| BrowserUI | Everything you see and click |
| TestSupport | Helpers used only by tests |

Each one starts as a stub: the outline of what it will do, with almost nothing inside.

## Words you will meet

- **Module** or **package.** A part of a program with a clear edge and a clear purpose.
- **Dependency.** When one part needs another in order to work.
- **Interface.** What a part offers to the others, as opposed to how it works inside.
- **Stub.** A placeholder with the right shape and no real contents yet.

## Decisions, and what they teach

### The arrows point one way

The part that draws windows may use the parts that read the disk. The parts that read the disk may never use, or even mention, the part that draws windows. Knowledge flows in one direction only.

Why does that matter? Because the disk-reading code can then be tested without opening a window, reused in a different kind of program, and understood without thinking about buttons. If the arrows pointed both ways, changing a button could break file copying, and nobody would know why.

**Lesson:** decide which parts may know about which. A program where everything knows about everything cannot be changed safely.

### A rule the tools cannot enforce gets its own check

The language has no way to say "this package may not use the window-drawing system". So a small script reads the core packages and fails if any of them does. And because a check can be wrong too, the check itself is tested: it is shown a deliberately rule-breaking example and must object.

**Lesson:** when a rule matters and nothing enforces it, write the enforcer. Then test the enforcer.

### Every part gets a test from the first day

Each package was born with at least one passing test, even when there was almost nothing to test. That sounds ceremonial. What it buys is that the plumbing for testing is already working when the first real code arrives, so there is never a moment when adding a test feels like extra setup.

**Lesson:** make the good habit the easy path before you need it.

### Outline first

The stubs name things, a file item, a file operation, a browser view, without implementing them. Drawing the floor plan first means later steps argue about what goes in a room, and not about where the walls are.

**Lesson:** a rough outline you can see is easier to correct than a detailed plan you cannot.

## Questions to think about

1. Suppose the disk-reading code needed to show an error to the user. With one-way arrows, it cannot open a dialog itself. How might it get the message across?
2. What everyday system has parts that deliberately know little about each other? (Consider a wall socket and the lamp plugged into it.)
3. The boundary check is itself tested. Why is an untested check risky?

## Where to look next

- `Packages/`, one folder per package
- `scripts/check-appkit-boundary.sh`
- `ARCHITECTURE.md`, written in step 11, draws the full picture
