# ADR-0010: Ship as a local source build linked to Homebrew FreeRDP, ad-hoc signed, targeting the current macOS major

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

Distributing a Mac app normally needs Developer ID signing, notarisation and bundled libraries.

## Decision

`scripts/build.sh` compiles with clang against Homebrew's `freerdp3` (checked with `pkg-config --atleast-version=3.0`), assembles `build/QuadRDP.app`, strips FinderInfo/ResourceFork xattrs, and signs ad-hoc (`codesign --sign -`). The deployment target defaults to the current macOS major version and is written into `LSMinimumSystemVersion`, overriding the `13.0` in `Resources/Info.plist`. `run.command` builds and opens the app. The bundle id is `local.quadrdp.app`. README states a portable distribution would need bundled libraries and Developer ID signing/notarisation and that the repo provides source builds only.

## Consequences

### Positive

- Simple, reproducible for the owner; no Apple developer account or packaging pipeline needed.

### Negative

- The built app only runs on the build Mac's macOS version or newer and depends on Homebrew libraries at their install path.
- No releases or binaries for other users; README says to rebuild after an incompatible FreeRDP upgrade.

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- Bundling FreeRDP into the app and notarising: named in README as what a portable distribution would need; not done.

## Evidence

- `scripts/build.sh`
- `run.command`
- `Resources/Info.plist`
- README.md ("Build and verify")
- commit addc0be
