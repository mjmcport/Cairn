#!/bin/sh
# Tests the UITEST_SUITE switch of `make uitest` without running anything:
# `make -n` prints the commands, and each suite must select the right tests.

set -u
repo="$(cd "$(dirname "$0")/.." && pwd)"
failed=0

ok() { echo "ok: $1"; }
not_ok() { echo "NOT OK: $1"; failed=1; }

# The suite comes only from the arguments: the weekly workflow sets
# UITEST_SUITE in the environment, and this test runs inside it.
plan() { env -u UITEST_SUITE make -C "$repo" -n uitest "$@" 2>&1; }

output="$(plan)"
case "$output" in
    *"-skip-testing:CairnUITests/PerformanceTests test"*) ok "with no suite named, every end-to-end test but the performance tests" ;;
    *) not_ok "with no suite named, every end-to-end test but the performance tests" ;;
esac
case "$output" in
    *"-only-testing:"*) not_ok "with no suite named, nothing is singled out" ;;
    *) ok "with no suite named, nothing is singled out" ;;
esac

output="$(plan UITEST_SUITE=full)"
case "$output" in
    *"-skip-testing:CairnUITests/PerformanceTests test"*) ok "full is the same as naming no suite" ;;
    *) not_ok "full is the same as naming no suite" ;;
esac

output="$(plan UITEST_SUITE=audits)"
case "$output" in
    *"-only-testing:CairnUITests/AccessibilityTests test"*) ok "audits runs the accessibility class alone" ;;
    *) not_ok "audits runs the accessibility class alone" ;;
esac
case "$output" in
    *"-skip-testing:"*) not_ok "audits does not also skip by name" ;;
    *) ok "audits does not also skip by name" ;;
esac
# The audit records are still collected, or the summary step would fail.
case "$output" in
    *"accessibility-retries.py extract"*) ok "audits still extracts the audit records" ;;
    *) not_ok "audits still extracts the audit records" ;;
esac

output="$(plan UITEST_SUITE=everything)"
status=$?
case "$status:$output" in
    0:*) not_ok "an unknown suite is refused" ;;
    *"must be 'full' or 'audits'"*) ok "an unknown suite is refused" ;;
    *) not_ok "an unknown suite is refused ($output)" ;;
esac

# The class the audits suite names has to exist, with the audit tests in it.
grep -q "^final class AccessibilityTests" "$repo/UITests/AccessibilityTests.swift" \
    && grep -q "func testAuditPasses" "$repo/UITests/AccessibilityTests.swift" \
    && ok "UITests/AccessibilityTests.swift holds the audit tests" \
    || not_ok "UITests/AccessibilityTests.swift holds the audit tests"

exit "$failed"
