# ADR-0001: Build a native AppKit app in Objective-C on top of FreeRDP 3

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

QuadRDP's stated goal is one Mac window that shows four remote desktops (README, "Why I built it"). Something has to speak RDP and something has to draw a Mac UI. The repository is a single commit (addc0be) with no history of earlier attempts.

## Decision

Write the app in Objective-C with AppKit (`Sources/*.m`, `-fobjc-arc`) and link FreeRDP 3 (`freerdp3`, `freerdp-client3`, `winpr3` via `pkg-config` in `scripts/build.sh`) directly as a C library. Each session drives FreeRDP's client API itself (`freerdp_new`, `freerdp_connect`, `gdi_init` in `Sources/QDSession.m`) instead of shelling out to an RDP client. There is no Xcode project; the app bundle is assembled by hand in `scripts/build.sh`.

## Consequences

### Positive

- One small native binary; no Electron/web runtime, and FreeRDP's C API is called directly without a bridging layer.
- Full control over frames, input and certificate callbacks, which the four-tile design needs.

### Negative

- Objective-C plus raw FreeRDP structs (e.g. `context->gdi->primary->hdc->hwnd->invalid` in `QDSession.m`) couples the code to FreeRDP 3 internals; README says to rebuild after an incompatible FreeRDP upgrade.
- WinPR and CoreFoundation clash on `REFIID`, handled with a macro and diagnostic pragmas at the top of `QDSession.m` and `Tests/Tests.m`.
- No Xcode project means no IDE-managed signing, entitlements or archive flow.

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- Microsoft's Windows App / Remote Desktop client with four windows: not evidenced in the repo; the README's motivation implies it did not give a one-click, one-window view (inferred, see A-002).
- Swift instead of Objective-C: not evidenced as considered. Only the icon script is Swift (`scripts/make-icon.swift`). Why Objective-C was chosen is inferred (A-001).

## Evidence

- README.md (title block, "Under the hood")
- `scripts/build.sh`
- `Sources/QDSession.m`
- `Sources/main.m`
- commit addc0be
