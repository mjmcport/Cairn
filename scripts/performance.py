#!/usr/bin/env python3
"""Turns XCTest performance output into JSON and compares it with a baseline.

    performance.py parse LOG [LOG ...] --output latest.json
    performance.py compare BASELINE LATEST [--threshold 0.25] [--strict]
                           [--targets TARGETS]

`parse` reads the "measured [...] average:" lines that XCTest prints for each
`measure` block. `compare` prints a table and reports every test that is
slower than the baseline by more than the threshold. It exits 1 on a
regression only with --strict; CI reports regressions without blocking.

With --targets, `compare` also judges each target in the file: a test, the
metric it must have been measured with, and the most its average may be. A
target that was missed, not measured, or measured with another metric exits
1, with or without --strict. Like regressions, targets are judged only on
the Mac the baseline was recorded on.
"""

import argparse
import json
import platform
import re
import subprocess
import sys
from datetime import datetime, timezone

MEASURED = re.compile(
    r"Test Case '-\[(?P<module>\w+)\.(?P<suite>\w+) (?P<test>\w+)\]' measured "
    r"\[(?P<metric>[^\]]+), (?P<unit>[^\],]+)\] average: (?P<average>[0-9.]+), "
    r"relative standard deviation: (?P<rsd>[0-9.]+)%, values: \[(?P<values>[^\]]*)\]"
)


def parse_log(text):
    """Returns {"Suite.test": {...}} for every measured line in `text`."""
    results = {}
    for match in MEASURED.finditer(text):
        values = [float(v) for v in match["values"].split(",") if v.strip()]
        results[f"{match['suite']}.{match['test']}"] = {
            "metric": match["metric"],
            "unit": match["unit"],
            "average": float(match["average"]),
            "relativeStandardDeviationPercent": float(match["rsd"]),
            "values": values,
        }
    return results


