#!/bin/sh
# Tests accessibility-retries.py: summarizing one run's audit log and applying
# the retry window to it and a folder of earlier records.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
# Everything, the tool included, runs from a path with a space in it.
work="$base/with space"
mkdir -p "$work"
cp "$here/accessibility-retries.py" "$work/accessibility-retries.py"
tool="$work/accessibility-retries.py"
failed=0

ok() { echo "ok: $1"; }
not_ok() { echo "NOT OK: $1"; failed=1; }

write_log() { # write_log FILE EVENT:SCREEN ... -- one tab-separated line each
    file="$1"; shift
    : > "$file"
    for entry in "$@"; do
        printf '%s\t%s\n' "${entry%%:*}" "${entry#*:}" >> "$file"
    done
}

record() { # record FILE RUN RECORDED AUDITS RETRIES
    printf '{"run": "%s", "recorded": "%s", "audits": %s, "retries": %s, "retriedScreens": []}\n' \
        "$2" "$3" "$4" "$5" > "$1"
}

history() { rm -rf "$work/history"; mkdir -p "$work/history"; }

current() { # current RETRIES -- this run's record, newer than any history
    record "$work/record.json" "900-1" "2026-12-01T00:00:00Z" 3 "$1"
}

check() { # check -- runs the window check; sets $output and $status
    output="$(python3 "$tool" check "$work/record.json" "$work/history" 2>&1)"
    status=$?
}

# --- summarize

write_log "$work/audits.log" "audit:Populated folder" "audit:Empty folder" "audit:Unlistable folder"
output="$(python3 "$tool" summarize "$work/audits.log" --run 7-1 --output "$work/out.json" 2>&1)"
status=$?
[ "$status" -eq 0 ] && echo "$output" | grep -q "Audits run: 3" && echo "$output" | grep -q "Retries after a timeout: 0" \
    && ok "three audits and no retry are summarized" || not_ok "three audits and no retry are summarized ($status: $output)"

python3 - "$work/out.json" <<'PY' && ok "the record holds 3 audits, 0 retries and the run" || not_ok "the record holds 3 audits, 0 retries and the run"
import json, sys
record = json.load(open(sys.argv[1]))
assert record["audits"] == 3, record
assert record["retries"] == 0, record
assert record["retriedScreens"] == [], record
assert record["run"] == "7-1", record
assert record["recorded"].endswith("Z"), record
PY

write_log "$work/audits.log" "audit:Populated folder" "audit:Empty folder" "retry:Empty folder" "audit:Unlistable folder"
output="$(python3 "$tool" summarize "$work/audits.log" --run 7-1 --output "$work/out.json" 2>&1)"
status=$?
[ "$status" -eq 0 ] && echo "$output" | grep -q "Retries after a timeout: 1 (Empty folder)" \
    && ok "a retry names the screen that retried" || not_ok "a retry names the screen that retried ($status: $output)"

python3 - "$work/out.json" <<'PY' && ok "the record holds the retry and its screen" || not_ok "the record holds the retry and its screen"
import json, sys
record = json.load(open(sys.argv[1]))
assert record["audits"] == 3 and record["retries"] == 1, record
assert record["retriedScreens"] == ["Empty folder"], record
PY

output="$(python3 "$tool" summarize "$work/audits.log" 2>&1)"
[ $? -eq 0 ] && echo "$output" | grep -q "Audits run: 3" \
    && ok "summarizes without writing a record" || not_ok "summarizes without writing a record"

broken() { # broken NAME LOG -- exit 1, a message, and no record written
    rm -f "$work/none.json"
    output="$(python3 "$tool" summarize "$2" --run 7-1 --output "$work/none.json" 2>&1)"
    status=$?
    if [ "$status" -eq 1 ] && echo "$output" | grep -q "recording is broken" && [ ! -e "$work/none.json" ]; then
        ok "$1"
    else
        not_ok "$1 ($status: $output)"
    fi
}

: > "$work/empty.log"
broken "an empty log is a broken recording" "$work/empty.log"
broken "a missing log is a broken recording" "$work/no such.log"
write_log "$work/retry-only.log" "retry:Empty folder"
broken "a log with a retry but no audit is a broken recording" "$work/retry-only.log"

# --- check

history
record "$work/history/a.json" 1-1 "2026-11-01T00:00:00Z" 3 2
record "$work/history/b.json" 2-1 "2026-11-02T00:00:00Z" 3 1
current 1; check
[ "$status" -eq 1 ] && echo "$output" | grep -q "holds 4 retries" && echo "$output" | grep -q "more than 3" \
    && ok "fails when this run retried and the window then holds more than the threshold" \
    || not_ok "fails when this run retried and the window then holds more than the threshold ($status: $output)"

