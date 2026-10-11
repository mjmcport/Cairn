# Phase 0, step 6: a tripwire and a flight recorder

- **Commit:** `Phase 0 step 6: main-thread guard and diagnostics`
- **Plan:** `plans/phase-0-step-06-main-thread-guard-and-diagnostics.md`
- **Engineering note:** `docs/solutions/2026-10-09-main-thread-guard-notes.md`

## The one cashier

Picture a small shop with a single cashier. Everything the customers experience, every greeting and every sale, passes through that one person. Now suppose that in the middle of serving you, the cashier walks to the stockroom to count boxes. The queue stops. Nobody is served until the counting is done.

Every app has such a cashier. It is called the main thread, and it is the only part of the program allowed to draw the window and respond to your clicks. When it wanders off to do something slow, the app freezes. Reading from a disk is exactly the kind of errand that is usually quick and now and then takes many seconds.

Step 5 kept the cashier at the counter by being careful. This step stops relying on care.

## What was added

- **A guard.** One line, placed at the start of every piece of code that touches the disk. If that code is ever run by the main thread, the guard records a fault and, in a developer's build, stops the program on the spot.
- **Organized logging.** Six labelled channels (file system, interface, and so on) for the app's running notes about what it is doing.
- **A local flight recorder.** When macOS reports that the app hung or crashed, the report is saved in a folder on your own Mac. The newest fifty are kept.
- **Two more checks,** described below.

## Words you will meet

- **Thread.** One line of work inside a program. A program can have several going at once.
- **Main thread.** The one that runs the interface.
- **Log.** A program's diary, read by developers after something goes wrong.
- **Telemetry.** Data about your use of an app, sent back to its makers. Cairn sends none.

## Decisions, and what they teach

### A rule in a document becomes a rule in the code

"Never read the disk on the main thread" was already written in the project's rules. But a sentence in a document does nothing at the moment a tired programmer makes the mistake. The guard does. It is the difference between a sign saying "do not enter" and a locked door.

**Lesson:** where you can, make the mistake impossible to miss, instead of asking people to remember not to make it.

### Fail loudly in the workshop, gently in the field

On a developer's machine, the guard halts the program immediately, so the mistake is found within seconds of being written. In the version real people use, it only records the fault and carries on. A frozen moment is bad; a crash that loses someone's work is worse.

**Lesson:** the same problem can deserve different reactions depending on who is watching.

### Prove the alarm rings

How do you test a guard whose job is to stop the program? If the test triggers it, the test dies too. So the guard was built with a replaceable reaction: a test can swap "stop the program" for "make a note", trip the guard on purpose, and confirm the note appears. And the replacement applies only to that one test, so other tests running at the same moment are undisturbed.

**Lesson:** a safety device you have never seen go off is a hope. Design it so it can be tested.

### Diagnostics that stay home

The app needs some way to learn about its own hangs. The common answer is to send reports to the developer's servers. Cairn promised in step 1 not to do that, so the reports are kept in a folder on the user's Mac, where the user can read them and choose whether to share one.

To hold that line, a check scans the code and fails if any networking code appears at all.

**Lesson:** privacy is a set of design decisions, each of which costs something. Here the cost is convenience for the developer.

### Know what your check cannot see

A second check confirms that any file touching the disk contains the guard. The plan is frank about its limit: it looks at whole files, so it would catch a new file with no guard, and miss a second, unguarded piece of code added to a file that already has one.

**Lesson:** every check has blind spots. Writing them down stops people trusting it for more than it does.

## Questions to think about

1. Why is it more useful for a developer's build to stop at once than to log a quiet warning?
2. What does a developer give up by keeping crash reports only on the user's computer?
3. Think of a safety device in daily life that is routinely tested. What would it mean if it never were?

## Where to look next

- `Packages/FileSystemCore/Sources/FileSystemCore/`: `MainThreadGuard`, `Log`, `LocalDiagnosticsStore`
- `scripts/check-main-thread-guard.sh`, `scripts/check-no-network.sh`
