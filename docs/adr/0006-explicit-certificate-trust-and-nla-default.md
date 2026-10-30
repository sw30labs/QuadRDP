# ADR-0006: Require an explicit user decision for every unknown or changed server certificate, default to NLA, and never allow legacy RDP security

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

RDP servers commonly present self-signed certificates. Silently accepting them would expose the connection (and the NLA credentials) to interception.

## Decision

`IgnoreCertificate` and `AutoAcceptCertificate` are off. FreeRDP's `VerifyCertificateEx`/`VerifyChangedCertificateEx` callbacks show host, subject, issuer and fingerprint in a sheet with Cancel, Connect Once and Trust Certificate (returns 0/2/1). Trusted certificates are stored by FreeRDP under the app's `freerdp/` config directory (0700). A changed certificate is shown as a critical alert with old and new fingerprints and needs a fresh decision. The worker blocks on a semaphore while the prompt is open and aborts if the session is cancelled. New profiles default to NLA; the only alternative is TLS-only; standard RDP security is always disabled. When the server asks for credentials again, `Authenticate` returns FALSE instead of prompting, so a wrong password fails the connection and the user edits the profile.

## Consequences

### Positive

- Matches a security-reviewer posture: no trust-on-first-use without a human looking at the fingerprint.
- Behaviour is covered by tests: reject, connect-once, remembered trust (no second prompt), changed-certificate rejection, and cancellation during an unanswered prompt.

### Negative

- "Connect all" can open up to four certificate prompts in sequence on first use; prompts are queued (`present:session:completion:`).
- No mid-connection credential prompt; a mistyped saved password needs a profile edit.

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- Auto-accepting certificates (FreeRDP option): explicitly set to FALSE.
- Standard RDP security for old servers: explicitly disabled; TLS-only is offered instead.

## Evidence

- Sources/QDSession.m (Verify, VerifyChanged, verify:changed:, Authenticate, settings block)
- Sources/QDSession.h (certificateRequest completion codes)
- Sources/QDApp.m (certificateRequest alert, present:session:completion:)
- Sources/QDProfile.m (emptyProfile: useNLA = YES)
- Tests/Tests.m (certificate test cases)
- README.md ("Get running" step 4)
- commit addc0be
