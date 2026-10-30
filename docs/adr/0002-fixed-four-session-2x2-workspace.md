# ADR-0002: Fix the workspace at exactly four sessions in a 2 × 2 grid with an expand view

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

The README frames the app around four inference servers and a single "Connect all" button. The product name is QuadRDP.

## Decision

Hard-code four slots everywhere: four tiles created in `applicationDidFinishLaunching` (`QDApp.m`), a 2 × 2 layout in `QDRootView layout`, menu items ⌘1–4, and `profiles.json` that must contain exactly four entries (`QDLoadProfiles`/`QDSaveProfiles` in `QDProfile.m`). One tile can be expanded to fill the workspace (⌘Return) and the grid restored (⌘0) without reconnecting; hidden tiles keep their sessions but are not redrawn (`QDApp.m` timer only refreshes visible tiles). Fewer than four configured tiles are allowed; unconfigured tiles show "Add a computer".

## Consequences

### Positive

- Very simple model and UI: no dynamic layout, no session list management.
- Every machine has a fixed place and shortcut, matching the "control room" intent in the README.

### Negative

- A fifth machine needs code changes in several places (layout, menus, persistence validation).
- A `profiles.json` with any count other than four is rejected as invalid.

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- A variable N-session grid: not evidenced as considered.
- Separate windows per session: rejected implicitly by the one-window goal in the README.

## Evidence

- Sources/QDApp.m (QDRootView layout, installMenu, applicationDidFinishLaunching)
- Sources/QDProfile.m (QDLoadProfiles, QDSaveProfiles)
- README.md ("The workflow", "A closer look")
- Tests/Tests.m (profiles.count==4)
- commit addc0be
