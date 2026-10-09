#!/bin/sh
# Tests performance.py: parsing XCTest output and comparing with a baseline.

set -u
here="$(cd "$(dirname "$0")" && pwd)"
tool="$here/performance.py"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

ok() { echo "ok: $1"; }
not_ok() { echo "NOT OK: $1"; failed=1; }

log_line() { # log_line SUITE TEST METRIC AVERAGE
    echo "/path/File.swift:10: Test Case '-[Module.$1 $2]' measured [$3, s] average: $4, relative standard deviation: 1.500%, values: [$4, $4], performanceMetricID:x, baselineName: \"\""
}

{
    echo "Test Suite 'All tests' started"
    log_line ListingPerformanceTests testList10000 "Clock Monotonic Time" 0.050
    log_line ListingPerformanceTests testList100000 "Clock Monotonic Time" 0.500
    log_line PerformanceTests testTimeToFirstRows10000 "Duration (LoadFolder)" 0.250
} > "$work/baseline.log"

python3 "$tool" parse "$work/baseline.log" --output "$work/baseline.json" >/dev/null \
    && ok "parses a log" || not_ok "parses a log"

python3 - "$work/baseline.json" <<'PY' && ok "records average, metric, values and machine" || not_ok "records average, metric, values and machine"
import json, sys
document = json.load(open(sys.argv[1]))
results = document["results"]
assert len(results) == 3, results
assert results["ListingPerformanceTests.testList10000"]["average"] == 0.05
assert results["ListingPerformanceTests.testList10000"]["values"] == [0.05, 0.05]
assert results["PerformanceTests.testTimeToFirstRows10000"]["metric"] == "Duration (LoadFolder)"
assert document["machine"]["model"]
assert document["recorded"].endswith("Z")
PY

echo "nothing measured here" > "$work/empty.log"
python3 "$tool" parse "$work/empty.log" --output "$work/empty.json" >/dev/null 2>&1 \
    && not_ok "rejects a log with no measurements" || ok "rejects a log with no measurements"

make_latest() { # make_latest LIST10000 LIST100000 [omit-ui]
    {
        log_line ListingPerformanceTests testList10000 "Clock Monotonic Time" "$1"
        log_line ListingPerformanceTests testList100000 "Clock Monotonic Time" "$2"
        [ "${3:-}" = "omit-ui" ] || log_line PerformanceTests testTimeToFirstRows10000 "Duration (LoadFolder)" 0.250
    } > "$work/latest.log"
    python3 "$tool" parse "$work/latest.log" --output "$work/latest.json" >/dev/null
}

make_latest 0.055 0.450
python3 "$tool" compare "$work/baseline.json" "$work/latest.json" --strict >/dev/null \
    && ok "accepts a change inside the threshold" || not_ok "accepts a change inside the threshold"

make_latest 0.080 0.500
output="$(python3 "$tool" compare "$work/baseline.json" "$work/latest.json" --strict)"
[ $? -eq 1 ] && echo "$output" | grep -q "testList10000.*REGRESSION" \
    && ok "strict mode fails on a regression and names it" || not_ok "strict mode fails on a regression and names it"

python3 "$tool" compare "$work/baseline.json" "$work/latest.json" >/dev/null \
    && ok "without --strict a regression is reported, not fatal" || not_ok "without --strict a regression is reported, not fatal"

python3 "$tool" compare "$work/baseline.json" "$work/latest.json" --strict --threshold 0.70 >/dev/null \
    && ok "honours a custom threshold" || not_ok "honours a custom threshold"

make_latest 0.050 0.500 omit-ui
output="$(python3 "$tool" compare "$work/baseline.json" "$work/latest.json" --strict)"
[ $? -eq 1 ] && echo "$output" | grep -q "MISSING: PerformanceTests.testTimeToFirstRows10000" \
    && ok "reports a measurement that disappeared" || not_ok "reports a measurement that disappeared"

exit "$failed"
