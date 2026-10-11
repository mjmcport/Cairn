# Phase 1, step 2: several places at once

- **Commit:** `Phase 1 step 2: tabs`
- **Plan:** `plans/phase-1a-step-02-tabs.md`
- **Engineering note:** `docs/solutions/2026-10-10-command-w-with-a-panel-in-front.md`

## Fingers in the book

Watch someone consult a thick reference book. Before long they have a finger holding one page, a thumb in another, and a scrap of paper marking a third. They are not reading three pages at once. They are refusing to lose their place.

That is what tabs are. Until this step a Cairn window showed exactly one folder, and comparing two meant leaving one to visit the other, then finding your way back. Now a window can hold several folders, each one waiting exactly as you left it.

## What was added

- **Tabs.** Each is a complete, independent browser with its own folder, its own back-and-forward history and its own selection.
- **A tab bar,** drawn by Cairn itself, which appears when there are two or more tabs.
- **The usual commands,** with the shortcuts people already know from Finder and Safari: new tab, close tab, next, previous.
- **Full keyboard and VoiceOver support** for every tab control.

## Words you will meet

- **Tab.** One of several views sharing a window, with only one showing at a time.
- **Focus.** Where your typing currently goes.
- **Key window.** The window in front, the one that receives your typing.
- **Responder chain.** The route a command travels through an app, looking for something able to carry it out.

## Decisions, and what they teach

### Reuse the whole thing

How do you make each tab remember its folder, history, selection and scroll position? One way is to write code that saves all of that when you leave a tab and restores it when you return. The step took a simpler road: each tab simply *is* a complete browser, kept alive in the background. Nothing is saved or restored, because nothing is ever thrown away. The browser built in earlier steps did not need to learn that tabs exist.

**Lesson:** before writing code to copy and restore something, ask whether you can keep the original.

### The rules live in a small, plain place

Where does a new tab go? Which tab shows after you close one? What happens at the end of the row when you ask for "next"? What if you close the last tab? These rules were written as one small piece of logic with no windows or buttons in it, just as the history was in step 1. Each rule became a quick test.

**Lesson:** the same move again. Separate the rules from the drawing, and the rules become easy to get right.

### Building a tab bar instead of borrowing one

macOS offers window tabs for free. Cairn did not use them. The project is heading toward two side-by-side panes, each with its own tabs, and the system's tabs belong to a whole window and cannot be split that way. Building its own cost real work in this step, and bought room for a later one.

There was a trap here too. The system reserves certain command names for its own tabs. Had Cairn used the same names, its menu items would have quietly operated the system's tabs instead of its own. Cairn's commands were given distinct names, and the system's tab feature was switched off.

**Lesson:** a free component is only free if it can do what you will need next. And when you build beside a system feature, make sure the two cannot be confused.

### Command-W and the question "which window?"

This is the bug the step will be remembered for.

Command-W should close a tab. Open the "About Cairn" panel, so that it sits in front, and press Command-W. Any person would expect the panel to close. Instead, a tab closed in the window *behind* it, and the panel stayed.

The plan had reasoned that a small panel has no tabs, so the command would pass through it and arrive at a general "close whatever is in front" handler. But macOS, after trying the front window, offers the command to the main window behind it next. The tab code was there, heard "close tab", and obliged.

The fix is one question, asked before acting: *is the window in front actually mine?* If not, close that window.

**Lesson:** "the obvious target" to a person and to a program can be two different things. And a confident line of reasoning about how a system behaves is still a guess until it has been tried.

### Only a real test could have found it

A fast, isolated test cannot have a window "in front", since there are no real windows in it at all. The bug showed itself only in an end-to-end test that launched the real app, opened the real panel, and pressed the real keys.

**Lesson:** some truths are only visible when the whole thing is running. That is what the slow, expensive tests are for.

### Not by colour alone

The tab that is showing is marked by more than a change of colour, and each tab reports itself to VoiceOver as a tab that is or is not selected. A tab's close button sits beside it, not inside it, so that keyboard and VoiceOver users can reach both.

**Lesson:** if the only signal is colour, some people will not receive it. Give every signal a second form.

### A tab in the background stays quiet

A tab you are not looking at is allowed to finish loading its folder. It is never allowed to change the window's title, steal the keyboard focus, or alter the toolbar. Closing a tab cancels whatever it was loading.

**Lesson:** when several things share one stage, be exact about who may touch what.

### A third version of macOS disagrees

In step 1 the oldest macOS behaved differently. This time a test passed on the oldest and the newest and failed on the one in the middle. The lesson from step 1 was simply confirmed from the other side.

**Lesson:** "it works on the versions either side" proves nothing about the one between.

## Left open

- Nobody had yet looked at the finished tab bar on a real screen with a critical eye; the tests check behaviour, not looks.
- Some checks added during review were not shown to fail first, which the project's own rule asks for.
- The automatic accessibility audits cannot complete on the development Mac, so the shared examiner is their only judge.

## Questions to think about

1. Why is "keep the original alive" simpler than "save and restore"? When would it become too costly?
2. Think of an app where a keyboard shortcut did something to a window you were not looking at. What had the app got wrong?
3. Besides colour, how many ways can you think of to show which of several items is selected?

## Where to look next

- `Packages/BrowserUI/Sources/BrowserUI/TabList.swift`, the rules
- `Packages/BrowserUI/Sources/BrowserUI/PaneViewController.swift`
- `UITests/TabsTests.swift`
