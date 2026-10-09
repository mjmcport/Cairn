## What this changes

<!-- One or two sentences. Name the phase and step if this is plan work. -->

## How it was tested

<!-- List the tests added or changed, and anything you checked by hand. -->

## Checklist

- [ ] Tests ship in this pull request (unit, plus end-to-end if the app's interface changed)
- [ ] `make test` and `make uitest` pass locally
- [ ] No code copied or adapted from GPL or closed-source projects
- [ ] No new dependency, or its licence (MIT, BSD, Apache-2.0 or zlib) is named above
- [ ] No file-system call on the main thread
- [ ] New controls have an accessibility label and identifier
- [ ] No telemetry and no new networking code
- [ ] APIs newer than macOS 15 sit behind `#available` with a fallback
