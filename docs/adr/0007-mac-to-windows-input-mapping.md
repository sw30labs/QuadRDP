# ADR-0007: Map Mac keys to RDP scancodes with a fixed US layout and route input only to the focused tile

## Status

Accepted (retrospective, inferred 2026-10-29)

## Context

Keyboard and mouse input from one Mac must reach exactly one of four Windows desktops, and modifier keys must behave like a Windows keyboard.

## Decision

`QDScanCode` maps Apple virtual key codes to RDP set-1 scancodes through a static table (0x100 marks E0-extended keys); the session advertises keyboard layout 0x0409 (US). Control maps to Ctrl, Option to Alt and Command to the Windows key; left/right modifiers are distinguished with device-specific flag masks; Caps Lock is sent as a synchronize event. The app reserves ⌘0–4, ⌘Return, ⌘, and ⌘Q; other ⌘ combinations go to the remote. Pressed keys and mouse buttons are tracked and released when a tile loses focus, the window resigns key, or the app deactivates. Mouse coordinates are converted from the letterboxed view to remote pixels and clamped (`QDRemotePoint`). Ctrl+Alt+Delete is sent from a tile button.

## Consequences

### Positive

- No stuck keys or buttons when switching tiles or apps.
- Input isolation between tiles is tested (only session 2's peer receives events).

### Negative

- Non-US layouts and IME input are not supported (README).
- Mac Cmd+C/V do not act as copy/paste on the remote; users must use Ctrl+C/V.

## Alternatives considered

The repository has a single commit and no design notes, so alternatives below are only those the code or README names; anything else is marked as not evidenced.

- Sending Unicode characters instead of scancodes: not evidenced as considered.
- Mapping Command to Ctrl for Mac-style shortcuts: not chosen; Command maps to the Windows key.

## Evidence

- Sources/QDDesktopView.m (QDScanCode, QDRemotePoint, flagsChanged:, performKeyEquivalent:, releaseInputs)
- Sources/QDSession.m (KeyboardLayout 0x0409, sendControlAltDelete, synchronizeCapsLock:)
- Sources/QDApp.m (windowDidResignKey:, applicationDidResignActive:)
- README.md ("Shortcuts")
- `Tests/Tests.m`
- commit addc0be
