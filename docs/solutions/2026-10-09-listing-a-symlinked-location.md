---
title: A folder location that is itself a symbolic link cannot be listed
date: 2026-10-09
category: solutions
module: FileSystemCore
problem_type: logic_error
component: DirectoryReader
symptoms:
  - Opening /tmp, /var or /etc shows an error instead of the folder's items
  - "The status line reads \"The operation couldn't be completed\""
root_cause: wrong_api
resolution_type: code_fix
severity: medium
tags: [symlinks, url, realpath, directory-listing, macos]
---

# A folder location that is itself a symbolic link cannot be listed

## Problem

`DirectoryReader` refused any location whose last path component is a symbolic link. On macOS that includes `/tmp`, `/var` and `/etc`, which link into `/private`. The error it threw had no description, so the browser showed the system's generic text.

## Symptoms

- `URL.resourceValues(forKeys: [.isDirectoryKey])` returns `isDirectory == false` and `isSymbolicLink == true` for `/tmp`, even when the URL is built with `directoryHint: .isDirectory`.
- `DirectoryReader.readItems` threw `DirectoryReadError.notADirectory`.
- A plain `Error` enum prints as "The operation couldn't be completed. (… error 0.)".

## What Didn't Work

- **`URL.resolvingSymlinksInPath()`**, the fix the reviewer proposed. A probe showed it returns `/tmp` for `/tmp`: it removes the `/private` prefix again, so the directory check still sees a link.
- **`standardizedFileURL`**, which `InitialLocation` already applied. It cleans up `.` and `..` only.

## Solution

Follow the location's links with `realpath` before the directory check and the enumeration. A location that cannot be resolved is passed through unchanged, so listing it reports the real reason.

```swift
private static func followingSymbolicLinks(_ location: URL) -> URL {
  guard let path = realpath(location.path(percentEncoded: false), nil) else { return location }
  defer { free(path) }
  return URL(fileURLWithFileSystemRepresentation: path, isDirectory: false, relativeTo: nil)
}
```

`DirectoryReadError` now conforms to `LocalizedError` ("notes.txt is not a folder.").

## Why This Works

`realpath` returns `/private/tmp`, `/private/var` and `/private/etc`, which are real directories. Neither `resourceValues` nor `FileManager.enumerator(at:)` follows a link in the last component by itself.

## A behavior this fix chose

Items are reported under the folder the link leads to. Opening `/tmp` lists its items, but opening a subfolder moves to `/private/tmp/<name>`, and Enclosing Folder from there lands on `/private/tmp`, not `/tmp`. Finder keeps the path as typed. Phase 1's link handling should decide the rule on purpose; this fix only made the folder listable.

## Prevention

- `DirectoryReaderTests.listsAFolderReachedThroughASymbolicLink` lists a fixture folder through a link, a link to a file, and a broken link.
- Every fixture root is resolved by `FixtureTree.build` before the tests see it, so a test that needs an unresolved location has to build the link itself. No test opens the real `/tmp`, because tests touch only fixture folders.
- Give every error that can reach the status line a `LocalizedError` description.

## Related Issues

- `docs/solutions/2026-10-09-walking-skeleton-notes.md`
