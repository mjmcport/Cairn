#!/bin/sh
# Prints the DEVELOPER_DIR line for CI: the Xcode pinned in .xcode-version if
# the runner has it, otherwise the newest Xcode with the same major version,
# otherwise the runner's default. Output goes to $GITHUB_ENV.
#
# With --strict there is no fallback to the default: if no Xcode of the pinned
# major version is installed, it prints nothing to stdout and exits 1. The
# macOS 15 workflow uses this, because that runner's default is an older Xcode.
#
# Set CAIRN_APPLICATIONS to look somewhere other than /Applications (tests).

strict=0
case "${1:-}" in
    '') ;;
    --strict) strict=1 ;;
    *) echo "ci-select-xcode: unknown option '$1'" >&2; exit 2 ;;
esac

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
if [ -z "$chosen" ]; then
    if [ "$strict" -eq 1 ]; then
        echo "No Xcode $major in $applications (.xcode-version pins $pinned), and --strict forbids the default Xcode" >&2
        exit 1
    fi
    chosen="$applications/Xcode.app"
fi

echo "Using $chosen (.xcode-version pins $pinned)" >&2
echo "DEVELOPER_DIR=$chosen/Contents/Developer"
