# ADR-0005: Keep passwords in macOS Keychain and store profiles as owner-only JSON without secrets

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

Four Windows accounts need stored credentials so "Connect all" can be one click, and connection settings must persist between launches.

## Decision

Profiles (id, name, host, port, username, domain, resolution, NLA flag) are written to `~/Library/Application Support/QuadRDP/profiles.json` with the directory at 0700 and the file at 0600, atomically and with sorted keys (`QDSaveProfiles`). Passwords go only into the Keychain as generic-password items under service `local.quadrdp.password`, accessible `WhenUnlockedThisDeviceOnly` (`savePassword:error:`). The Keychain account is a JSON array of profile id, lower-cased host, port, domain and username, so changing any of those uses a different entry. Saving the password is opt-in in the connect prompt; an empty password field in the editor keeps the existing one, and a checkbox removes it. `QUADRDP_DATA_DIR` overrides the data directory for development and tests but not the Keychain service.

## Consequences

### Positive

- No secrets on disk in plain files; tests assert that `profiles.json` never contains the word "password" and has mode 0600.
- Credentials do not sync or migrate to other devices (ThisDeviceOnly).
- Identity-scoped Keychain entries prevent a password being sent to a different host after a profile edit.

### Negative

- Editing host/port/user leaves the old Keychain item behind (orphaned entries); nothing cleans them up.
- Real Keychain permission prompts are not covered by automated tests (README: still needs end-to-end verification).

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- Storing passwords in the profile file or an encrypted file: not evidenced as considered.
- Using FreeRDP's own credential handling: not used; credentials are passed into settings before connect.

## Evidence

- Sources/QDProfile.m (QDDataDirectory, keychainQuery, password:, savePassword:error:, QDSaveProfiles)
- Sources/QDApp.m (connectTile:, editProfile:)
- README.md ("Where things live")
- Tests/Tests.m (ModelAndInputTests)
- .gitignore (profiles.json, *.pem, *.key, .env)
- commit addc0be
