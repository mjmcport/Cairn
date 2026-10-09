---
title: Build artifact notes
date: 2026-10-09
step: Phase 0 step 12
tags: [ci, packaging, codesign]
---

# Build artifact notes

## What we learned

- **A Release build of the skeleton zips to about 100 KB.** Artifact storage is not a concern yet.
- **`codesign --display --verbose=4` tells a package's whole signing story**: `Signature=adhoc`, the `runtime` flag for the hardened runtime, and `TeamIdentifier=not set`. Grepping those three lines is enough to prove a build is what it claims to be.
- **`lipo -archs` and `LSMinimumSystemVersion` check the two platform decisions** on the finished binary, independently of the project settings that were supposed to produce them.
- **Launching the packaged binary and checking it is alive after three seconds** catches a build that links but cannot start, such as a missing framework.
- **Use `ditto -c -k --keepParent` to zip an app bundle**, not `zip`, so permissions, symlinks and extended attributes survive.

## What to carry forward

- Phase 1's release pipeline replaces the ad hoc signature with Developer ID signing and notarization. `scripts/check-package.sh` then needs the opposite expectations for release builds: a team identifier, and `spctl --assess` passing.
- When the version starts to matter, set `MARKETING_VERSION` from a tag instead of the fixed `0.0.1` in `project.yml`.

## The clean-clone test caught a regression

`make clean-clone` passed in step 2 and failed in step 12. Tests added in steps 8 and 11 copied the repository with `git ls-files`, which lists nothing in a copy that is not a git checkout, so they ran against an empty tree. In the governance test that made every "must fail" case pass for the wrong reason.

- `scripts/copy-source-tree.sh` now does the copying for all three tests, and falls back to a plain copy without build folders when there is no git index.
- Run `make clean-clone` before the last commit of every phase. CI cannot catch this, because its checkout is always a git repository.
