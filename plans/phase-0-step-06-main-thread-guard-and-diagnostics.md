# feat: Phase 0 step 6, main-thread guard and diagnostics

Date: 2026-10-09

Make "no file-system call on the main thread" (quality bar 2) something the code checks for itself, and give the app logs and local diagnostic reports to investigate hangs with.

## Acceptance criteria

- [x] `MainThreadGuard.assertOffMainThread()` at every file-system entry point: `DirectoryReader.readItems`, `LocalDiagnosticsStore.save` and `reports`
- [x] On the main thread the guard logs a fault and, in debug builds, stops the program
- [x] The handler is injectable per task (`MainThreadGuard.withHandler`), so tests can prove a guard fires without crashing and without affecting parallel tests
- [x] `Log` defines six `os.Logger` categories under the subsystem `com.mjmcport.cairn`: filesystem, metadata, operations, ui, lifecycle, diagnostics
- [x] `DiagnosticsSubscriber` (app target) receives MetricKit diagnostic payloads and saves each as JSON through `LocalDiagnosticsStore`, in `~/Library/Application Support/Cairn/Diagnostics`, keeping the newest 50
- [x] No report leaves the Mac; no networking code exists anywhere in the app

## Tests

- [x] The guard fires on the main thread and names the entry point; it is silent off the main thread
- [x] Listing a folder synchronously on the main thread trips the guard; the async API awaited from the main actor does not
- [x] Saving and listing diagnostics on the main thread trip the guard
- [x] Handlers in two concurrent tasks each see only their own violation
- [x] The store writes a report, prunes to its limit, keeps same-instant reports apart, and cannot be steered outside its folder by the report kind
- [x] `scripts/check-main-thread-guard.sh`: a package source file that calls a file-system API must contain the guard
- [x] `scripts/check-no-network.sh`: no networking API in the app or package sources
- [x] `scripts/test-source-checks.sh` tests both scripts

## Design notes

- The handler override is a task-local value rather than a global, so Swift Testing's parallel tests cannot interfere.
- `LocalDiagnosticsStore` lives in FileSystemCore so it can be unit tested; the app target has no unit-test bundle. The MetricKit subscriber stays in the app target.
- MetricKit on macOS delivers diagnostic payloads only, at most once a day, and crash reports on the next launch. The subscriber cannot be exercised end to end in a test.
- The source checks are heuristics on file contents. They catch a forgotten guard in a new file, not a second unguarded function in a file that already has one.

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 6 and quality bars 2 and 10
