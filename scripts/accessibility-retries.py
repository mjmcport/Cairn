#!/usr/bin/env python3
"""Counts accessibility-audit retries and gates on them over recent runs.

    accessibility-retries.py summarize LOG [--run ID] [--output record.json]
    accessibility-retries.py check RECORD HISTORY_FOLDER
    accessibility-retries.py limits

`summarize` reads the audit log the UI tests write (one "audit<TAB>screen" or
"retry<TAB>screen" line each), prints a Markdown summary and, with --output,
writes this run's record. A log with no audits means the recording is broken,
and exits 1.

`check` adds this run's record to the newest earlier records in
HISTORY_FOLDER and prints where the retry count stands. It exits 1 only when
this run retried and the window then holds more than THRESHOLD retries, so a
run that did not retry never fails. If HISTORY_FOLDER does not exist, the
earlier records could not be fetched: the count is unknown and the run passes.

`limits` prints the two numbers below, for the self-test that compares them
with CONTRIBUTING.md.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

# Full-suite runs counted, the current one included, and the most retries they
# may hold before a run that retries fails. Documented in CONTRIBUTING.md
# ("The accessibility audit's one retry"); change both together.
WINDOW = 20
THRESHOLD = 3


def plural(count, word, many):
    return f"{count} {word if count == 1 else many}"


def read_log(path):
    """Returns (audits, screens that retried), or None if there is no log."""
    try:
        with open(path, errors="replace") as log:
            lines = log.read().splitlines()
    except OSError:
        return None
    audits, retried = 0, []
    for line in lines:
        event, _, screen = line.partition("\t")
        if event == "audit":
            audits += 1
        elif event == "retry":
            retried.append(screen)
    return audits, retried


def command_summarize(arguments):
    counted = read_log(arguments.log)
    if counted is None or counted[0] == 0:
        print(
            f"No accessibility audit was recorded in {arguments.log}: the recording is broken. "
            "The UI tests record every audit, so a run with none cannot be trusted."
        )
        return 1
    audits, retried = counted
    print("### Accessibility audits")
    print()
    print(f"- Audits run: {audits}")
    screens = f" ({', '.join(retried)})" if retried else ""
    print(f"- Retries after a timeout: {len(retried)}{screens}")
    if arguments.output:
        record = {
            "run": arguments.run,
            "recorded": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "audits": audits,
            "retries": len(retried),
            "retriedScreens": retried,
        }
        with open(arguments.output, "w") as output:
            json.dump(record, output, indent=2)
            output.write("\n")
    return 0


def read_record(path):
    with open(path) as file:
        record = json.load(file)
    # Fail here, not later, on a record that lacks what the window needs.
    return {
        "run": str(record["run"]),
        "recorded": str(record["recorded"]),
        "retries": int(record["retries"]),
    }


def read_history(folder, current_run):
    """Returns (records newest first, names of files that could not be read)."""
    records, unreadable = [], []
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".json"):
            continue
        try:
            record = read_record(os.path.join(folder, name))
        except (OSError, ValueError, KeyError, TypeError):
            unreadable.append(name)
            continue
        # The artifact listing can include the record this run just uploaded.
        if record["run"] != current_run:
            records.append(record)
    records.sort(key=lambda record: (record["recorded"], record["run"]), reverse=True)
    return records, unreadable


def command_check(arguments):
    try:
        current = read_record(arguments.record)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Cannot read this run's record {arguments.record}: {error}")
        return 1

    if not os.path.isdir(arguments.history):
        print(
            "- Retry window: the earlier records could not be read, so the count is unknown "
            "and this run is not judged"
        )
        return 0

    earlier, unreadable = read_history(arguments.history, current["run"])
    window = [current] + earlier[: WINDOW - 1]
    retries = sum(record["retries"] for record in window)
    print(
        f"- Retry window: {plural(retries, 'retry', 'retries')} in the last "
        f"{plural(len(window), 'full-suite run', 'full-suite runs')} "
        f"(window {WINDOW}, threshold {THRESHOLD})"
    )
    for name in unreadable:
        print(f"- Skipped an earlier record that could not be read: {name}")

    if retries <= THRESHOLD:
        return 0
    if current["retries"] == 0:
        print(
            f"- Warning: the window holds {plural(retries, 'retry', 'retries')}, more than "
            f"{THRESHOLD}. This run did not retry, so it passes; the next run that retries fails"
        )
        return 0
    print()
    print(
        f"**Failed:** this run retried an audit and the window now holds "
        f"{plural(retries, 'retry', 'retries')}, more than {THRESHOLD}. Open an issue and find "
        "out why the audit times out; do not simply re-run. See CONTRIBUTING.md."
    )
    return 1


def command_limits(arguments):
    print(f"window={WINDOW}")
    print(f"threshold={THRESHOLD}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)

    summarize = commands.add_parser("summarize")
    summarize.add_argument("log")
    summarize.add_argument("--run", default="local")
    summarize.add_argument("--output")
    summarize.set_defaults(run_command=command_summarize)

    check = commands.add_parser("check")
    check.add_argument("record")
    check.add_argument("history")
    check.set_defaults(run_command=command_check)

    limits = commands.add_parser("limits")
    limits.set_defaults(run_command=command_limits)

    arguments = parser.parse_args()
    return arguments.run_command(arguments)


if __name__ == "__main__":
    sys.exit(main())
