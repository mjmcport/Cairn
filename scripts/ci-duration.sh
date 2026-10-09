#!/bin/sh
# Prints how long a CI job ran and what it cost. GitHub bills whole minutes,
# rounded up, and counts a macOS minute on a private repository ten times.
# The same line is appended to the run summary when GITHUB_STEP_SUMMARY is set.
#
# Usage: ci-duration.sh [--weekly] START [END]
# START and END are seconds since the epoch; END defaults to now. The job's
# first step records START, so the runner's own setup before it is not counted.
#
# --weekly is for a workflow that runs once a week. It adds what such a run
# costs in a month, and a warning annotation when that passes the limit.

macos_rate=10
# The most a weekly workflow may cost in billed minutes a month before the
# user is told. Documented in CONTRIBUTING.md.
weekly_limit=300

weekly=0
if [ "${1:-}" = "--weekly" ]; then
    weekly=1
    shift
fi

start="${1:-}"
end="${2:-$(date +%s)}"
case "$start" in
    '' | *[!0-9]*)
        echo "ci-duration: the start time is missing or not a number: '$start'" >&2
        exit 1
        ;;
esac
case "$end" in
    '' | *[!0-9]*)
        echo "ci-duration: the end time is not a number: '$end'" >&2
        exit 1
        ;;
esac
if [ "$end" -lt "$start" ]; then
    echo "ci-duration: the start time $start is after the end time $end" >&2
    exit 1
fi

elapsed=$((end - start))
minutes=$(((elapsed + 59) / 60))
line="Run duration: $((elapsed / 60)) min $((elapsed % 60)) s, $((minutes * macos_rate)) billed minutes ($minutes at the macOS rate of $macos_rate)"

echo "$line"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    # A blank line first, so the line does not join the paragraph above it.
    printf '\n%s\n' "$line" >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$weekly" -eq 1 ]; then
    # 52 runs a year over 12 months.
    monthly=$((minutes * macos_rate * 52 / 12))
    projection="Run weekly, that is about $monthly billed minutes a month (limit: about $weekly_limit)"
    echo "$projection"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        printf '\n%s\n' "$projection" >> "$GITHUB_STEP_SUMMARY"
    fi
    if [ "$monthly" -gt "$weekly_limit" ]; then
        echo "::warning title=Weekly run over budget::This run took $((elapsed / 60)) min $((elapsed % 60)) s, about $monthly billed minutes a month against a limit of about $weekly_limit. Tell the user; do not drop a test to make it cheaper."
    fi
fi
