#!/usr/bin/env python3
"""Checks that every path the CI workflow ignores starts the Documents workflow.

    check-workflow-paths.py [CI_WORKFLOW DOCUMENTS_WORKFLOW]

CI starts no run for a documents-only change and leaves those files to the
Documents workflow. If CI ignored a path that Documents does not list, a
change there would be checked by nothing. Exits 1 and names the path.
"""

import os
import sys


def path_lists(workflow, key):
    """Returns the list under each `key:` in the file, one per event."""
    lists, current = [], None
    with open(workflow) as file:
        for line in file:
            stripped = line.strip()
            if stripped == f"{key}:":
                current = []
                lists.append(current)
            elif current is not None and stripped.startswith("- "):
                current.append(stripped[2:].strip().strip("\"'"))
            elif stripped and not stripped.startswith("#"):
                current = None
    return lists


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    ci = os.path.join(root, ".github/workflows/ci.yml")
    documents = os.path.join(root, ".github/workflows/documents.yml")
    if len(sys.argv) == 3:
        ci, documents = sys.argv[1], sys.argv[2]
    try:
        ignored = path_lists(ci, "paths-ignore")
        checked = path_lists(documents, "paths")
    except OSError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    failures = []
    if len(ignored) != 2 or not all(ignored):
        failures.append(f"{ci} should ignore paths for push and for pull_request")
    if len(checked) != 2 or not all(checked):
        failures.append(f"{documents} should list paths for push and for pull_request")
    if not failures:
        for event, (skip, run) in enumerate(zip(ignored, checked)):
            for path in skip:
                if path not in run:
                    failures.append(
                        f"CI ignores '{path}' but the Documents workflow does not list it "
                        f"(event {event + 1}): a change there would be checked by nothing"
                    )
    for failure in failures:
        print(f"FAIL: {failure}", file=sys.stderr)
    if failures:
        return 1
    print("Every path CI ignores starts the Documents workflow")
    return 0


if __name__ == "__main__":
    sys.exit(main())
