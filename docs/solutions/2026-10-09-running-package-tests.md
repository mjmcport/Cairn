---
title: Running package tests without filling the disk
date: 2026-10-09
step: Phase 0 step 3
tags: [swiftpm, testing, disk]
---

# Running package tests without filling the disk

## What we found

- Each package's first `swift test` writes 90 to 170 MB of build output. Five packages took about 550 MB, which filled a disk that had under 1 GB free and stopped every shell command.
- When the disk is full, the compiler reports unrelated-looking errors ("plugin for module 'TestingMacros' not found", "database or disk is full"). Check `df -h` before debugging a build error that makes no sense.
- `swift test` leaves `.build/` inside each package by default.

## What we do

- `make test` passes `--scratch-path build/packages/<name>`, so all build output sits under `build/`, which `make clean` removes and `.gitignore` ignores.
- Keep at least 10 GB free before building. Xcode's DerivedData for the app adds to the package output.

## What to carry forward

- CI should cache `build/packages` between runs.
- If the package count grows, consider one workspace-level test plan so the packages share a single build folder.

## Added in step 6

- **The first `swift test` after adding source files to a dependency package can fail** with "cannot find X in scope" for the new files, when run from a package that depends on it. The second run passes. If CI shows this, clear `build/packages/<name>` for the dependent package.
- **RTK filters `make` output in Claude Code sessions.** A redirected log from `make test` is truncated. Use `rtk proxy make test` to capture the full output, and trust the exit status either way.
