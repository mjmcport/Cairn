# Phase 1A: Browse

Date: 2026-10-09

Milestone 1A of Phase 1 (Finder-replacement core). It turns the walking skeleton into a browser: history, tabs, live folders, three views, a sidebar, a path bar and state that survives a quit. The workstreams come from the Claude Doc "Mac file manager implementation plan"; this file fixes their order as steps, one commit each.

| Step | Name | Delivers | Quality bar |
| --- | --- | --- | --- |
| 1 | Navigation history | Back and forward per browser, selection restored on return, toolbar buttons | 6 |
| 2 | Tabs | A custom tab bar inside the pane; each tab is its own browser | |
| 3 | Fast first rows | The first batch of rows shown unsorted at once, the sort in the background, and a performance test: first rows of a 10,000-item folder in 200 ms or less | 4 |
| 4 | Live updates | FSEvents per visible folder, coalesced; a change made elsewhere appears within 1 s | 5 |
| 5 | List view | `NSOutlineView` with disclosure triangles, type-to-select, sortable columns including Date Added and Size on Disk, folders-first option | 6 |
| 6 | Icon view | `NSCollectionView` with cached thumbnails; placeholders for online-only cloud files | 7 |
| 7 | Column view | `NSBrowser` with a preview column | |
| 8 | Sidebar | Favorites (bookmarks), Locations (volumes, eject), Cloud, Tags, Recents | 7 |
| 9 | Path bar | Breadcrumb with menus, Go to Folder with completion, Copy Path in four formats | |
| 10 | State restoration | Windows, tabs, view settings and column widths restored after quit and crash | 3 |

Each step follows the loop in `CLAUDE.md`: plan, work with tests, review, record lessons, commit. When to push, how to wait for CI and how branches and pull requests work are in `CLAUDE.md` under "CI, pushing and branches".

Order notes:

- History comes first because tabs, the sidebar and the path bar all navigate through it.
- Fast first rows comes before live updates and the outline view, which both change how rows reach the table.
- State restoration comes last so it can cover everything the earlier steps add.

## Requirements for the milestone

### Fast first rows (step 3)

- **Show first, sort after.** When a folder is opened, the first batch of rows is shown unsorted as soon as it has been listed. The app does not wait for the rest of the listing or for the sort.
- **Sort in the background.** The sort runs off the main thread while the unsorted rows are on screen. When it finishes, the list settles into sorted order.
- **A performance test holds the number.** It asserts that the time to first rows for a 10,000-item folder is 200 ms or less (quality bar 4).

Why: the committed baseline (`docs/performance/baseline.json`) shows 0.266 s to first rows for 10,000 items. Listing takes 54 ms and sorting takes 144 ms, and today `BrowserModel.load()` sorts the whole folder before it publishes any row. Showing the first batch before the sort removes the sort from the wait.

How the test measures it:

- The measured interval starts at the request to load and ends when the first batch reaches the list. The current `LoadFolder` signpost interval ends after the full sort, so it cannot be used as it is: step 3 ends it at the first batch or adds a second interval that does.
- The 200 ms assertion applies on the reference Mac, the one that recorded the baseline. Times from another Mac, the CI runner included, are not comparable (`docs/performance/README.md`), so there the test reports its time without judging it.

## Phase 1 exit requirements

These apply to the whole of Phase 1, not only to milestone 1A. They sit in this file until a plan for the whole phase exists.

- **Developer ID signing and notarization are required by the end of Phase 1.** A build handed to anyone outside the project is signed with a Developer ID certificate, uses the hardened runtime and is notarized by Apple. This needs Apple Developer Program membership.
- **The CI build is not a release.** The zip that CI uploads from `main` is signed ad hoc, not with a Developer ID, and is not notarized. It is for checking that the app builds and packages, not for distribution.
