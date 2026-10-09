#!/bin/sh
# Prints the DEVELOPER_DIR line for CI: the Xcode pinned in .xcode-version if
# the runner has it, otherwise the newest Xcode with the same major version,
# otherwise the runner's default. Output goes to $GITHUB_ENV.
#
# Set CAIRN_APPLICATIONS to look somewhere other than /Applications (tests).

root="$(cd "$(dirname "$0")/.." && pwd)"
applications="${CAIRN_APPLICATIONS:-/Applications}"
pinned="$(cat "$root/.xcode-version")"
major="${pinned%%.*}"

if [ -d "$applications/Xcode_$pinned.app" ]; then
    chosen="$applications/Xcode_$pinned.app"
else
    # Names look like Xcode_26.1.app; sort by version and take the newest.
    chosen="$(ls -d "$applications"/Xcode_"$major"*.app 2>/dev/null | sort -t_ -k2 -V | tail -1)"
fi
[ -n "$chosen" ] || chosen="$applications/Xcode.app"

echo "Using $chosen (.xcode-version pins $pinned)" >&2
echo "DEVELOPER_DIR=$chosen/Contents/Developer"
