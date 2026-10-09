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
- **Xcode had never been launched.** After the licence was accepted, `xcodebuild` still failed with "failed to load a required plug-in" (CoreSimulator missing). `xcodebuild -runFirstLaunch` fixed it and did not need `sudo`.
- **The Command Line Tools cannot run Swift Testing here.** `swift test` under the Command Line Tools compiled the packages, then failed to load `Testing.framework` or to find the `TestingMacros` plugin. Use Xcode's toolchain for every test run.
- **XcodeGen was missing.** `brew install xcodegen` installed 2.46.0.
- **The compound engineering plugin renamed its commands.** Version 2.11.0 used `/workflows:plan`, `/workflows:work`, `/workflows:review` and `/workflows:compound`. Version 3.30.4 uses `/ce-plan`, `/ce-work`, `/ce-code-review` and `/ce-compound`. A plugin update applies only after Claude Code restarts.

## Fix

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license
xcodebuild -runFirstLaunch
brew install xcodegen
```

## What to carry forward

- `make bootstrap` (step 2) checks each of these conditions and prints the exact command for each one that fails, instead of letting `xcodebuild` fail with a vaguer message.
- The Makefile does not depend on `xcode-select`. Setting `DEVELOPER_DIR` from a pinned Xcode path keeps the build working on a Mac whose selected tools are the Command Line Tools.
- A docs-only step can still have a test: `scripts/check-governance.sh` checks the files and the statements in them, and `scripts/test-check-governance.sh` proves the check fails when one is removed. CI should run both.
