# feat: Phase 0 step 5, walking skeleton

Date: 2026-10-09

Make the app do the one thing that proves every layer is connected: open on a folder, list it, and navigate into a subfolder.

## Acceptance criteria

- [x] `DirectoryReader.items(in:)` lists a folder asynchronously, off the caller's actor, with name, kind, hidden flag, size and modified date prefetched
- [x] A listing stops with `CancellationError` when its task is cancelled, before it starts or while it runs
- [x] `FileItemSort` orders by name (as Finder does), size or modified date, ascending or descending, optionally folders first
- [x] `BrowserModel` holds the location, the visible sorted items and a loading, loaded or failed state
- [x] `BrowserViewController` shows a three-column list (Name, Size, Date Modified); double-click or File > Open (Command-O) opens a folder; Go > Enclosing Folder (Command-Up) goes up
- [x] The app opens on the folder named by `-OpenFolder <path>`, or the home folder
- [x] An empty folder and a folder that cannot be listed each show a message

## Tests

Unit (Swift Testing):

- [x] Hidden-file filtering: dot names and the BSD hidden flag
- [x] Sorting: numeric and case-insensitive names, size, date, folders first, ties, input-order independence
- [x] Cancellation: before the listing starts, and during a 100,000-item listing
- [x] Kinds, sizes and dates read from a fixture; Unicode names; 10,000 items; missing, non-folder and unreadable locations
- [x] The listing runs off the main thread when awaited from the main actor
- [x] Model: navigation, enclosing folder, failure, change notifications, a stale slow listing, a cancelled load
- [x] View controller: columns, accessibility identifier and label, row count after loading, cell text

End-to-end (XCUITest, first real suite):

- [x] Launch on a fixture: three rows, no hidden file, window titled with the folder name
- [x] Double-click a subfolder: one row, window titled "Sub"; Command-Up returns
- [x] Double-clicking a file does not navigate
- [x] A missing folder shows an explanation and no rows

## Design notes

- `FileItem` now carries size and modified date, so `BasicMetadata` in FileMetadata was removed as a duplicate.
- The listing loads the whole folder before showing it. Batched delivery for a fast first row is Phase 1 work; step 7 records the baseline it must beat.
- The model counts loads, so a slow listing of a folder the user has left cannot overwrite the current one.
- A symbolic link to a folder is not navigable yet. Link resolution is Phase 1.

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 5 and quality bars 2 and 9
