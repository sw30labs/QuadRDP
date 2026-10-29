# ADR-0008: Connect only on explicit user action; no auto-connect on launch and no auto-reconnect

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

The README promises one click, not zero clicks, and states the limits of that click.

## Decision

Sessions start only from "Connect all" or a tile's Connect button. There is no connect-on-launch and no automatic reconnect; a dropped session ends in Idle or Failed with FreeRDP's last error string shown on the tile. Quitting with live sessions disconnects all of them first and replies to `applicationShouldTerminate` only after every worker has stopped.

## Consequences

### Positive

- Certificate and password prompts always appear in response to a user action.
- Clean shutdown: FreeRDP contexts are freed on the worker before the app exits.

### Negative

- After a network blip or server reboot the user must click Connect again.

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- Auto-reconnect: listed as not implemented in README "Current scope"; whether it is planned is not stated (A-005).

## Evidence

- README.md ("The one-click part" note, "Current scope")
- Sources/QDApp.m (connectAll:, applicationShouldTerminate:, timer quitting branch)
- Sources/QDSession.m (runProfile error handling, disconnect)
- commit addc0be
