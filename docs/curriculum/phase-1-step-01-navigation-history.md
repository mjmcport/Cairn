# Phase 1, step 1: remembering the way back

- **Commit:** `Phase 1 step 1: navigation history`
- **Plan:** `plans/phase-1a-step-01-navigation-history.md`
- **Engineering notes:** `docs/solutions/2026-10-09-navigation-history-notes.md`, `docs/solutions/2026-10-10-check-then-act-across-a-task-boundary.md`

## Breadcrumbs

Anyone walking into an unfamiliar forest faces an old problem: going in is easy, and coming out requires having paid attention. The fairy-tale solution is a trail of pebbles. A web browser's Back button is the same idea, and we lean on it so heavily that an app without one feels like a room with no door behind you.

Until this step Cairn could go into a folder and up to the folder above. It could not go *back*. That is a different thing: "up" is about where folders sit on the disk, and "back" is about where *you* have been. This step gives Cairn a memory of its own path.

## What was added

- **Back and Forward,** from the keyboard, the menu, and two new toolbar buttons.
- **A remembered selection.** Go back, and the file you had highlighted is highlighted again. Go up, and the folder you just left is selected, so you can see where you came from.
- **Buttons that know when they are useful.** Back is greyed out when there is nowhere to go back to.

## Words you will meet

- **History.** The ordered list of places visited, with a marker for where you are now.
- **State.** Everything a program is remembering at a given moment.
- **Toolbar.** The strip of buttons along the top of a window.
- **Race condition.** A bug whose appearance depends on the exact order in which two things happen.

## Decisions, and what they teach

### The memory lives apart from the window

The list of visited places is a small, plain piece of logic. Nothing in it knows about windows or buttons. It can therefore be tested in a fraction of a second with no app running: go here, go there, go back; where am I? The rules of history (for instance, that visiting somewhere new after going back discards the "forward" trail) are settled in one place.

**Lesson:** pull the pure logic out from the interface. Logic that stands alone is easy to test and easy to trust.

### When is a folder the same folder?

This sounds like a question for philosophers. It caused real bugs.

The same folder can be written `/Users/sam/Documents` or `/Users/sam/Documents/`, with or without the final slash. A computer comparing the two letter by letter says they differ. So "select the folder I just left" could not find the folder in its own parent's list. And, as in the follow-up, some folders are signposts, so the place you asked to open and the place its contents report coming from are spelled differently again.

The answer was to write one small function that reduces any spelling to a standard form, and use it everywhere.

**Lesson:** deciding what counts as "the same" is a design decision, and usually a harder one than it looks. Make it once, in one place.

### The double tap

The most instructive bug in this step. Press Back twice, quickly, when there is only one place to go back to.

The first press checked "is there somewhere to go back to?" and the answer was yes, so it scheduled the move to happen a moment later. The second press arrived before that moment. It asked the same question, got the same yes, because nothing had moved yet, cancelled the first, and then found there was nothing left to do. The window was left loading, forever.

Think of two people sharing a kitchen. Each looks in the fridge, sees no milk, and resolves to buy some on the way home. Each acted sensibly on what they saw. There are now two cartons, because the looking and the buying were separated by time, and the world changed in between.

The repair: make the check and the move a single, uninterruptible act. Only the slow part, reading the folder, is left for later.

**Lesson:** when you check something and then act on it, ask what could change in the gap. If the answer is "anything", close the gap.

### One source of truth for "can I?"

The Back menu item and the Back toolbar button could each have had their own logic for when to be greyed out, and then one day they would disagree. Both ask the same single question of the same single object.

**Lesson:** two copies of a rule will eventually become two different rules.

### Three versions of macOS, three behaviours

A test that passed on the developer's Mac and on the main examiner failed on the macOS 15 machine added in the follow-up. The same request to the system, "which window does this button belong to?", was answered on newer versions and met with silence on the older one. The code now asks in a way that works on all three.

That macOS 15 check was brand new. It had already caught two real bugs: this one, and the "go up from the top of the disk" bug in the follow-up.

**Lesson:** the platform beneath you is not one fixed thing. Test on the oldest version you promise to support, not only the newest.

### Counting the cost of a test

Each end-to-end test launches the real app, and each launch adds billed time on the rented Mac. So new checks were added to existing tests where they fitted, instead of each getting a launch of its own.

**Lesson:** tests have running costs. It is fair to design them with thrift.

## What the review found

The double-tap bug was not caught by the first round of tests. It was found in review, by reading the code and asking what happens when two commands arrive almost together. The tests written afterwards send each command twice with no pause, and each was seen to fail against the old code first.

**Lesson:** ordinary testing asks "does it work when used as intended?". Someone also has to ask "what if two things happen at almost the same time?".

## Questions to think about

1. In a web browser, what happens to your "forward" pages when you go back and then click a new link? Why is that the right rule?
2. Find an everyday example, like the milk, where checking and acting are separated and something changes between them.
3. Why might two spellings of the same address be a problem for a program and not for a postal worker?

## Where to look next

- `Packages/BrowserUI/Sources/BrowserUI/BrowserHistory.swift`
- `Packages/BrowserUI/Sources/BrowserUI/BrowserToolbar.swift`
- `UITests/HistoryTests.swift`
