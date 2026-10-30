# ADR-0012: Generate documentation screenshots from the production views with example profiles, and draw the app icon in code

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

README images must show the real UI without leaking real hostnames, accounts or desktops.

## Decision

`scripts/render-screenshots.m` `#import`s `Sources/QDApp.m` and renders the real `QDRootView`/`QDTile` views offscreen with example profiles (`inference-0N.example.com`, user `operator`) into `docs/images/quad-grid.png` and `docs/images/focus-view.png`, without connecting or loading saved profiles. `scripts/make-icon.swift` draws the icon at 16–1024 px and writes `Resources/QuadRDP.icns` itself (building the icns container by hand). README states the screenshots show the disconnected state and that no live desktops or credentials are pictured.

## Consequences

### Positive

- Screenshots stay in sync with the real UI and contain no private data.

### Negative

- Screenshots never show a connected desktop, so the README cannot illustrate a live session.
- Including `QDApp.m` directly into the renderer couples the script to private class names in that file.

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- Taking real screen captures: avoided, per the README note on what is pictured.

## Evidence

- `scripts/render-screenshots.m`
- `scripts/screenshots.sh`
- `scripts/make-icon.swift`
- README.md (screenshot note)
- `docs/images/`
- commit addc0be
