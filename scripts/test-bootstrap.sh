#!/bin/sh
# Tests bootstrap.sh's failure reports. These cases need no working Xcode.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
bootstrap="$here/bootstrap.sh"
failed=0

# expect_problem NAME PATTERN -- runs bootstrap with the caller's environment
expect_problem() {
    output="$(CAIRN_SKIP_INSTALL=1 "$bootstrap" 2>&1)"
    status=$?
    if [ "$status" -ne 0 ] && echo "$output" | grep -q -- "$2"; then
        echo "ok: $1"
    else
        echo "NOT OK: $1"; echo "$output" | sed 's/^/    /'; failed=1
    fi
}

export DEVELOPER_DIR=/nonexistent/Xcode.app/Contents/Developer
expect_problem "reports a missing Xcode with its fix" "No Xcode at /nonexistent"

export CAIRN_ARCH=x86_64
expect_problem "rejects an Intel Mac" "Apple Silicon only"

exit "$failed"
