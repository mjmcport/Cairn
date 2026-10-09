#!/bin/sh
# Checks that this Mac can build Cairn and installs XcodeGen if it is missing.
# Reports every problem with the command that fixes it, then exits non-zero if
# there was one.
#
# Environment:
#   DEVELOPER_DIR   the Xcode to use (default /Applications/Xcode.app/Contents/Developer)
#   CAIRN_ARCH      overrides the detected CPU architecture (used by the tests)
#   CAIRN_SKIP_INSTALL=1  report a missing XcodeGen instead of installing it

root="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
pinned="$(cat "$root/.xcode-version")"
problems=0

problem() {
    echo "PROBLEM: $1" >&2
    [ -n "${2:-}" ] && echo "    fix: $2" >&2
    problems=$((problems + 1))
}

arch="${CAIRN_ARCH:-$(uname -m)}"
if [ "$arch" != "arm64" ]; then
    problem "Cairn builds on Apple Silicon only; this Mac is $arch"
fi

if [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
    problem "No Xcode at $DEVELOPER_DIR" \
        "install Xcode $pinned, or set DEVELOPER_DIR to its Contents/Developer folder"
else
    found="$("$DEVELOPER_DIR/usr/bin/xcodebuild" -version 2>/dev/null | awk '/^Xcode /{print $2; exit}')"
    if [ "${found%%.*}" != "${pinned%%.*}" ]; then
        problem "Xcode $found found, but .xcode-version pins $pinned" "install Xcode $pinned"
    elif [ "$found" != "$pinned" ]; then
        echo "note: Xcode $found found; .xcode-version pins $pinned. Continuing." >&2
    fi

    if ! "$DEVELOPER_DIR/usr/bin/xcodebuild" -license check >/dev/null 2>&1; then
        problem "The Xcode license has not been accepted" "sudo xcodebuild -license"
    fi

    if ! "$DEVELOPER_DIR/usr/bin/xcodebuild" -checkFirstLaunchStatus >/dev/null 2>&1; then
        problem "Xcode has not installed its system components" "xcodebuild -runFirstLaunch"
    fi
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    if [ "${CAIRN_SKIP_INSTALL:-0}" = "1" ]; then
        problem "XcodeGen is not installed" "brew install xcodegen"
    elif command -v brew >/dev/null 2>&1; then
        echo "Installing XcodeGen with Homebrew..."
        brew install xcodegen || problem "XcodeGen failed to install" "brew install xcodegen"
    else
        problem "XcodeGen is not installed and Homebrew is missing" \
            "install Homebrew from https://brew.sh, then run: brew install xcodegen"
    fi
fi

if [ "$problems" -gt 0 ]; then
    echo "$problems problem(s) found. Fix them and run 'make bootstrap' again." >&2
    exit 1
fi
echo "Toolchain ready: Xcode ${found:-?}, $(xcodegen --version 2>/dev/null | head -1)"
