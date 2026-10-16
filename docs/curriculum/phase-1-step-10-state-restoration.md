# Phase 1, step 10: picking up where you left off

- **Commit:** `Phase 1 step 10: state restoration`
- **Plan:** `plans/phase-1a-step-10-state-restoration.md`
- **Engineering note:** `docs/solutions/2026-10-16-state-restoration-notes.md`

## Picking up where you left off

A carpenter who leaves the workshop for the night does not tidy everything away. The saw stays on the bench, the half-cut board stays in the vice, and in the morning the work goes on from where it stopped. A workshop that was swept bare each evening would cost hours every day.

Until this step Cairn swept itself bare. Quit it, and the next launch opened one window on your home folder. The tabs, the views and the sort orders arranged over a day were gone. Now Cairn keeps the bench as it was.

## What changed

1. **The window comes back.** Its position and size, its tabs in order with the same one showing, and for each tab its folder, its view (list, icons or columns), its sort, whether hidden files show, which folders were open, what was selected, and Back and Forward.
2. **The sidebar and the path bar** keep their width and whether they show.
3. **It saves as you go.** A moment after something changes, not only when you quit, so a crash loses at most a second of arrangement.
4. **A missing folder is not an error.** If the folder is gone, you land in the nearest folder above it that still exists. A removed tag takes you home.
5. **A setting.** "Reopen windows and tabs when Cairn starts" is on by default. Closing the window yourself means the next launch starts fresh.

## Words you will meet

- **State.** Everything about how something is set up right now, as opposed to the data it holds.
- **Debounce.** Waiting for a burst of changes to settle before acting on them once, as you wait for a friend to finish a sentence before answering.
- **Autosave.** A system feature that remembers a window's frame or a table's columns under a name you give it.
- **Version.** A number written with saved data, so a newer program can recognize data in a shape it no longer understands and ignore it.

## Decisions, and what they teach

### Save while working, not when leaving

If saving happened only at quit, a crash would lose everything exactly when it mattered. So Cairn saves half a second after the last change, and at most a second after the first one even if you keep dragging. Quitting just saves immediately. A crash and a quit become the same case, and the test proves it by killing the app, with no goodbye, and checking that it comes back.

**Lesson:** do not build a special path for the rare bad day; make the ordinary path safe on it.

### Open first, look second

The saved folder might have been deleted, and checking takes the disk's time. Rather than make the window wait, Cairn opens it at once, shows the tab as loading, checks off to the side, and then lists the right folder once. It never lists the missing one, so there is no flicker and no error to explain.

**Lesson:** show something true right away and fill in the rest when you know it.

### Keep what the system already keeps

The window's position and the list's column widths already have a system feature that remembers them. Cairn uses it, and gives each a name that includes the test's own label, so a test never touches your real settings.

**Lesson:** do not rebuild what the platform gives you, but make sure it is isolated like everything else.

### A message sent to everyone

The test that killed the app and relaunched it found a mistake no other test could: the code meant to notice "the person closed the window" was listening to every window, because the window it should watch was not yet set when the listener was made. A small panel closing was taken for the main window closing, and the saved state was thrown away. The listener now names its window.

**Lesson:** a test that does what a person does finds what a test of the parts cannot.

## What was left open

VoiceOver checks, as in steps 4 to 9. Scroll position is not restored, and only one window exists. A watcher test that is slow when the whole suite runs in parallel fails on this Mac before and after this step; it is reported, not hidden.

## Questions to think about

1. Why does a tab that has not been shown yet keep its saved folder untouched until it is?
2. What would you lose if state were saved only at quit?
3. When is it right to throw saved data away, and when to keep it?

## Where to look next

The plan and the engineering note above; `StateSaver.swift` for the timing, `RestoredLocation.swift` for the nearest folder.
