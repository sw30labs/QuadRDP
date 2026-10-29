# Architecture Decision Records

Retrospective ADRs for QuadRDP, written on 2026-10-29 from `main` at `addc0be69f6a20b1570c3353270418789a449994` (the repository's only commit, 2026-10-11). Each record cites the files it is based on. Where the reason for a decision is not written down in the repo, the ADR says so and the gap is logged in [`../assumptions.md`](../assumptions.md).

Format: Title; Status; Context; Decision; Consequences (positive/negative); Alternatives considered; Evidence.

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-native-appkit-objective-c-on-freerdp3.md) | Build a native AppKit app in Objective-C on top of FreeRDP 3 | Accepted (retrospective) |
| [0002](0002-fixed-four-session-2x2-workspace.md) | Fix the workspace at exactly four sessions in a 2 × 2 grid with an expand view | Accepted (retrospective) |
| [0003](0003-per-session-worker-thread-and-latest-frame-rendering.md) | Run one FreeRDP instance per session on its own worker, and render only the latest frame at 30 Hz | Accepted (retrospective) |
| [0004](0004-software-gdi-minimal-channels.md) | Use FreeRDP's software GDI path with a minimal feature set (no GFX/H.264, audio, clipboard or redirection) | Accepted (retrospective) |
| [0005](0005-keychain-credentials-and-password-free-profiles.md) | Keep passwords in macOS Keychain and store profiles as owner-only JSON without secrets | Accepted (retrospective) |
| [0006](0006-explicit-certificate-trust-and-nla-default.md) | Require an explicit user decision for every unknown or changed server certificate, default to NLA, and never allow legacy RDP security | Accepted (retrospective) |
| [0007](0007-mac-to-windows-input-mapping.md) | Map Mac keys to RDP scancodes with a fixed US layout and route input only to the focused tile | Accepted (retrospective) |
| [0008](0008-manual-connect-no-auto-reconnect.md) | Connect only on explicit user action; no auto-connect on launch and no auto-reconnect | Accepted (retrospective) |
| [0009](0009-fail-closed-profile-loading.md) | Fail closed on a corrupt or invalid profiles.json and never overwrite it | Accepted (retrospective) |
| [0010](0010-local-source-build-adhoc-signed.md) | Ship as a local source build linked to Homebrew FreeRDP, ad-hoc signed, targeting the current macOS major | Accepted (retrospective) |
| [0011](0011-in-process-rdp-peer-test-harness.md) | Test against real in-process FreeRDP server peers over socket pairs, with no network, credentials or Keychain | Accepted (retrospective) |
| [0012](0012-generated-screenshots-and-icon.md) | Generate documentation screenshots from the production views with example profiles, and draw the app icon in code | Accepted (retrospective) |
