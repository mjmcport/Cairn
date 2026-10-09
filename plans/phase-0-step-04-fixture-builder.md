# feat: Phase 0 step 4, fixture builder

Date: 2026-10-09

Give every test a way to describe a folder tree in a few lines and get it on disk, so file-system behavior is tested against real files with known properties.

## Acceptance criteria

- [x] `FixtureTree.build { ... }` builds a tree in a temporary folder from a result-builder description and returns its root
- [x] `FixtureNode` covers: files with given contents, fully written sized files, sparse files, dot-hidden files, folders, symbolic links, hard links and application bundles
- [x] Modifiers cover: extended attributes, Finder tags, the quarantine flag, the BSD hidden flag and POSIX permissions
- [x] `FixtureNames` supplies Unicode names, a 255-byte name and the numbered names used by large folders
- [x] `FixtureNode.files(count:in:)` builds 10,000- and 100,000-item folders
- [x] `remove()` deletes a tree that contains unreadable folders
- [x] A failed build removes what it created; a duplicate name fails instead of overwriting

## Tests

Each test reads the property back with a system call (`lstat`, `readlink`, `getxattr`, `readdir`) rather than through the builder:

- [x] contents and sizes; allocated blocks cover a sized file
- [x] a 1 GB sparse file occupies under 1 MB
- [x] dot names and `UF_HIDDEN`
- [x] symlink destinations stored verbatim, including a dangling link
- [x] a hard link shares an inode with a target listed after it
- [x] a bundle reports `isPackage`
- [x] extended attributes, tags (decoded from Finder's property list), quarantine fields
- [x] permission bits, then removal of a tree with a `0o000` folder
- [x] Unicode names survive byte for byte; a 256-byte name is rejected
- [x] 10,000 and 100,000 items counted with `readdir`

## Design notes

- Building runs in three passes: contents, then links, then attributes. A hard link can name a file listed later, and a read-only folder can still be filled.
- The builder is synchronous. It is test-only code and Swift Testing runs tests off the main thread.
- Measured on the development Mac: 10,000 items in 0.55 s, 100,000 items in 5.3 s.

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 4
