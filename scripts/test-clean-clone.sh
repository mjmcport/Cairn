#!/bin/sh
# Proves that a clean clone builds with one command: copies the sources (no
# build output, no git data) to a temporary folder and runs `make all` there.
# The copy is not a git checkout, so this also proves the build and tests do
# not depend on one.

set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

"$repo/scripts/copy-source-tree.sh" "$work"

if [ -e "$work/Cairn.xcodeproj" ] || [ -e "$work/build" ]; then
    echo "FAIL: the clean copy contains generated files" >&2
    exit 1
fi

(cd "$work" && make all)
echo "Clean clone built and passed its tests with one command"
