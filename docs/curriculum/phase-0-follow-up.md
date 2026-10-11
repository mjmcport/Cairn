# Phase 0 follow-up: looking back before going on

- **Commits:** the nine commits named `Phase 0 follow-up ...`, and `Check documents-only changes on Linux`
- **Plan:** `plans/phase-0-follow-up.md`
- **Engineering notes:** `docs/solutions/2026-10-09-checks-that-pass-without-checking.md`, `docs/solutions/2026-10-09-listing-a-symlinked-location.md`, `docs/solutions/2026-10-09-phase-0-follow-up-notes.md`

## You cannot proofread your own writing

Anyone who has written a long letter knows the experience. You read it three times, send it, and the moment it is gone you see the mistake in the first line. You did not miss it through carelessness. You missed it because you were reading what you *meant*, and what you meant was correct.

Science answers this weakness with an institution: peer review. Work is handed to people who did not do it, have no memory of what was intended, and can see only what is actually on the page.

Phase 0 was finished. All twelve steps had been checked by the one who wrote them. Before building anything on top, the whole of it was handed to a panel of independent reviewers, each looking for a different kind of fault. This page is about what they found, and what changed because of it.

## What the review found

The author's own review had found none of the ten problems the panel reported. That single fact is the main lesson of the page. Three of the findings are worth telling.

### The checks that checked nothing

Several of the project's safety checks worked by gathering a list of files and inspecting each. If the project happened to sit in a folder with a space in its name, say `My Projects`, the list was silently chopped into fragments that matched no real file. The check then inspected nothing, found no problems, and reported success.

A second check piped its output through another program, and reported whether *that* program succeeded, not whether the check did.

A third kept its own hand-typed list of packages to inspect. A new package nobody added to the list would be built and shipped and never looked at.

Step 12 had already stumbled on one case of this. The review showed it was a family.

**Lesson:** a check that cannot fail is more dangerous than no check, because its green tick is believed. Every check needs a companion test that breaks the rule on purpose and watches the check object.

### The folder that could not be opened

Cairn refused to open `/tmp`, one of the best-known folders on any Mac. The reason is a curiosity of macOS: `/tmp` is not really a folder. It is a signpost pointing to another folder, and Cairn checked "is this a folder?" before following the signpost.

The first repair suggested did not work, and a quick experiment showed why before any time was wasted on it. The repair that worked uses an older, plainer system call.

**Lesson:** test a proposed fix with a small experiment before building on it. And notice which ordinary cases your tests never happened to visit.

### The window that waited forever

Pressing a key to go "up" when there was nowhere to go cancelled the folder load already in progress, and started nothing in its place. The window sat showing "loading", for good.

**Lesson:** cancelling work is only safe if something is ready to replace it. This bug's relatives reappear in Phase 1.

## The red marks stay

Steps 10 and 11 had been checked on the developer's Mac, passed, and been published. On the shared examiner they failed. The developer's Mac ran one version of macOS and the examiner ran another, and the accessibility audit behaved differently on each. Worse, nobody looked at the examiner's verdict before publishing the next step on top.

It is possible to rewrite a project's history so the two failed commits appear never to have happened. The instruction here was explicit: do not. The history is a laboratory notebook, and the pages with mistakes on them are part of the record.

What changed was the practice:

- After publishing, wait for the examiner's answer. Never build on red.
- Passing on your own machine does not mean it will pass elsewhere.
- From Phase 1, every change is proposed on a side branch and joins the main code only when green.

**Lesson:** do not hide a mistake. Change the process so it cannot easily happen again.

## The price of certainty

Each run on a rented Mac was costing roughly 50 billed minutes of a 2,000-minute monthly allowance. Left alone, the project would have run out of checking partway through each month. Three changes:

- **A newer change cancels the run of the one it replaces.** There is no point finishing an examination of work that has already been superseded.
- **The expensive tests run only where they count:** on proposals about to be merged, and on the main code.
- **Changes to documents alone skip the Mac entirely** and are checked on a cheap Linux machine for about one billed minute.

One more discovery: billing rounds each run *up* to the next whole minute. A weekly job taking six minutes costs about 260 billed minutes a month; at six minutes and one second it costs about 303.

**Lesson:** verification is a budget. Spend it where a failure would hurt most.

## Testing the promise nobody was testing

Cairn promises to run on macOS 15. Nothing had ever run it there. A weekly check on a macOS 15 machine was added, and its very first run found a real bug: on that version, asking for the folder above the top of the disk gives a slightly different answer, and "go up" from the top led to a folder that does not exist.

**Lesson:** a promise you never test is a guess.

## Making a flaky check visible

Step 10 let the accessibility audit retry once when it timed out. Quietly retrying is how a small unreliability grows into a large one unseen. Now every retry is counted and shown in each run's summary, and if there are more than 3 retries across the last 20 full runs, the run fails. The numbers are admitted to be a first guess.

**Lesson:** if you tolerate a fault, count it. Then you will know when tolerating it has stopped being reasonable.

## Questions to think about

1. Why did ten problems survive the author's review and not the panel's? What does that say about reviewing your own work?
2. How would you prove that one of your own checks is capable of failing?
3. What is gained by leaving two failed commits visible in the history? What is lost?
4. If you could afford only ten full checks a month, which changes would you spend them on?

## Where to look next

- `CLAUDE.md`, the section on CI, pushing and branches
- `CONTRIBUTING.md`, the cost table
- `.github/workflows/`
