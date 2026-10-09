#!/bin/sh
# Proves that a clean clone builds with one command: copies every file git
# would track (committed or not, ignoring ignored files) to a temporary folder
# and runs `make all` there.

set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

(cd "$repo" && git ls-files -co --exclude-standard -z | xargs -0 tar -cf -) | (cd "$work" && tar -xf -)

if [ -e "$work/Cairn.xcodeproj" ] || [ -e "$work/build" ]; then
    echo "FAIL: the clean copy contains generated files" >&2
    exit 1
fi

(cd "$work" && make all)
echo "Clean clone built and passed its tests with one command"
