---
title: Toolchain setup on a fresh Mac
date: 2026-10-09
step: Phase 0 step 1
tags: [toolchain, xcode, xcodegen, plugin]
---

# Toolchain setup on a fresh Mac

## What we found

- **Xcode was installed but not selected.** `xcode-select -p` pointed at `/Library/Developer/CommandLineTools`, so `xcodebuild` failed with "requires Xcode". `swift` still worked, because the Command Line Tools ship their own Swift 6.4.
- **The Xcode licence had not been accepted.** Every Xcode tool then refuses to run, including `swift` when `DEVELOPER_DIR` points at Xcode. Only `xcodebuild -version` still answers.
- **Both fixes need `sudo` and a person.** An agent cannot accept the licence.
- **XcodeGen was missing.** `brew install xcodegen` installed 2.46.0.
- **The compound engineering plugin renamed its commands.** Version 2.11.0 used `/workflows:plan`, `/workflows:work`, `/workflows:review` and `/workflows:compound`. Version 3.30.4 uses `/ce-plan`, `/ce-work`, `/ce-code-review` and `/ce-compound`. A plugin update applies only after Claude Code restarts.

## Fix

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license
brew install xcodegen
```

## What to carry forward

- `make bootstrap` (step 2) should check all three conditions and print the exact command for each one that fails, instead of letting `xcodebuild` fail with a vaguer message.
- The Makefile should not depend on `xcode-select`. Setting `DEVELOPER_DIR` from a pinned Xcode path keeps the build working on a Mac whose selected tools are the Command Line Tools.
- A docs-only step can still have a test: `scripts/check-governance.sh` checks the files and the statements in them, and `scripts/test-check-governance.sh` proves the check fails when one is removed. CI should run both.
