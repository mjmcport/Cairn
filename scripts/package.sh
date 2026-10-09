#!/bin/sh
# Zips the Release build of Cairn.app for download from CI.
#
# The build is signed ad hoc ("sign to run locally"), which Apple Silicon
# requires to run at all. It has no Developer ID and is not notarized, so
# Gatekeeper will refuse it on another Mac unless the user overrides that.
# Developer ID signing and notarization arrive in Phase 1.
#
# Usage: package.sh APP_PATH OUTPUT_DIRECTORY
# Prints the path of the zip it wrote.

set -eu
app="$1"
output="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"

[ -d "$app" ] || { echo "No app at $app; run 'make package'" >&2; exit 1; }

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
commit="$(git -C "$root" rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$root" status --porcelain 2>/dev/null)" ]; then
    commit="$commit-dirty"
fi

mkdir -p "$output"
zip="$output/Cairn-$version-$commit-unsigned.zip"
rm -f "$zip"
# ditto keeps the bundle's symlinks, permissions and extended attributes.
ditto -c -k --keepParent "$app" "$zip"
echo "$zip"
