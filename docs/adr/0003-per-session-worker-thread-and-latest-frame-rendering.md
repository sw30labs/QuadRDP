# ADR-0003: Run one FreeRDP instance per session on its own worker, and render only the latest frame at 30 Hz

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

Four live RDP connections must not block the AppKit main thread or each other, and a slow UI must not build up a backlog of frames.

## Decision

Each `QDSession` owns its own `freerdp` instance and runs it on a global dispatch queue (`connectProfile` dispatches `runProfile`). All protocol work happens on that worker; the main thread only reads atomic properties. Input from the UI goes into a locked byte queue that the worker drains between event waits, woken by a WinPR event (`_wake`); consecutive mouse moves are coalesced (`enqueue:`). On `EndPaint` the worker copies the GDI buffer into a single retained `QDFrame` ("One retained latest frame: the UI never accumulates a render backlog"). A 30 Hz `NSTimer` in `QDApp.m` pulls the newest frame into each visible `QDDesktopView`, which aspect-fits (letterboxes) it into the tile.

## Consequences

### Positive

- Sessions are isolated: a stalled handshake on one tile does not freeze the others (tested by the stalled-handshake cancellation case in `Tests/Tests.m`).
- Bounded memory per session; no frame queue.
- Mouse-move coalescing limits input traffic.

### Negative

- Full-frame copy on every paint and a fixed 30 Hz poll cost CPU even when little changes.
- Intermediate frames are dropped by design, so fast animations can look choppy.
- Shared state relies on atomic properties and two locks; correctness depends on discipline rather than a single-threaded model.

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- Rendering on every FreeRDP paint callback via the main queue: not evidenced as considered; the code comment states the backlog concern.
- One shared FreeRDP event loop for all four sessions: not evidenced as considered.

## Evidence

- Sources/QDSession.m (connectProfile, enqueue, drainInputs, capture, runProfile)
- Sources/QDDesktopView.m (refresh, drawRect, QDAspectFit)
- Sources/QDApp.m (30 Hz timer)
- README.md ("Under the hood")
- `Tests/Tests.m`
- commit addc0be
