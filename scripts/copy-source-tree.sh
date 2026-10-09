#!/bin/sh
# Copies the repository's source files into a folder, leaving out build
# output and git's own data. Used by tests that need a scratch copy.
#
# In a git checkout it copies the tracked and unignored files. In a plain
# copy of the sources (a downloaded archive, or the clean-clone test) there is
# no index to ask, so it copies everything except known build folders.
#
# Usage: copy-source-tree.sh DESTINATION

set -eu
destination="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$destination"

if [ "$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" = "$root" ]; then
    (cd "$root" && git ls-files -co --exclude-standard -z | xargs -0 tar -cf -) \
        | (cd "$destination" && tar -xf -)
else
    (cd "$root" && tar -cf - --exclude .git --exclude build --exclude .build \
        --exclude '*.xcodeproj' --exclude DerivedData --exclude .DS_Store .) \
        | (cd "$destination" && tar -xf -)
fi
