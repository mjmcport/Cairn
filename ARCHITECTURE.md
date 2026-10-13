# Architecture

Cairn is an AppKit app built from five Swift packages. The rule that shapes everything: **only the top two layers touch AppKit, so the core stays testable without a window.**

## Layers

```
App target      Windows, menus, the Settings window, launch, diagnostics subscriber
    │
BrowserUI       Panes, the file list, models that drive the views
    │                                          ── AppKit boundary ──
    ├── FileOperations     Copy, move, trash, rename, undo        (stub)
    ├── FileMetadata       Thumbnails today; Get Info readers in Phase 1
    │         │
    └── FileSystemCore     Items, listing, sorting, watching, logging, the main-thread guard

TestSupport     Fixture-tree builder; used by every test target, depends on nothing
```

An arrow means "depends on". `BrowserUI` also uses `FileSystemCore` directly. Nothing below the boundary imports AppKit, SwiftUI or Cocoa; `scripts/check-appkit-boundary.sh` enforces that.

| Module | Responsibility | May import |
| --- | --- | --- |
| `App/` | Entry point, main menu, the window, the Settings window, MetricKit subscriber | AppKit, SwiftUI, MetricKit, BrowserUI, FileSystemCore |
| `BrowserUI` | `PaneViewController` (one pane: its tabs, the window's title and keyboard focus), `TabList` (the order of a pane's tabs and which one is showing; no AppKit in it), `TabBarView` (the row of tabs, their close buttons and the New Tab button), `BrowserModel` (state of one browser: the folder shown, the folders open in it, the selection), `FolderKey` and `OpenFolder` (a folder open in place, by its names from the folder shown), `BrowserHistory` (its back and forward places, with the selection and the open folders left at each), `BrowserViewController` (the list, an outline; one per tab), `OutlineNode` (the handle of one outline row), `IconCollectionView`, `IconItem`, `GenericIcons`, `ThumbnailLoader` and `ThumbnailCache`, `TypeAhead` (the icon presentation and its pictures), `ColumnBrowserController` and `PreviewViewController` (the column presentation and its preview), `WindowContentViewController` (the sidebar beside the pane) and `SidebarViewController` (the source list), `BrowserToolbar` (the Back and Forward buttons), `BrowserSettings` and `SettingsView` (the one setting, and its window's content), `AccessibilityElement`, `InitialLocation` | AppKit, SwiftUI, the three core packages |
| `FileOperations` | `FileOperation` today; the operation engine in Phase 1 | Foundation, FileSystemCore |
| `FileMetadata` | `ThumbnailProviding` and `QuickLookThumbnailer` (a picture of a file, as a `CGImage`), `MetadataGroup`; Get Info readers in Phase 1 | Foundation, CoreGraphics, QuickLookThumbnailing, FileSystemCore |
| `FileSystemCore` | `FileItem` (with its size on disk, the date it was added and whether it is online only), `DirectoryReader`, `CompositeReader` and `MetadataQueryReader` (a listing of a folder, or of a tag or the recents), `VirtualLocation`, `SidebarBuilder` with its volume, cloud and tag sources, `Favorites`, `FileItemSort` (name, size, size on disk, dates modified and added), `FolderWatcher` (one FSEvents stream per watched folder), `MainThreadGuard`, `Log`, `LocalDiagnosticsStore` | Foundation, os, CoreServices |
| `TestSupport` | `FixtureTree`, `FixtureNode`, `FixtureNames`, `TemporaryDirectory` | Foundation |

## How a folder gets on screen

1. `AppDelegate` resolves the launch folder (`-OpenFolder <path>`, else the home folder) and gives the window a `WindowContentViewController`: the sidebar beside a `PaneViewController`. The pane starts with one tab, and each tab is a whole `BrowserViewController`. Only the showing tab's view is in the window, and a browser lists its folder when its view loads.
2. Each browser owns a `BrowserModel` on the main actor. A user action that loads a folder goes through `run`, which cancels the previous action's task and starts a new one. A command that cannot do anything, such as Back with no history or Enclosing Folder at the root, never reaches `run`, so a load under way is left to finish.
3. `BrowserModel.load()` reads `DirectoryReader.listing(in:)`, a stream of at most two events. The folder is enumerated in a task that never runs on the main actor, with the listing's resource keys prefetched and a cancellation check every 256 items. A folder of more than 2,000 items hands over its first 2,000 as soon as the next one has been read, and every folder ends with all of its items. Ending the stream from the model's side cancels the enumeration.
4. When the first items arrive and the list is empty, the model filters out hidden items and calls `onChange` with the rows as they were read, unsorted, while its state is still loading. The rows can be used: selected, opened, scrolled. A reload skips this, so it keeps its rows until the sorted list replaces them. A folder that fits in one batch has no first items and is shown once.
5. When all the items have arrived, `FileItemSort.arranged(_:includingHidden:)` filters and sorts them off the main actor, reading each name once and checking for cancellation on every comparison. The model then sets the sorted list and the selection and calls `onChange` again. The selection is what the user has selected since the move, or else what the history remembered; it is not applied to the first rows. The controller reloads the whole outline for a load or a refresh of the top level, which keeps the scroll offset and keyboard focus, and one open folder for a change inside it.
6. After every wait, the model checks two things before it publishes: a load counter, which discards a result for a folder the user has already left, and the task's cancellation, because a cancelled stream still delivers an event that was waiting and then ends without throwing. A stream that ends with no all-items event is a failed listing. A failed listing clears the rows, the first rows included, and shows why.
7. Every move to another folder is recorded in the model's `BrowserHistory` with the selection being left, so Back and Forward restore it. Places are compared by the text of their paths, and a selection at the top level is matched to the listed items by name, and one inside an open folder by its place under the folder shown; neither touches the disk.

A load is wrapped in two signpost intervals. `FirstRows` runs from the request until the list has rows: the first rows of a large folder, or the sorted list of a smaller one. The performance test measures it. `LoadFolder` covers the whole load, until the sorted list has been published.

## How a change on disk reaches the list

1. While a pane's view is on screen, its showing tab watches the folder it shows. The pane tells that browser's model to start, and tells every other browser to stop; a move starts the watch of the new folder as the command arrives, where the load in flight is retired.
2. `FolderWatcher.signals(for:)` returns a stream of "look again" signals. It resolves the folder with `realpath`, because FSEvents reports real paths, and starts one FSEvents stream for it in a task that never runs on the main actor, with events delivered on a private queue. The stream is created with `WatchRoot` and without `FileEvents`, so an event names a folder in which something changed, and a change to the watched folder itself is flagged.
3. FSEvents collects events for up to 0.3 s and delivers them in one callback. `FolderWatcher.eventConcernsFolder(path:flags:folder:)` keeps a callback when one of its events names the folder, names a direct subfolder, or carries the root-changed or must-scan flag. A callback that is kept becomes one signal: the watch is live, the contents changed, or the folder itself changed. The model answers all three the same way.
4. The model answers a signal with a refresh: `DirectoryReader.items(in:)` for the whole folder, the same filter and sort as a load, and `differs(from:)` against the rows on screen, all off the main actor. It publishes only when the visible rows changed, or when a folder that could not be listed now can. It never sets the loading state and never shows first rows.
5. Signals are answered one at a time. Any number that arrive during a refresh are answered by one more. A signal that arrives during a load is set aside, and the load answers it with one refresh when it settles. A load that starts clears what was set aside, because its listing begins after every signal so far.
6. A refresh reads the load counter and never changes it. A move or a load retires a refresh in flight, and a refresh cannot retire a load. A refresh also stops when its watch has ended.
7. The model says whether a publish was a load or a refresh. For a refresh the controller reloads the table and puts the selection back on the same items by name, and does not scroll to it, so the scroll offset and keyboard focus stay where they were.
8. A folder that is deleted or renamed away is a refresh whose listing fails: the rows are cleared and the reason is shown, as for a failed load. The watch stays, so a folder that appears again at that path is listed.
9. The watch stops when the tab is hidden or closed, when the pane's view leaves the screen, and when the model goes away. Ending the signal stream stops the FSEvents stream. Every start of a watch sends a "live" signal, so a tab that comes back on screen brings its list up to date.

A change that another computer makes on a network share is not reported by FSEvents; those locations are handled later in Phase 1.

## How a folder opens in place

The list is an `NSOutlineView`. A folder row has a disclosure triangle, and opening it lists the folder beneath the row without moving anywhere: history, the title and the tabs are untouched.

1. The model keeps the top level as `items` and a dictionary of open folders by `FolderKey`, the names from the folder shown down to the folder. Each open folder holds its own sorted items and whether it is listing, listed, or could not be listed. A key is made of names because a listing spells a folder differently from the location that was opened.
2. `openFolder(_:)` and `closeFolder(_:)` change that state as the command arrives and publish at once. Only the listing runs in a task: `DirectoryReader.items(in:)` and the same filter and sort, off the main actor, publishing the folder's rows once they are sorted. Each opening has a token, and each listing also carries the load counter, so a move, a load or a close retires a listing in flight.
3. A folder that cannot be listed stays open with the reason, which the outline draws as a row beneath it that is not selectable. A later listing of the same folder brings its rows back.
4. A reload keeps the open folders and lists them again, one at a time, after the top level has settled; a folder that is gone is closed with what was open inside it. A move closes everything.
5. Every open folder has its own watch, and one answerer takes the signals of all of them one at a time, shallowest first, with the rules above: a refresh is of one folder, publishes only when its rows changed, and never changes the load counter. A signal for a folder that is being listed, or that arrives while the top level loads, is paid with one refresh when that settles.
6. The selection may hold items at any level. It is looked up by an item's own URL, then by its path below the location as it was opened or below the folder the listing followed, and only then, for a URL outside both, by name at the top level.
7. A change of sort re-arranges the top level and every listed open folder in one pass off the main actor and publishes once. A header click and View > Keep Folders on Top both come to `changeSort(to:)`.
8. The outline holds a handle for each row that stays equal to itself across reloads, so a folder that was open is still open. AppKit asks for the handles of the rows it draws, so a handle for a folder far down a long list is made from the model when it is needed. Opening and closing by the user come back from the outline's notifications and go to the model; opening and closing from the model never go back.

### What a history entry remembers

A history entry holds the keys of the folders that were open when the place was left, beside the selection. Going Back or Forward to it, with the setting on, opens them again once the top level has settled: shallowest first, one at a time, through the same path as the user's own opening, so it is retired by a move, a load or a close like any listing. A folder that is gone is skipped without a message, and what was selected inside them returns as their rows appear, unless the user has selected something since. Open, Enclosing Folder and a first visit start with a closed outline.

The setting is `BrowserSettings.rememberOpenFolders`, in the user defaults, on until it is turned off. It is read when the move is made. The Settings window (Cairn > Settings…) is a SwiftUI view hosted in an AppKit window and holds that one checkbox.

## How a folder is shown as icons

`View > as Icons` (Command-2) shows the showing tab's folder as a grid of pictures and names, and `as List` (Command-1) returns. The mode is the tab's own and lives in `BrowserModel.viewMode`; the model's items, selection, sort, history and watches are the same for both.

1. A browser owns both views, the outline and an `NSCollectionView`, and shows one. A switch is a hide and a reload: nothing is listed again. Switching to icons closes the folders that were open in place, because the icon view shows the top level only; what was selected inside falls back to the folder.
2. The collection view has a fixed item size, so laying out 100,000 items is arithmetic: only the cells in or near view are made (140 in a probe). A reload clears its selection, so the controller applies the model's, as the list does, and a publish that empties the rows reloads it at once.
3. A cell has a picture the moment it is configured: the system's icon for the type, chosen from the item's kind and the extension of its name, with no file access. It asks `ThumbnailLoader` for a better one only when it is about to be shown, and cancels when it goes away.
4. `ThumbnailLoader` is an actor. It answers from a cache bounded in entries and in bytes, least recently used out first, keyed by the item's place, modified date, size and the pixel size asked for, so a changed file is a different key. Otherwise it asks a `ThumbnailProviding`, at most four at a time, the newest request first, off the main actor. Four in flight is where the system's generator stopped getting faster in a measurement.
5. A file that is online only is never given to the provider: drawing a file can make the system download it. The cell does not ask for it and the loader refuses it as well. `FileItem.isOnlineOnly` comes from values the listing already reads (a size and no allocated blocks); iCloud's own downloading status said it outright but cost nine times the listing, so it is not read there.
6. A cell is one accessibility element that speaks the name, the kind and whether the file is online only. Its picture and cloud mark are decoration and are not elements.
7. `NSCollectionView` has no type-to-select and no double-click action. A small subclass forwards typed characters and a double-click, and `TypeAhead` (a value with no clock of its own) decides what has been typed.

## How a folder is shown as columns

`View > as Columns` (Command-3) shows the showing tab's folder as a row of columns with a preview. It is the third value of `BrowserModel.viewMode`; the items, selection, sort, history and watches are the same as in the other two.

1. The columns are the model's open chain. Column 0 lists `model.items`; each next column lists the open folder that is selected in the one before it. Nothing is copied: the `NSBrowser` asks the model through its item-based delegate, and its handles are `OutlineNode`s, as the outline's are.
2. Selecting in a column is a request to the model. The controller works out the folders that lead to what is selected, opens those the model has not got open (so they are listed and watched), closes the others, and sets the model's selection. Only then does it ask for the preview. A flag stops the model's own publishes, which come back from that request, from being drawn as if they were changes made elsewhere. Without the flag the reload and the selection feed each other until the process dies.
3. A folder's rows arrive later than its selection. When the model publishes the listing, only that folder's column is reloaded and the selection is put back.
4. Switching to columns keeps the folders that lead to the selected items and closes the others (`pruneOpenFolders`); switching to the list leaves them open, and switching to icons closes them.
5. The last column is a `PreviewViewController` for a file: the same picture pipeline as the icon view at a larger size, the name, and facts as words ("Size: 2 kB", "Availability: Online only, not on this Mac"). Several items show a count and a total and make no pictures, and a file that is online only is never asked for a picture.
6. Each column's list is named by its place ("Column 1"), and the preview's picture carries its description on the image itself, because that is where the audit reads it from.

## How the sidebar works

The window's content is a split view: the sidebar on the left, the pane on the right. The sidebar is a source list of four sections, built from sources by one pure function.

1. **Sources.** `FavoriteStoring` (bookmarks in the user defaults), `VolumeSource` (mounted volumes), `CloudSource` (iCloud Drive and each folder under `~/Library/CloudStorage`) and `TagSource` (the tags in use). Each is a protocol with a stub in the tests. `SidebarBuilder.sections` turns their answers into sections and items and touches nothing; reading the sources is done off the main actor and arrives as values.
2. **Favorites** are bookmarks, so a favorite follows its folder when it is moved or renamed. One whose folder cannot be found is kept and spoken as "not found". Recents is the first item of Favorites and cannot be removed.
3. **Choosing** an item asks the pane to show its place in the showing tab, as a move: history, the title and the toolbar follow, and Back returns. Command-click opens a tab. The sidebar holds no browser. It follows the showing tab through `onLocationChange`, which the browser reports as a move is made and the pane reports again when another tab starts showing.
4. **A place that is not a folder** (a tag, the recents) is a URL with a scheme of its own (`cairn-tag:`, `cairn-recents:`), so history, tabs and the title need no new idea. `CompositeReader` sends a file URL to `DirectoryReader` and a virtual one to `MetadataQueryReader`, which runs a Spotlight query scoped to this Mac and yields the same events a folder does. Its files are real files, so open, selection and thumbnails work as they do anywhere.
5. **What a virtual location is not.** It is a flat list: folders do not open in place in it, it has no enclosing folder, and nothing watches it (a one-shot query; it is read again when the tab goes there). Open on a folder in it enters that folder.
6. **Eject** unmounts and ejects the one volume whose button was pressed, through the workspace, off the main thread, and says why in the window when it fails. Nothing ejects any other way.
7. **Commands with focus in the sidebar.** The pane is a sibling of the sidebar, not an ancestor, so the split view controller offers the pane (and through it the showing browser) for the actions they handle, as the pane does for its own tab bar.

## Tabs

A pane keeps every tab's browser alive as a child view controller, so a tab that is not showing keeps its folder, history, selection, open folders, sort, view mode and scroll position, and finishes a listing it had started. Only the showing tab is watched for changes on disk, and only while the pane is on screen; a tab that is shown again refreshes its list as its watch starts. Closing a tab cancels its listing and stops its watch. Closing the last tab closes the window.

- `TabList` holds the rules: a new tab goes last and is shown, closing the showing tab shows its right neighbour or else its left, and next and previous wrap around. The tab bar is hidden while there is one tab.
- A tab command (`newTab`, `closeTab`, `showNextTab`, `showPreviousTab`) changes the tab list as it arrives and brings the window in line before it returns. Only a browser's listing runs in a task, so the same command sent twice in a row does what two commands should.
- The pane owns what a browser cannot know: the window's title, which is the showing tab's folder name, and keyboard focus. After the showing tab changes, focus goes to the new tab's file list, unless it is on a tab bar control that is still there. A browser keeps its own title and reports a change to the pane.
- The Go commands and the toolbar's buttons travel the responder chain to the showing browser. With keyboard focus on the tab bar the chain reaches the pane without passing a browser, so the pane offers the showing one through `supplementalTarget(forAction:sender:)`. `ToolbarButtonItem` follows such offers when it walks the chain itself.
- The tabs are the app's own, drawn inside the pane. `NSWindow`'s window tabbing is switched off at launch.

## Rules the code enforces on itself

| Rule | Enforced by |
| --- | --- |
| No file-system call on the main thread | `MainThreadGuard.assertOffMainThread()` at each entry point; unit tests prove each guard fires; `scripts/check-main-thread-guard.sh`, whose list of calls includes `FSEventStreamCreate` and `realpath` |
| Core packages never import a UI framework | Package manifests; `scripts/check-appkit-boundary.sh` |
| No networking code | `scripts/check-no-network.sh` |
| Every control has an identifier and a spoken label | `AccessibilityElement` and `apply(_:)`, for AppKit views and for SwiftUI; `scripts/check-accessibility.sh`, which also rejects the SwiftUI modifiers outside the helper; the accessibility audit in the UI suite |
| Swift 6, complete concurrency checking, warnings as errors | `project.yml`, package manifests |
| One code style | `.swift-format`, `make lint`, the pre-commit hook |
| Build settings match the decisions | `scripts/check-project-spec.sh` |

## Testing

| Kind | Framework | Where | Run with |
| --- | --- | --- | --- |
| Unit | Swift Testing | `Packages/*/Tests/*Tests` | `make test` |
| Repository checks | Shell | `scripts/check-*.sh`, `scripts/test-*.sh` | `make test` |
| End-to-end | XCUITest | `UITests/` | `make uitest` |
| Performance | XCTest `measure` | `Packages/FileSystemCore/Tests/FileSystemCorePerformanceTests`, `UITests/PerformanceTests.swift` | `make perf` |

Tests build real folder trees with `FixtureTree` in the temporary directory and read results back with system calls. They never touch a real user folder.

Two launch arguments keep an end-to-end test off the person's data, like `-OpenFolder`: `-FavoritesSuite <name>` keeps favorites in a defaults suite of that name, and `-SearchScope <folder>` restricts Spotlight queries (Recents, tags) to a folder, so what they list is the fixture and not whatever was used lately.

A unit test that asserts on a clock is in a suite named in `TIMING_SUITES` in the `Makefile`. Every suite of a package shares one process and one main actor, so in the parallel run such a test measures how busy the other suites keep it; `make test` runs those suites alone, after the rest, and their bounds are not widened.

## Build

`project.yml` is the source of truth; XcodeGen turns it into `Cairn.xcodeproj`, which is not committed. The `Makefile` wraps every task and sets `DEVELOPER_DIR` itself, so it does not depend on `xcode-select`. CI runs the same `make` tasks.

## Decisions

Each decision that shaped this structure has a record in [`docs/adr`](docs/adr):

1. [AppKit for the interface](docs/adr/0001-appkit-for-the-interface.md)
2. [XcodeGen for the project file](docs/adr/0002-xcodegen-for-the-project-file.md)
3. [MIT license with clean-room rules](docs/adr/0003-mit-license-with-clean-room-rules.md)
4. [Minimum macOS 15](docs/adr/0004-minimum-macos-15.md)
5. [Distribution outside the App Store](docs/adr/0005-distribution-outside-the-app-store.md)
6. [No telemetry](docs/adr/0006-no-telemetry.md)

## What is not here yet

Phase 0 is a skeleton. Get Info, file operations, undo, state restoration, signing and updates all arrive in Phase 1. The plan is the Claude Doc "Mac file manager implementation plan".
