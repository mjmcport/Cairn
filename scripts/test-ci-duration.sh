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

expect_weekly() { # expect_weekly NAME START END TEXT... -- as expect, with --weekly
    name="$1"; start="$2"; end="$3"; shift 3
    output="$(env -u GITHUB_STEP_SUMMARY "$tool" --weekly "$start" "$end" 2>&1)" || { not_ok "$name (exit $?)"; return; }
    for text in "$@"; do
        case "$output" in
            *"$text"*) ;;
            *) not_ok "$name (no '$text' in: $output)"; return ;;
        esac
    done
    ok "$name"
}

expect_weekly "a weekly 6-minute run projects about 260 billed minutes a month" 1000 1360 \
    "60 billed minutes" "about 260 billed minutes a month"
expect_weekly "a weekly 7-minute run projects about 303 and warns" 1000 1420 \
    "about 303 billed minutes a month" "::warning "

# Billing rounds up, so one second past 6 minutes already costs a 7th minute.
expect_weekly "a weekly run one second over 6 minutes warns" 1000 1361 \
    "about 303 billed minutes a month" "::warning "

output="$(env -u GITHUB_STEP_SUMMARY "$tool" --weekly 1000 1360 2>&1)"
case "$output" in
    *"::warning "*) not_ok "a weekly run of exactly 6 minutes does not warn (got: $output)" ;;
    *"about 260 billed minutes a month"*) ok "a weekly run of exactly 6 minutes does not warn" ;;
    *) not_ok "a weekly run of exactly 6 minutes does not warn (no projection in: $output)" ;;
esac

output="$(env -u GITHUB_STEP_SUMMARY "$tool" 1000 1420 2>&1)"
case "$output" in
    *"a month"* | *"::warning "*) not_ok "without --weekly there is no projection or warning (got: $output)" ;;
    *"70 billed minutes"*) ok "without --weekly there is no projection or warning" ;;
    *) not_ok "without --weekly there is no projection or warning (got: $output)" ;;
esac

GITHUB_STEP_SUMMARY="$work/weekly.md" "$tool" --weekly 1000 1360 >/dev/null
grep -q "about 260 billed minutes a month" "$work/weekly.md" \
    && ok "the weekly projection is written to the run summary" \
    || not_ok "the weekly projection is written to the run summary"

printed="$(GITHUB_STEP_SUMMARY="$work/summary.md" "$tool" 1000 1333)"
[ -n "$printed" ] && grep -Fxq -- "$printed" "$work/summary.md" \
    && ok "the printed line is appended to the run summary" \
    || not_ok "the printed line is appended to the run summary"

exit "$failed"
