---
title: Architecture records notes
date: 2026-10-09
step: Phase 0 step 11
tags: [docs, adr, scripts]
---

# Architecture records notes

## What we learned

- **A test that copies the repository must copy only tracked and unignored files.** `scripts/test-check-governance.sh` used `tar --exclude .git`, which was instant in step 1 and took minutes by step 11, once `build/` held several gigabytes. `git ls-files -co --exclude-standard` gives the right file list.
- **Decision records are checkable.** Requiring a status line and the Decision and Consequences headings, and a link from `ARCHITECTURE.md`, keeps a new record from being half written or orphaned.

## What to carry forward

- A new decision gets the next number in `docs/adr`, a link in `ARCHITECTURE.md` and, when it replaces an old one, `Status: Superseded` on the old record.
- When a rule in `ARCHITECTURE.md`'s "Rules the code enforces on itself" table changes, change the check that enforces it in the same commit.
