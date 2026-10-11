# Phase 0, step 12: something you can hold

- **Commit:** `Phase 0 step 12: build artifact`
- **Plan:** `plans/phase-0-step-12-build-artifact.md`
- **Engineering note:** `docs/solutions/2026-10-09-build-artifact-notes.md`

## The loaf at the end of the line

A bakery's recipes, ovens and inspections all exist for one purpose: a loaf that someone can pick up and take home. Until this step, Cairn was a project that could be built only by someone with the full set of tools and the knowledge to use them. The last step of Phase 0 puts a loaf on the shelf. Every accepted change now produces a packaged copy of the app that anyone on the project can download and run.

## What was added

- **`make package`.** Builds the finished form of the app and wraps it in a single zip file.
- **A name that tells the truth.** The file name carries the version, the exact commit it was built from, and the word `unsigned`.
- **A package inspection.** A script unzips the result and checks it, ending with the most basic question of all: does it start?
- **Automatic packaging** on every change to the main code, kept for 30 days.

## Words you will meet

- **Artifact.** A finished, packaged output of a build.
- **Release.** A version meant for the public.
- **Code signing.** A cryptographic seal that says who made an app and that it has not been altered since.
- **Notarization.** Apple scanning an app and vouching that it found nothing malicious.
- **Gatekeeper.** The part of macOS that checks those seals before letting an app run.

## Decisions, and what they teach

### Stamp every build with its origin

Because the file name includes the commit, anyone holding a build can say exactly which version of the code produced it. When a bug appears in one build and not in the one before, the search is confined to the handful of changes between them.

**Lesson:** if you can always trace a thing back to where it came from, half of every investigation is already done.

### Label it honestly

Proper signing requires a paid developer identity, and was scheduled for Phase 1. Without it, macOS will refuse to open the app on another person's Mac unless they deliberately override the warning. The package could have been given a neutral name. It was given the word `unsigned`, so that nobody could mistake a test build for something ready to hand to the public.

(A detail for the curious: the build does carry a minimal local seal, because modern Macs will not run a program with no seal at all. "Unsigned" here means "not vouched for by an identified developer".)

**Lesson:** name things for what they are, especially when what they are is unfinished.

### Inspect the package, not just the contents

The app had been tested many times. The zip had not. Wrapping can go wrong in its own ways: a missing piece, a damaged seal, a build for the wrong kind of processor. So the inspection opens the actual zip and checks what a user would receive, then launches it and confirms it is still running three seconds later.

**Lesson:** test the thing you will hand over, in the form you will hand it over.

### A test that could not fail

Here the project caught itself in a mistake worth remembering. Some tests for the checks worked by copying the project's files to a temporary place and breaking something on purpose, expecting the check to complain. But in one situation, the list of files to copy came back empty. The tests then ran against an empty folder. Every "this should fail" case duly failed, for the wrong reason: there was nothing there at all. Everything looked fine.

It was found by hand in this step. It was the first sighting of a pattern that an independent review would soon find three more times.

**Lesson:** a check that passes because it looked at nothing is worse than no check, because you believe it. The follow-up page takes this up in earnest.

### Spend where it counts

Packaging runs only when a change joins the main code, not on every proposal, because each run on a rented Mac costs money (step 9).

**Lesson:** not every check needs to run every time.

## The end of Phase 0: an honest scorecard

Phase 0 had five conditions for being finished. The plan grades them:

| Condition | Result |
| --- | --- |
| A clean copy builds and passes its tests with one command | Met |
| The examiner is green, and blocks a failing change | Half met: it turns red, but cannot block (step 9) |
| The app lists a folder and enters subfolders, with an end-to-end test | Met |
| Speed baselines are recorded for 10,000 and 100,000 files | Met |
| The six decision records exist | Met |

"Half met" is the most important phrase on this page. It would have been easy to round it up.

## Questions to think about

1. Why include the commit in a file name when a version number is already there?
2. How could a test "pass" while checking an empty folder? How might you make that impossible?
3. Why is "half met" more useful to the next person than "met"?

## Where to look next

- `scripts/check-package.sh`
- The next page, the Phase 0 follow-up, where an outside review looks at all twelve steps
