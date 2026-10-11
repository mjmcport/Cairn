# Phase 0, step 8: ending the argument about commas

- **Commit:** `Phase 0 step 8: formatting`
- **Plan:** `plans/phase-0-step-08-formatting.md`
- **Engineering note:** `docs/solutions/2026-10-09-formatting-notes.md`

## The house style

Open any good newspaper and every article follows the same small conventions: how dates are written, when numbers are spelled out, where the commas go. No reporter chose them. They come from a house style, and their purpose is to disappear. When the surface is uniform, the reader's attention goes to what is being said.

Programmers have their own version of the comma question. Two spaces or four? Where does the brace go? How long may a line be? These have no right answers, which is precisely why people can argue about them without end. This short step ends the argument by handing it to a machine.

## What was added

- **A style file** stating the choices: two-space indentation, lines of at most 100 characters, and a few rules about risky shortcuts.
- **`make format`,** which rewrites every source file to match.
- **`make lint`,** which checks, changes nothing, and fails if anything is out of place.
- **A commit hook:** a small program that runs automatically each time a developer saves a change to the history, and refuses if the code is not formatted.

## Words you will meet

- **Formatter.** A tool that rewrites code into a standard layout without changing what it does.
- **Linter.** A tool that inspects code and reports problems.
- **Code review.** One person reading another's change before it is accepted.
- **Hook.** A program that runs automatically at a certain moment, such as just before a commit.

## Decisions, and what they teach

### Give the unanswerable questions to a machine

Human attention is the scarcest thing on any project. A reviewer who spends it noticing a misplaced space has less left for noticing that the code deletes the wrong file. Once a tool owns the layout, people are free to discuss what the code does.

**Lesson:** automate the decisions that do not matter, so that people can spend themselves on the ones that do.

### Use the tool you already have

The formatter chosen is the one that ships with Xcode. There is nothing extra to install, and because step 2 pinned the Xcode version, everyone automatically has the same formatter. Two versions of a formatter can disagree, and then the argument returns in a new costume.

**Lesson:** fewer tools to install means fewer ways for two machines to differ.

### Catch it at the cheapest moment

The hook stops an unformatted change within a second, on the developer's own machine, before anyone else sees it. The same check runs again later on a shared server (step 9), as the gate that cannot be bypassed. The first is for speed; the second is for certainty.

**Lesson:** the earlier a mistake is caught, the less it costs. Put a quick check close to the person and a firm one further out.

### Check what is being saved, not what is on the desk

A subtle point. When you make a commit, what gets saved is a snapshot you prepared a moment ago, which can differ from the file currently open in your editor. An early version of such a hook might check the file on disk, be satisfied, and let an unformatted snapshot through. This hook examines the snapshot itself, and a test proves it by fixing the file on disk while leaving the snapshot broken.

**Lesson:** make sure a check is looking at the thing that will actually ship.

### Adopt a style while the project is small

Applying a formatter to a large, old project rewrites thousands of lines at once and buries the history of who changed what. Cairn did it when there was almost nothing to rewrite.

**Lesson:** conventions are cheapest on the first day and grow dearer every day after.

## Questions to think about

1. Why might a team argue longer about spacing than about how a feature should work?
2. The hook can be bypassed by a determined developer; the server check cannot. Why keep both?
3. Where else do agreed conventions free people to think about more important things? (Consider which side of the road we drive on.)

## Where to look next

- `.swift-format`
- `.githooks/pre-commit`
