# chore: Phase 0 step 8, formatting

Date: 2026-10-09

Settle code style once, by tool, so reviews are about behavior.

## Acceptance criteria

- [x] `.swift-format` committed: two-space indentation, 100-column lines, ordered imports, `try!` forbidden
- [x] `make lint` runs `swift-format lint --strict` with that configuration and fails on any finding
- [x] `make format` reformats every Swift file in place
- [x] `.githooks/pre-commit` refuses a commit whose staged Swift is unformatted or that breaks a governance rule
- [x] `make bootstrap` enables the hook by setting `core.hooksPath`
- [x] The existing code passes strict lint

## Tests

- [x] `scripts/test-pre-commit.sh`, in a throwaway repository: the repository as it stands commits; formatted Swift commits; unformatted Swift is refused; the staged content is what is checked, even when the working copy has been fixed; non-Swift files are ignored; removing a governance file is refused

## Design notes

- The formatter is the swift-format that ships with Xcode, so there is nothing to install and its version is pinned by `.xcode-version`.
- The hook checks staged content with `git show :file`, not files on disk.
- CI runs `make lint` from step 9, which is what blocks unformatted code in a pull request. The hook is the fast local check.

## References

- Claude Doc "Mac file manager implementation plan", Phase 0 step 8
