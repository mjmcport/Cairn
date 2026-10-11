# Phase 0, step 10: built for everyone, from the start

- **Commit:** `Phase 0 step 10: accessibility convention`
- **Plan:** `plans/phase-0-step-10-accessibility-convention.md`
- **Engineering note:** `docs/solutions/2026-10-09-accessibility-notes.md`

## The ramp in the blueprint

A building designed with a ramp has a ramp that belongs: it meets the door at the right height and nobody thinks about it. A building that gets its ramp ten years later has one bolted to the side, steep and awkward, reached by a detour past the bins. The cost and the result both depend almost entirely on *when* the question was asked.

Many people use a Mac without seeing the screen. A program called VoiceOver reads aloud whatever the pointer or keyboard is on. Others cannot use a mouse and do everything from the keyboard. For these users, an app with a button that has no name is an app with a door that has no handle. This step puts the ramp in the blueprint.

## What was added

- **A catalog** listing every control in the app with two things: a spoken name for people and a stable code name for tests.
- **One way to create a control,** which sets both names together. There is no way to set one and forget the other.
- **A check** that fails if any code sets these names by another route.
- **The system's own accessibility audit,** run automatically on three screens: a full folder, an empty folder, and a folder that could not be read.
- **A keyboard-only test:** open a folder and leave it without touching the mouse.

## Words you will meet

- **Accessibility.** Making software usable by people with a wide range of abilities.
- **Screen reader.** A program that speaks what is on screen. VoiceOver is the Mac's.
- **Label.** The name a screen reader speaks for a control.
- **Contrast.** How strongly text stands out from its background.
- **Audit.** An automatic inspection for known accessibility problems.

## Decisions, and what they teach

### Make the right way the only way

The usual approach is to remind developers to add a label to each new control. Reminders fail on busy days. Here, creating a control *is* naming it: the same single action does both, and a script objects to any other route.

**Lesson:** do not rely on people remembering. Build the path so that the correct thing happens by default.

### One list, used by both the app and its tests

The tests find buttons through the very same catalog the app uses to name them. If someone renames a control, the app and its tests change together. Two separate lists would drift apart, and one day a test would be faithfully checking a button that no longer exists.

**Lesson:** when two things must agree, give them one source to read from.

### What the audit found

The automatic inspection ran and reported four things. They did not all get the same answer, and that is the instructive part.

- *The "This folder is empty" message was close to failing contrast.* Fixed: it now uses a stronger text colour.
- *A dash shown for a missing size is not a word.* Fixed: VoiceOver now says "No size" where the screen shows a dash.
- *A cell showing `alpha.txt` has a label that is "not human-readable".* Not changed. A file's name is the user's own data, and reading it aloud is exactly right. The audit is told to skip that one complaint, for file-name cells only.
- *Something in the Touch Bar has no description.* Not changed. That element belongs to the system, not to Cairn.

**Lesson:** a tool's report is evidence to weigh, not a list of orders. Fix what is real, and when you decline, write down why, as narrowly as you can.

### The audit is necessary, and not sufficient

An automatic audit can tell that a button has a name. It cannot tell whether the name makes sense, or whether using the app by ear is pleasant or maddening. That takes a person, and the project's later pages record honestly when that human check has not yet been done.

**Lesson:** automated checks set a floor. They do not tell you how good the experience is.

### An unreliable check, handled in the open

About one run in ten, the audit simply ran out of time and reported nothing. The step did the pragmatic thing: announce the timeout, try once more, and fail if it happens twice. It also wrote the problem down as a known issue.

The audit had one more surprise in store. It passed on the developer's Mac and failed on the shared examiner, which runs a different version of macOS, and so this commit and the next sit red in the project's history. The follow-up page tells that story.

**Lesson:** a retry can be a reasonable patch for a flaky check, provided it is visible. A hidden retry is a way of not knowing how bad things are.

## Questions to think about

1. Why is it so much cheaper to design for accessibility at the start than to add it later?
2. The team declined two of the audit's four findings. What makes that defensible, and what would make it an excuse?
3. Close your eyes and imagine using your favourite app by sound alone. Which controls would need a name?

## Where to look next

- `Packages/BrowserUI/Sources/BrowserUI/Accessibility.swift`
- `UITests/AccessibilityTests.swift`
- `scripts/check-accessibility.sh`
