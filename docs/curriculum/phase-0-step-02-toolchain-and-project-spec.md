# Phase 0, step 2: one command builds everything

- **Commit:** `Phase 0 step 2: toolchain and project spec`
- **Plan:** `plans/phase-0-step-02-toolchain-and-project-spec.md`
- **Engineering note:** `docs/solutions/2026-10-09-toolchain-setup-on-a-fresh-mac.md`

## The recipe problem

Two cooks follow the same recipe and produce two different loaves. One oven runs hot. One bag of flour is a different brand. Neither cook did anything wrong, and yet the bread disagrees.

Programmers know this as five tired words: "it works on my machine". Software is turned from text into a running program by a set of tools, and if two people have slightly different tools, they can get slightly different programs, or one that builds and one that does not. This step is about making the kitchen part of the recipe.

## What was added

- **A pinned toolchain.** One small file names the exact version of Xcode, Apple's building tool, that Cairn expects.
- **A project description.** A short, readable file that states what the app is: its name, the oldest macOS it supports, the kind of Mac it runs on, and how strict the compiler should be.
- **A tiny app.** One empty window and a menu bar. It does nothing yet, on purpose.
- **A Makefile.** A list of named tasks, so that typing `make` sets up, builds and tests the whole project.
- **A setup script** that, when something is missing, says what and gives the exact command to fix it.

## Words you will meet

- **Build.** Turning source code, which people write, into a program the computer can run.
- **Toolchain.** The set of tools that does the building.
- **Compiler.** The main tool in that set. It also acts as a tireless proofreader.
- **Generated file.** A file a tool writes for you from a simpler description.

## Decisions, and what they teach

### Keep the description, not the machine-written file

Xcode stores a project in a large, tangled file that people are not meant to read. When two people change it at once, untangling the result is miserable. So Cairn keeps a short description that a person can read, and a tool regenerates the tangled file from it whenever needed. The tangled file is never saved in the repository.

**Lesson:** store the thing a person can understand, and let a machine produce the rest.

### Prove it on a clean copy

How do you know the recipe is complete, and that you are not relying on something left on the counter from yesterday? You hand it to someone in an empty kitchen. A test here copies the project to a fresh folder, with nothing left over from earlier work, and builds it from scratch.

**Lesson:** the only proof that setup instructions work is following them somewhere they have never been followed.

### Ask the compiler to be as strict as possible

Compilers offer warnings: "this looks suspicious, but I will allow it". Cairn treats every warning as an error, and switches on the strictest checking of one notoriously slippery area, code that does several things at once. It is far cheaper to be told about a mistake by a proofreader today than by a user next year.

**Lesson:** turn on the strictest checks at the start. Adding them to a large project later means fixing a thousand complaints at once.

### An error message should say what to do

When the setup script finds a problem, it does not merely announce failure. It names the problem and prints the command that fixes it. A tested case even confirms it turns away an older Intel Mac with a clear explanation instead of a baffling one.

**Lesson:** whoever reads an error message is already having a bad moment. Tell them the next step.

### An honest gap

At this point `make test` ran no real tests of the program's logic, because there was no logic yet. The plan says so plainly, and says which step fills the gap.

**Lesson:** "not yet, and here is when" is a respectable answer.

## Questions to think about

1. Why is "it works on my machine" not good enough when you are the only developer? (Hint: you will get a new machine one day.)
2. What could go wrong if warnings are allowed to pile up?
3. Think of instructions you have followed that left out a step the writer found obvious. How could the writer have caught it?

## Where to look next

- `project.yml`, the readable description
- `Makefile`
- `scripts/bootstrap.sh`
