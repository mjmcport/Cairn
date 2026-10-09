---
title: Formatting notes
date: 2026-10-09
step: Phase 0 step 8
tags: [swift-format, git-hooks]
---

# Formatting notes

## What we learned

- **swift-format ships with Xcode** (`xcrun swift-format`). The Command Line Tools alone do not provide a `swift-format` on the path.
- **A partial `.swift-format` is valid.** Keys that are left out take their defaults, so the file lists only the choices this project made.
- **`swift-format lint` reads standard input** when given `-`, with `--assume-filename` for messages. That lets the hook check staged content from `git show :path`.
- **Writing code in the formatter's default style from the first step** meant that turning on strict lint changed no files.
- **Hooks in `.githooks` plus `core.hooksPath`** keep the hook under version control. `core.hooksPath` is local configuration, so each clone runs `make bootstrap` once.

## What to carry forward

- Run `make format` before staging. The hook refuses the commit otherwise.
- A commit made with `--no-verify` skips the hook; CI's `make lint` still catches it.
