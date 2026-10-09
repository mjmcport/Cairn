#!/bin/sh
# Tests ci-duration.sh with fixed start and end times.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/ci-duration.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

ok() { echo "ok: $1"; }
not_ok() { echo "NOT OK: $1"; failed=1; }

expect() { # expect NAME START END TEXT... -- every TEXT must be in the output
    name="$1"; start="$2"; end="$3"; shift 3
    output="$(env -u GITHUB_STEP_SUMMARY "$tool" "$start" "$end" 2>&1)" || { not_ok "$name (exit $?)"; return; }
    for text in "$@"; do
        case "$output" in
            *"$text"*) ;;
            *) not_ok "$name (no '$text' in: $output)"; return ;;
        esac
    done
    ok "$name"
}

expect_error() { # expect_error NAME [ARGUMENT ...]
    name="$1"; shift
    output="$(env -u GITHUB_STEP_SUMMARY "$tool" "$@" 2>"$work/stderr")"
    status=$?
    # Exit 1 and a message, so a tool that is missing or crashed does not pass.
    if [ "$status" -ne 1 ]; then
        not_ok "$name (exit $status, expected 1)"
    elif [ -n "$output" ]; then
        not_ok "$name (printed: $output)"
    elif ! grep -q "start time" "$work/stderr"; then
        not_ok "$name (no message about the start time)"
    else
        ok "$name"
    fi
}

expect "333 seconds is 5 min 33 s and 60 billed minutes" 1000 1333 "5 min 33 s" "60 billed minutes"
expect "exactly 300 seconds is 5 min 0 s and 50 billed minutes" 1000 1300 "5 min 0 s" "50 billed minutes"
expect "1 second is 10 billed minutes" 1000 1001 "0 min 1 s" "10 billed minutes"

expect_error "a missing start time is an error and prints no duration"
expect_error "an empty start time is an error and prints no duration" "" 1300
expect_error "a non-numeric start time is an error and prints no duration" yesterday 1300

printed="$(GITHUB_STEP_SUMMARY="$work/summary.md" "$tool" 1000 1333)"
[ -n "$printed" ] && grep -Fxq -- "$printed" "$work/summary.md" \
    && ok "the printed line is appended to the run summary" \
    || not_ok "the printed line is appended to the run summary"

exit "$failed"
