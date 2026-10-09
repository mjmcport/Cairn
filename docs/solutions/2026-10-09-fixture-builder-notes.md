---
title: Fixture builder notes
date: 2026-10-09
step: Phase 0 step 4
tags: [testing, fixtures, apfs, xattr]
---

# Fixture builder notes

## What we learned

- **Temporary paths have two spellings.** `FileManager.temporaryDirectory` returns `/var/folders/...`, but the system reports `/private/var/folders/...`. `FixtureTree` resolves symlinks in its root so paths compare equal. Enumeration code in step 5 must expect the same difference.
- **APFS keeps Unicode names byte for byte** but treats names that differ only by normalization as the same file. A precomposed and a decomposed spelling of one name cannot share a folder, so `FixtureNames.unicode` avoids that pair.
- **The longest file name is 255 UTF-8 bytes.** A 256-byte name fails with `ENAMETOOLONG`.
- **Tags are settable through `NSURL.setResourceValue(_:forKey: .tagNamesKey)`.** Finder stores them as a binary property list in the `com.apple.metadata:_kMDItemUserTags` extended attribute, each entry as `name` or `name\ncolorNumber`.
- **A quarantine attribute written by hand is accepted** in the form `flags;hexTimestamp;agent;UUID`.
- **`ftruncate` on a new file makes a sparse file** on APFS: 1 GB logical, under 1 MB allocated.
- **Removing a tree with a `0o000` folder needs `chmod` first**, top down. `FixtureTree.remove()` does it; plain `FileManager.removeItem` fails.
- **Creating 100,000 empty files takes about 5 seconds.** Performance tests in step 7 should build that folder once per suite, not once per test.

## What to carry forward

- Read properties back with system calls in tests, not through the code under test.
- Use `tree.path(_:)` for system calls and `tree.url(_:)` for Foundation APIs.
