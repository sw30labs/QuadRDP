# ADR-0009: Fail closed on a corrupt or invalid profiles.json and never overwrite it

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

A hand-edited or damaged `profiles.json` could otherwise be silently replaced by defaults, losing the user's configuration.

## Decision

`QDLoadProfiles` validates that the file is an array of exactly four dictionaries with typed fields, unique non-empty ids, and valid host/port/resolution for configured entries. On any failure it returns four empty profiles plus an error, the app shows the error, and `editProfile:` refuses to save until the file is fixed and the app relaunched. Profile input is also validated live in the editor (`QDFormValidation`): no URL prefixes, paths, spaces, port 1–65535, resolution 640×480 to 3840×2160, username required.

## Consequences

### Positive

- The user's original file is preserved (tested: a `{broken` file is unchanged after load).

### Negative

- A single bad entry blocks editing of all four profiles until the file is fixed by hand.

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- Repairing or dropping only the bad entry: not evidenced as considered.

## Evidence

- Sources/QDProfile.m (QDLoadProfiles, validationError)
- Sources/QDApp.m (profileLoadFailed, editProfile:, QDFormValidation)
- Tests/Tests.m (corrupt-file case)
- commit addc0be
