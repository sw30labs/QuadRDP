# ADR-0004: Use FreeRDP's software GDI path with a minimal feature set (no GFX/H.264, audio, clipboard or redirection)

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

FreeRDP offers many codecs and virtual channels. The app's first version is scoped to seeing and driving four desktops.

## Decision

Connection settings in `runProfile` enable `SoftwareGdi` and `NSCodec`, and disable `SupportGraphicsPipeline` (GFX/H.264), `RemoteFxCodec`, `AudioPlayback` and `NetworkAutoDetect`; colour depth is fixed at 32 bpp and the TCP connect timeout at 10 s. Clipboard, audio, drive redirection, RD Gateway, smart cards, Entra web auth, IME/alternate layouts, auto-reconnect and dynamic resolution are explicitly out of scope (README "Current scope", About box in `QDApp.m`). Remote cursors are supported through FreeRDP pointer callbacks.

## Consequences

### Positive

- Small attack surface and code size: no clipboard or drive channels that could move data between the Mac and remote hosts.
- Predictable rendering path that maps directly to a BGRA buffer for `CGImage`.

### Negative

- Higher bandwidth and CPU than the GFX/H.264 pipeline, especially at 4K (3840 × 2160 is allowed).
- No copy/paste between Mac and remote desktops; README tells users to use Ctrl+C/V inside the remote desktop only.
- Servers that require RD Gateway or web authentication cannot be reached.

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- Enabling the H.264 graphics pipeline: README notes it "is not enabled" without giving a reason; the why is inferred (A-003).
- Clipboard sync: listed as not implemented; whether it was excluded for security or deferred for effort is not stated (A-004).

## Evidence

- Sources/QDSession.m (runProfile settings block, PointerSet/PointerDefault/PointerNull)
- README.md ("Current scope")
- Sources/QDApp.m (about:)
- commit addc0be