history
record "$work/history/a.json" 1-1 "2026-11-01T00:00:00Z" 3 2
current 1; check
[ "$status" -eq 0 ] && echo "$output" | grep -q "3 retries in the last 2 full-suite runs" \
    && ok "passes when this run retried and the window holds exactly the threshold" \
    || not_ok "passes when this run retried and the window holds exactly the threshold ($status: $output)"

history
record "$work/history/a.json" 1-1 "2026-11-01T00:00:00Z" 3 5
current 0; check
[ "$status" -eq 0 ] && echo "$output" | grep -q "Warning" && echo "$output" | grep -q "5 retries" \
    && ok "passes with a warning when this run did not retry and the count is over" \
    || not_ok "passes with a warning when this run did not retry and the count is over ($status: $output)"

# 25 earlier records, one retry each on days 1 to 25. The newest 19 are days
# 7 to 25, so the window holds 19 retries, not 25.
history
day=1
while [ "$day" -le 25 ]; do
    record "$work/history/run-$day.json" "$day-1" "$(printf '2026-11-%02dT00:00:00Z' "$day")" 3 1
    day=$((day + 1))
done
current 0; check
[ "$status" -eq 0 ] && echo "$output" | grep -q "19 retries in the last 20 full-suite runs" \
    && ok "counts only the newest 19 earlier records with the current run" \
    || not_ok "counts only the newest 19 earlier records with the current run ($status: $output)"

# The same, but the retries are all in the six oldest records, which fall out.
history
day=1
while [ "$day" -le 25 ]; do
    if [ "$day" -le 6 ]; then retries=1; else retries=0; fi
    record "$work/history/run-$day.json" "$day-1" "$(printf '2026-11-%02dT00:00:00Z' "$day")" 3 "$retries"
    day=$((day + 1))
done
current 1; check
[ "$status" -eq 0 ] && echo "$output" | grep -q "1 retry in the last 20 full-suite runs" \
    && ok "retries older than the window are not counted" \
    || not_ok "retries older than the window are not counted ($status: $output)"

history
current 1; check
[ "$status" -eq 0 ] && echo "$output" | grep -q "1 retry in the last 1 full-suite run" \
    && ok "an empty history passes with a window of 1 run" \
    || not_ok "an empty history passes with a window of 1 run ($status: $output)"

rm -rf "$work/history"
current 1; check
[ "$status" -eq 0 ] && echo "$output" | grep -q "count is unknown" \
    && ok "a history that could not be read passes and says the count is unknown" \
    || not_ok "a history that could not be read passes and says the count is unknown ($status: $output)"

history
record "$work/history/a.json" 1-1 "2026-11-01T00:00:00Z" 3 3
echo "not json" > "$work/history/damaged.json"
: > "$work/history/empty.json"
current 1; check
[ "$status" -eq 1 ] && echo "$output" | grep -q "holds 4 retries" \
    && echo "$output" | grep -q "damaged.json" && echo "$output" | grep -q "empty.json" \
    && ok "an unreadable record is skipped and named, and the rest are counted" \
    || not_ok "an unreadable record is skipped and named, and the rest are counted ($status: $output)"

# The artifact listing can include this run's own record; it is not counted twice.
history
record "$work/history/a.json" 1-1 "2026-11-01T00:00:00Z" 3 2
record "$work/history/self.json" 900-1 "2026-12-01T00:00:00Z" 3 1
current 1; check
[ "$status" -eq 0 ] && echo "$output" | grep -q "3 retries in the last 2 full-suite runs" \
    && ok "this run's own record in the history is not counted twice" \
    || not_ok "this run's own record in the history is not counted twice ($status: $output)"

output="$(python3 "$tool" check "$work/no-record.json" "$work/history" 2>&1)"
[ $? -eq 1 ] && ok "a missing record for this run fails the check" || not_ok "a missing record for this run fails the check"

# --- the documented numbers

limits="$(python3 "$tool" limits)"
window="$(echo "$limits" | sed -n 's/^window=//p')"
threshold="$(echo "$limits" | sed -n 's/^threshold=//p')"
contributing="$here/../CONTRIBUTING.md"
[ -n "$window" ] && [ -n "$threshold" ] \
    && grep -q "the $window most recent full-suite runs" "$contributing" \
    && grep -q "more than $threshold retries" "$contributing" \
    && ok "CONTRIBUTING.md states the tool's window ($window) and threshold ($threshold)" \
    || not_ok "CONTRIBUTING.md states the tool's window ($window) and threshold ($threshold)"

exit "$failed"
