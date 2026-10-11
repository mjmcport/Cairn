# Phase 0, step 1: the ground rules

- **Commit:** `Phase 0 step 1: repository and governance`
- **Plan:** `plans/phase-0-step-01-repository-governance.md`

## Before the first brick

Imagine a town deciding to build a library. Long before anyone pours concrete, a few quiet things have to be settled. Who owns the land? Who may use the building? What happens if someone finds a crack in a wall? None of this is construction, yet a building that skips it tends to end in an argument.

Software has the same quiet beginning. The first commit of Cairn contains no program at all. It contains the agreements the program will be built on.

## What was added

- **A README.** The front door: what Cairn is (a file manager for the Mac), which Macs it runs on, how to build it, and a promise that it collects no data about you.
- **A licence.** One page that says anyone may use, copy and change the code. Without it, the legal default is that nobody may.
- **Contribution rules.** Every change comes with tests. One commit per step. And the "clean room" rule, explained below.
- **A code of conduct and a security page.** How people treat each other here, and whom to tell, privately, if you find a weakness.
- **A file of settled decisions.** A short list that every working session starts from, so the same questions are not reopened each morning.
- **A script that checks all of the above exist.**

## Words you will meet

- **Repository.** The folder that holds a project and its entire history.
- **Commit.** One saved, labelled change to that history. This curriculum has one page per commit.
- **Licence.** The legal terms under which others may use the code.
- **Open source.** Code whose licence lets anyone read, use and change it.

## Decisions, and what they teach

### The licence comes first

It is tempting to treat the licence as paperwork for later. But every line written before a licence exists sits in a legal fog. Cairn chose MIT, one of the shortest and most permissive, on the first day.

**Lesson:** decide the things that are hard to change before the things that are easy to change.

### The clean room

Other file managers exist, and some publish their code under licences that require anything built from that code to carry the same terms. One is named in the rules: Nimble Commander. If Cairn borrowed even a little of it, Cairn's own licence would be in question. So the rule is absolute: no code from such projects, and none from closed-source apps. Ideas can be learned from; text cannot be copied.

The name comes from hardware companies that once had one team study a competitor's chip and write down only *what it did*, and a second team, who had never seen the chip, build a new one from that description. The second team worked in the "clean room".

**Lesson:** where your code came from matters as much as whether it works.

### A promise is written where it can be checked

"We do not collect telemetry" is an easy sentence to write and an easy one to forget. So a small script reads the README and fails if the sentence has gone missing, along with a handful of other promises. It is a crude instrument. It cannot tell whether the promise is *kept*, only whether it is still *made*. Later steps add checks that look at the code itself.

**Lesson:** a rule that nothing checks will, given time, quietly stop being true.

### Write down what has been decided

Which macOS versions? Which licence? Which kinds of dependency are acceptable? These were answered once and recorded in a single table. The value is not in the answers so much as in not having to ask again.

**Lesson:** a decision that lives only in someone's memory will be made again, differently, by someone else.

## Left open

The repository is private for now, which means GitHub's built-in private reporting of security problems is unavailable. The security page gives a direct contact instead, and says this will change when the project goes public.

## Questions to think about

1. Why might a company refuse to use software that has no licence at all, even if the code is public?
2. The check confirms that a promise is written down. What would it take to check that the promise is kept?
3. Think of a group project you have been part of. Which decisions kept being reopened? Would writing them down have helped?

## Where to look next

- `README.md`, `LICENSE`, `CONTRIBUTING.md`
- `scripts/check-governance.sh`
