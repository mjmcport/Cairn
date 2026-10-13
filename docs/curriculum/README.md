# The Cairn curriculum

Cairn is a file manager for the Mac. It is also, on purpose, a worked example: every step of building it has a page here that explains what was done, why, and what is worth learning from it.

These pages are for people who are new to software, or who work near it without writing it. You do not need to read code to follow them. Each one begins with something familiar, a recipe, a shop with one cashier, a trail of pebbles, and uses it to explain a real engineering decision made in this project.

Read them in order and you will have watched a program go from an empty folder to a working app, including the mistakes. The mistakes are some of the best pages.

## Phase 0: foundations

Twelve steps that produce almost nothing you can see, and everything the visible parts stand on.

| Step | Page | The idea |
| --- | --- | --- |
| 1 | [The ground rules](phase-0-step-01-repository-and-governance.md) | Settle the hard-to-change things first; a promise needs a check |
| 2 | [One command builds everything](phase-0-step-02-toolchain-and-project-spec.md) | Make the kitchen part of the recipe |
| 3 | [Drawing the rooms before building them](phase-0-step-03-package-skeletons.md) | Divide a program into parts, and decide which may know about which |
| 4 | [A laboratory of files](phase-0-step-04-fixture-builder.md) | Controlled experiments need controlled conditions |
| 5 | [The walking skeleton](phase-0-step-05-walking-skeleton.md) | Connect everything thinly before building anything thickly |
| 6 | [A tripwire and a flight recorder](phase-0-step-06-main-thread-guard-and-diagnostics.md) | Turn a rule in a document into a rule in the code |
| 7 | [A number instead of a feeling](phase-0-step-07-performance-baseline.md) | Measure before you decide what to fix |
| 8 | [Ending the argument about commas](phase-0-step-08-formatting.md) | Automate the decisions that do not matter |
| 9 | [An examiner who never tires](phase-0-step-09-continuous-integration.md) | A result counts when a neutral machine can repeat it |
| 10 | [Built for everyone, from the start](phase-0-step-10-accessibility-convention.md) | Make the right way the only way |
| 11 | [A letter to whoever comes next](phase-0-step-11-architecture-records.md) | Write down why, while you still remember |
| 12 | [Something you can hold](phase-0-step-12-build-artifact.md) | Test the thing you will hand over; grade yourself honestly |
| Follow-up | [Looking back before going on](phase-0-follow-up.md) | You cannot proofread your own writing |

## Phase 1: a file manager you could use

| Step | Page | The idea |
| --- | --- | --- |
| 1 | [Remembering the way back](phase-1-step-01-navigation-history.md) | Checking and then acting leaves a gap; close it |
| 2 | [Several places at once](phase-1-step-02-tabs.md) | Keep the original instead of saving and restoring; "which window?" |
| 3 | [The first rows, at once](phase-1-step-03-fast-first-rows.md) | How a wait feels; asking "is this still wanted?" after every pause |
| 4 | [A list that keeps up](phase-1-step-04-live-updates.md) | A new source of change must fit the old rules; make the other system share ownership |
| 5 | [A drawer without leaving the room](phase-1-step-05-list-view.md) | Name a place so it cannot be spelled two ways; a test that measures time measures its neighbours; check the old version first |
| 6 | [A photograph album](phase-1-step-06-icon-view.md) | Show something true at once and improve it; measure every fact you read for every item; make the harm impossible two ways |

## Ideas that keep coming back

A few lessons appear in step after step. Watching one recur is the best way to learn it.

- **A check must be able to fail.** Steps 1, 3, 6, 9 and 12 of Phase 0, and the follow-up.
- **Keep slow work away from the interface.** Phase 0 steps 5 and 6; Phase 1 steps 3, 4, 5 and 6.
- **A late answer to an old question.** Phase 0 step 5; Phase 1 steps 1, 3, 4 and 5.
- **Measure, and record the conditions.** Phase 0 steps 7 and 9; Phase 1 steps 3, 4, 5 and 6.
- **Say plainly what is not done.** Nearly every page.
- **It passed here, not there.** The follow-up; Phase 1 steps 1 and 2.

## How a page is written

For whoever writes the next one.

- **Voice.** Write the way a good science writer explains the cosmos or the sleeping brain to a curious reader with no degree in the subject: open with something from ordinary life, build the idea from it, and trust the reader's intelligence. Never talk down, and never hide behind jargon. A term is explained in a sentence the first time it appears.
- **Truth.** Every fact comes from the step's plan, its engineering notes or its measurements. An analogy may simplify; it may not say something false. Mistakes and unfinished work are told as they happened.
- **Shape.** A title that names the idea; the commit and where its plan lives; an opening picture; what was added; words you will meet; the decisions, each ending with a one-line lesson; what review found or what was left open, when there is something to say; questions to think about; where to look next.

The engineering record is elsewhere: plans in `plans/`, notes for the people and agents building Cairn in `docs/solutions/`, and architecture decisions in `docs/adr/`.
