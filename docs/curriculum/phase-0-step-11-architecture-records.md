# Phase 0, step 11: a letter to whoever comes next

- **Commit:** `Phase 0 step 11: architecture records`
- **Plan:** `plans/phase-0-step-11-architecture-records.md`
- **Engineering note:** `docs/solutions/2026-10-09-architecture-records-notes.md`

## The fence in the field

There is an old piece of advice about a traveller who finds a fence across a road, sees no purpose in it, and wants it removed. The reply is: go away and find out why it was put there. Then you may take it down.

Code is full of such fences. Why is this written in one technology and not the newer one? Why can this part not talk to that part? The code shows *what* was decided with perfect accuracy and says nothing at all about *why*. The reasons live in the heads of the people who were there, and memory is a poor archive: sleep researchers will tell you that what is not consolidated soon after the event is largely gone. This step writes the reasons down while they are still fresh.

## What was added

- **`ARCHITECTURE.md`.** A map of the whole program: the layers, what each part owns, how a folder travels from the disk to the screen, and, for each rule, what enforces it.
- **Six decision records.** One short page each, for the six choices that shape everything else.

## Words you will meet

- **Architecture.** The large-scale shape of a program: its parts and how they relate.
- **Decision record.** A short note capturing one significant choice and the reasoning behind it.
- **Trade-off.** What you give up to get what you chose.

## The six decisions

1. **Use AppKit for the interface.** Apple's older, more detailed toolkit, chosen over its newer one because a file manager is mostly very long lists that must stay responsive with 100,000 rows and behave the way Finder does.
2. **Generate the project file** from a readable description (step 2).
3. **MIT licence with clean-room rules** (step 1).
4. **Support macOS 15 and later.** Newer system features can be used freely, at the cost of leaving older Macs out.
5. **Distribute outside the App Store.** The store requires apps to be confined in ways that would cripple a tool whose purpose is to reach every file.
6. **No telemetry** (steps 1 and 6).

## Decisions, and what they teach

### Record the roads not taken

Every record has the same parts: the situation, the decision, the consequences, and the alternatives that were considered and set aside. That last part is the valuable one. A future reader who thinks "why did they not just use the newer toolkit?" finds that someone already asked, and can see whether the answer still holds.

**Lesson:** the options you rejected, and why, are worth as much as the option you chose.

### Write down the cost as well

A record that lists only benefits is an advertisement. These state what each choice makes harder: supporting only recent macOS shuts out some users; leaving the App Store means handling updates and trust yourself.

**Lesson:** every real decision has a price. Naming it is what makes the record believable.

### Write it while you still remember

This step came near the end of Phase 0, when the reasons were days old. A year later the same pages would have been reconstructed from guesswork, and would have been tidier and less true.

**Lesson:** the best time to explain a decision is just after making it.

### Decisions can be revisited, knowingly

Each record carries a status and a date. The usual practice with records like these is that an overturned decision is not deleted: a new record explains what changed, and the old one stays, the way a laboratory notebook keeps the crossed-out line.

**Lesson:** changing your mind is fine. Erasing the fact that you once thought otherwise is not.

### Keep the map honest

A script confirms that the map and all six records exist, that each has its decision and consequences, and that the map links to every one. It is the same idea as in step 1: documents rot quietly unless something notices.

**Lesson:** documentation needs maintenance like anything else, and a little automation helps it get some.

## Questions to think about

1. Think of a rule at school or work that nobody can explain. What happens to such rules over time?
2. Why might a team be tempted to leave the downsides out of a decision record?
3. Pick a decision you made this year. Could you still list the alternatives you considered?

## Where to look next

- `ARCHITECTURE.md`
- `docs/adr/`, the six records