def sysctl(name):
    try:
        return subprocess.run(
            ["sysctl", "-n", name], capture_output=True, text=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def machine():
    memory = sysctl("hw.memsize")
    return {
        "model": sysctl("hw.model"),
        "chip": sysctl("machdep.cpu.brand_string"),
        "cores": sysctl("hw.ncpu"),
        "memoryGB": round(int(memory) / 2**30) if memory.isdigit() else "unknown",
        "macOS": platform.mac_ver()[0],
    }


def command_parse(arguments):
    results = {}
    for path in arguments.logs:
        with open(path, errors="replace") as log:
            results.update(parse_log(log.read()))
    if not results:
        print("No performance measurements found in the logs", file=sys.stderr)
        return 1
    document = {
        "recorded": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "machine": machine(),
        "results": dict(sorted(results.items())),
    }
    with open(arguments.output, "w") as output:
        json.dump(document, output, indent=2)
        output.write("\n")
    print(f"Wrote {len(results)} measurements to {arguments.output}")
    return 0


def compare(baseline, latest, threshold):
    """Returns (rows, regressions, missing). A row is (name, base, new, change)."""
    rows, regressions, missing = [], [], []
    for name, base in baseline["results"].items():
        new = latest["results"].get(name)
        if new is None:
            missing.append(name)
            continue
        change = (new["average"] - base["average"]) / base["average"] if base["average"] else 0.0
        rows.append((name, base["average"], new["average"], change))
        if change > threshold:
            regressions.append(name)
    added = [name for name in latest["results"] if name not in baseline["results"]]
    return rows, regressions, missing, added


TARGET_KEYS = ("test", "metric", "unit", "maximum", "source")


def load_targets(path):
    """Returns the targets in the file at `path`. Raises ValueError for a file
    that names no target or leaves a target incomplete: a file that judges
    nothing must not look like a file whose targets were all met."""
    with open(path) as file:
        targets = json.load(file).get("targets")
    if not targets:
        raise ValueError(f"{path} names no target")
    for target in targets:
        absent = [key for key in TARGET_KEYS if key not in target]
        if absent:
            raise ValueError(f"{path}: a target has no {', '.join(absent)}")
    return targets


def judge_targets(targets, latest, judged):
    """Returns (lines, failures): one line per target and how many failed.

    `judged` is whether this Mac is the one the targets were set for. On any
    other Mac every line ends "not judged" and nothing fails."""
    lines, failures = [], 0
    for target in targets:
        name, limit = target["test"], f"{target['maximum']:.3f}{target['unit']}"
        result = latest["results"].get(name)
        if result is None:
            measured, verdict = "was not measured", "TARGET NOT MEASURED"
        elif (result["metric"], result["unit"]) != (target["metric"], target["unit"]):
            measured = (
                f"was measured as {result['metric']} in {result['unit']}, "
                f"not as {target['metric']} in {target['unit']}"
            )
            verdict = "TARGET NOT MEASURED"
        else:
            slowest = max(result["values"] + [result["average"]])
            measured = (
                f"{target['metric']} average {result['average']:.3f}{result['unit']}, "
                f"slowest {slowest:.3f}{result['unit']}"
            )
            verdict = "target met" if result["average"] <= target["maximum"] else "TARGET MISSED"
        if not judged:
            verdict = "not judged"
        elif verdict != "target met":
            failures += 1
        lines.append(f"{name} {measured}, limit {limit} ({target['source']}): {verdict}")
    return lines, failures


def command_compare(arguments):
    with open(arguments.baseline) as file:
        baseline = json.load(file)
    with open(arguments.latest) as file:
        latest = json.load(file)
    targets = []
    if arguments.targets:
        try:
            targets = load_targets(arguments.targets)
        except ValueError as error:
            print(error, file=sys.stderr)
            return 1
    rows, regressions, missing, added = compare(baseline, latest, arguments.threshold)

    # Times from a different Mac say nothing about the code, so they are shown
    # but never called a regression.
    base_model = baseline["machine"].get("model")
    latest_model = latest["machine"].get("model")
    comparable = base_model == latest_model
    if not comparable:
        regressions = []

    width = max([len(row[0]) for row in rows] + [4])
    print(f"{'Test':<{width}}  {'Baseline':>10}  {'Latest':>10}  {'Change':>8}")
    for name, base, new, change in rows:
        flag = "  REGRESSION" if name in regressions else ""
        print(f"{name:<{width}}  {base:>9.3f}s  {new:>9.3f}s  {change:>+7.1%}{flag}")
    for name in missing:
        print(f"MISSING: {name} is in the baseline but was not measured")
    for name in added:
        print(f"NEW: {name} has no baseline yet")

    target_lines, missed_targets = judge_targets(targets, latest, judged=comparable)
    for line in target_lines:
        print(f"Target: {line}")

    if not comparable:
        print(
            f"note: the baseline was recorded on {base_model} and this run on {latest_model}, "
            "so the times are shown for information and not judged"
        )
    status = 1 if missed_targets else 0
    if missed_targets:
        print(f"{missed_targets} target(s) not met")
    if regressions or missing:
        print(
            f"{len(regressions)} regression(s) beyond {arguments.threshold:.0%}, "
            f"{len(missing)} missing measurement(s)"
        )
        return 1 if arguments.strict else status
    if comparable:
        print("No performance regression")
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)

    parse = commands.add_parser("parse")
    parse.add_argument("logs", nargs="+")
    parse.add_argument("--output", required=True)
    parse.set_defaults(run=command_parse)

    comparison = commands.add_parser("compare")
    comparison.add_argument("baseline")
    comparison.add_argument("latest")
    comparison.add_argument("--threshold", type=float, default=0.25)
    comparison.add_argument("--strict", action="store_true")
    comparison.add_argument("--targets")
    comparison.set_defaults(run=command_compare)

    arguments = parser.parse_args()
    return arguments.run(arguments)


if __name__ == "__main__":
    sys.exit(main())
