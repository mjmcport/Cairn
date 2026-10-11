#!/bin/sh
# Tests performance.py: parsing XCTest output, comparing with a baseline and
# judging targets.

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
    log_line PerformanceTests testTimeToFirstRows10000 "Duration (FirstRows)" 0.250
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
assert results["PerformanceTests.testTimeToFirstRows10000"]["metric"] == "Duration (FirstRows)"
assert document["machine"]["model"]
assert document["recorded"].endswith("Z")
PY

echo "nothing measured here" > "$work/empty.log"
python3 "$tool" parse "$work/empty.log" --output "$work/empty.json" >/dev/null 2>&1 \
    && not_ok "rejects a log with no measurements" || ok "rejects a log with no measurements"

make_latest() { # make_latest LIST10000 LIST100000 [omit-ui | FIRSTROWS [METRIC]]
    {
        log_line ListingPerformanceTests testList10000 "Clock Monotonic Time" "$1"
        log_line ListingPerformanceTests testList100000 "Clock Monotonic Time" "$2"
        [ "${3:-}" = "omit-ui" ] || log_line PerformanceTests testTimeToFirstRows10000 \
            "${4:-Duration (FirstRows)}" "${3:-0.250}"
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

make_latest 0.500 5.000
python3 - "$work/latest.json" <<'PY'
import json, sys
document = json.load(open(sys.argv[1]))
document["machine"]["model"] = "SomeOtherMac1,1"
json.dump(document, open(sys.argv[1], "w"))
PY
output="$(python3 "$tool" compare "$work/baseline.json" "$work/latest.json" --strict)"
[ $? -eq 0 ] && ! echo "$output" | grep -q "REGRESSION" && echo "$output" | grep -q "not judged" \
    && ok "does not judge times from a different Mac" || not_ok "does not judge times from a different Mac"

# Targets. The file sits under a path with a space, the awkward way.
mkdir "$work/with space"
targets="$work/with space/targets.json"
write_targets() { # write_targets MAXIMUM
    cat > "$targets" <<JSON
{"targets": [{"test": "PerformanceTests.testTimeToFirstRows10000",
  "metric": "Duration (FirstRows)", "unit": "s", "maximum": $1, "source": "quality bar 4"}]}
JSON
}
write_targets 0.2
other_mac() {
    python3 - "$work/latest.json" <<'PY'
import json, sys
document = json.load(open(sys.argv[1]))
document["machine"]["model"] = "SomeOtherMac1,1"
json.dump(document, open(sys.argv[1], "w"))
PY
}
judge() { python3 "$tool" compare "$work/baseline.json" "$work/latest.json" --targets "$targets" 2>&1; }

make_latest 0.050 0.500 0.150
output="$(judge)"
[ $? -eq 0 ] && echo "$output" | grep -q "testTimeToFirstRows10000 .*average 0.150s.*limit 0.200s.*: target met" \
    && ok "a target under its limit is met, from a file under a path with a space" \
    || not_ok "a target under its limit is met, from a file under a path with a space"

make_latest 0.050 0.500 0.250
output="$(judge)"
[ $? -eq 1 ] && echo "$output" | grep -q "testTimeToFirstRows10000 .*average 0.250s.*limit 0.200s.*: TARGET MISSED" \
    && ok "a missed target fails without --strict and names the test, the time and the limit" \
    || not_ok "a missed target fails without --strict and names the test, the time and the limit"

other_mac
output="$(judge)"
[ $? -eq 0 ] && echo "$output" | grep -q "testTimeToFirstRows10000 .*average 0.250s.*limit 0.200s.*: not judged" \
    && ! echo "$output" | grep -q "TARGET" \
    && ok "a missed target is not judged on a different Mac" || not_ok "a missed target is not judged on a different Mac"

make_latest 0.050 0.500 omit-ui
output="$(judge)"
[ $? -eq 1 ] && echo "$output" | grep -q "testTimeToFirstRows10000 was not measured.*: TARGET NOT MEASURED" \
    && ok "a target that was not measured fails" || not_ok "a target that was not measured fails"

make_latest 0.050 0.500 0.150 "Duration (LoadFolder)"
output="$(judge)"
[ $? -eq 1 ] && echo "$output" | grep -q "measured as Duration (LoadFolder) in s, not as Duration (FirstRows) in s.*: TARGET NOT MEASURED" \
    && ok "a target measured from another interval fails and names both" \
    || not_ok "a target measured from another interval fails and names both"

make_latest 0.050 0.500 0.150
echo '{"targets": []}' > "$targets"
output="$(judge)"
[ $? -eq 1 ] && echo "$output" | grep -q "names no target" \
    && ok "a targets file with no targets is an error" || not_ok "a targets file with no targets is an error"

echo '{"targets": [{"test": "PerformanceTests.testTimeToFirstRows10000"}]}' > "$targets"
output="$(judge)"
[ $? -eq 1 ] && echo "$output" | grep -q "a target has no metric, unit, maximum, source" \
    && ok "a target with no limit is an error" || not_ok "a target with no limit is an error"

# The committed targets file is the one `make perf` passes.
make_latest 0.050 0.500 0.250
output="$(python3 "$tool" compare "$work/baseline.json" "$work/latest.json" --targets "$here/../docs/performance/targets.json")"
[ $? -eq 1 ] && echo "$output" | grep -q "limit 0.200s (quality bar 4): TARGET MISSED" \
    && ok "the committed targets file fails a first-rows time above 200 ms" \
    || not_ok "the committed targets file fails a first-rows time above 200 ms"
# What `make perf` would run, with its continuation lines joined.
recipe="$(cd "$here/.." && make -n perf 2>/dev/null | tr -d '\\\n' | tr -s ' \t' ' ')"
echo "$recipe" | grep -q 'performance.py compare docs/performance/baseline.json build/performance/latest.json --targets docs/performance/targets.json' \
    && ok "make perf passes the committed targets file" || not_ok "make perf passes the committed targets file"

output="$(python3 "$tool" compare "$work/baseline.json" "$work/latest.json")"
[ $? -eq 0 ] && ! echo "$output" | grep -qi "target" \
    && ok "without --targets nothing is judged against a target" || not_ok "without --targets nothing is judged against a target"

exit "$failed"
