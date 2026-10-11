# Security Policy

Cairn reads, moves and deletes your files, so security and data-loss bugs are treated as the highest priority.

## Supported versions

Cairn has no released builds yet. Once releases begin, only the latest release receives security fixes.

## Reporting a vulnerability

Do not open a public issue for a security problem.

Use GitHub's **Report a vulnerability** button under the repository's Security tab. The report is private.

Include the Cairn version or commit, your macOS version, the steps to reproduce, and what an attacker could do.

## What to expect

- An acknowledgement within 7 days.
- A fix or a mitigation plan before any public disclosure.
- Credit in the release notes, unless you ask not to be named.

## In scope

- Data loss or corruption in copy, move, trash, rename or undo.
- Writing outside the chosen destination, for example through a crafted archive entry or symlink.
- Privilege escalation, especially through any privileged helper.
- A tampered or unsigned update being accepted.
- Any network request other than the update check, or any data leaving the Mac.
