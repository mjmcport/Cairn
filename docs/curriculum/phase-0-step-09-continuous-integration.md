# Phase 0, step 9: an examiner who never tires

- **Commit:** `Phase 0 step 9: continuous integration`
- **Plan:** `plans/phase-0-step-09-continuous-integration.md`
- **Engineering note:** `docs/solutions/2026-10-09-ci-notes.md`

## The second laboratory

A result in science is not believed because one laboratory reports it. It is believed when a different laboratory, with different equipment and no stake in the outcome, repeats the experiment and gets the same answer.

So far, every check in Cairn had run in one place: the developer's own Mac. That Mac has the right tools, yesterday's leftover files, and an owner who hopes the tests pass. This step sets up the second laboratory: a fresh, rented computer that knows nothing, wants nothing, and runs every check on every change.

## What was added

- **A workflow.** A recipe that tells GitHub: whenever the code changes, start a clean Mac, fetch the code, and run the format check, the build, the unit tests, the tests that drive the real app, and the speed tests.
- **A results trail.** When a run fails, the evidence is kept so someone can see why.
- **Two trial runs,** one meant to pass and one meant to fail.

## Words you will meet

- **Continuous integration (CI).** Automatically building and testing every change on a neutral machine.
- **Runner.** The rented computer that does it.
- **Pull request.** A proposed change, set out for checking and discussion before it joins the main code.
- **Main.** The official, current version of the code.
- **Green** and **red.** Shorthand for a run that passed and one that failed.

## Decisions, and what they teach

### One definition of "passing"

The runner does not have its own list of checks. It types the same commands a developer types: `make lint`, `make test`. If the two could differ, the developer would learn to distrust one of them.

**Lesson:** there should be exactly one way to answer "does it work?", and everyone, human or machine, should use it.

### Break it on purpose

After the first run passed, a second change was submitted with a test deliberately made to fail. The point was to see the system say no. It did: the run turned red and the later stages were skipped. An inspector who has only ever approved things has not yet been shown to inspect.

**Lesson:** before trusting any safeguard, watch it catch something.

### Finding the edge of what is possible

The plan wanted more: a failing change should be *blocked* from joining the main code. GitHub offers that lock, but not for a private project on the free plan. So the failing change showed red, and could still have been merged by anyone who ignored it.

The step did not pretend otherwise. It left that item unticked, marked as "half met", and added a one-line script that applies the lock the day the project's circumstances change.

**Lesson:** when you cannot do something, say so precisely, and make the future fix as small as possible.

### A slower machine is not a slower program

On its first run, the runner reported that five speed measurements had got dramatically worse. Nothing had changed in the code. The rented machine was simply slower than the Mac that recorded the baseline. The comparison tool was changed to judge only measurements taken on the same model of Mac, and to merely display the others.

**Lesson:** an alarm that goes off for the wrong reason teaches people to ignore alarms. Fix it immediately.

### Checking costs money

A run took about five minutes. GitHub charges Mac time at ten times the ordinary rate, so each run consumed about 50 of the 2,000 minutes a free account gets per month. Forty runs and the month's allowance is gone. This small fact shaped a surprising amount of what came after, including a whole section of the follow-up.

**Lesson:** verification has a price. Know what it is before the bill arrives.

### Try the recipe on a branch

The workflow was first tried on a side copy of the code with a draft pull request, so that a mistake in the recipe itself could never leave the main code with a broken examiner.

**Lesson:** test the testing machinery somewhere it cannot do harm.

## Questions to think about

1. Why is a check on a clean machine more convincing than the same check on the developer's own?
2. A red result that can be ignored is still useful. In what way? And what is missing?
3. Suppose each check cost you a pound. How would that change how often, and how carefully, you asked for one?

## Where to look next

- `.github/workflows/ci.yml`
- `CONTRIBUTING.md`, for what runs cost today
