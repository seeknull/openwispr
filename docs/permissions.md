# Permissions

Whisp needs three macOS privacy permissions. This page documents each one,
what triggers the prompt, and how to recover if a user denied it.

## Microphone

**What:** Read audio from the system default input device.
**TCC bundle:** `kTCCServiceMicrophone`.
**System Settings pane:** Privacy & Security → Microphone.

Triggered by the first call to `AVCaptureDevice.requestAccess(for: .audio)`,
which happens when the user clicks **Request** on the Settings →
Permissions tab. On macOS this presents a standard system prompt.

If denied, the user must re-grant in System Settings (we can't re-prompt).
Whisp's Settings tab shows a red "Denied" pill and a button to open the
right pane.

## Accessibility

**What:** Post synthetic input events into the focused application
(Cmd+V for the clipboard-paste insertion mode, or per-character
keystrokes for the keystroke mode).
**TCC bundle:** `kTCCServiceAccessibility`.
**System Settings pane:** Privacy & Security → Accessibility.

Triggered by `AXIsProcessTrustedWithOptions([
kAXTrustedCheckOptionPrompt: true])`, which causes macOS to display a
prompt **and** open the right Settings pane. The user has to flip Whisp
on manually — macOS does not let an app toggle this itself.

After granting, **the app must usually be re-launched** for the grant
to take effect for the running process. Whisp logs a warning in
Console.app if it detects it's running without the bit set.

## Input Monitoring

**What:** Receive every key-down / key-up / flags-changed event in the
session via a CGEventTap. Whisp uses this to watch for Fn + Option.
**TCC bundle:** `kTCCServiceListenEvent`.
**System Settings pane:** Privacy & Security → Input Monitoring.

There is no API to trigger this prompt directly; macOS will show it the
first time Whisp calls `CGEvent.tapCreate` and the grant is missing.
Whisp's Settings tab provides a button that opens the pane.

Whisp uses `.listenOnly` taps — we never modify or suppress events — so
the privacy ask is the lighter of the two CGEventTap permission levels.

## Why not the App Sandbox?

The App Sandbox can't grant CGEventTap or Accessibility access, so a
sandboxed Whisp would not work. Until Apple changes this (or we add a
helper XPC service architecture), Whisp ships unsandboxed. The
entitlements file (`Sources/Whisp/Resources/Whisp.entitlements`) makes
this explicit.

## Resetting permissions during development

If you need to re-test the onboarding flow:

```bash
# Reset just Whisp's grants (replace ai.whisp.app with your bundle id)
tccutil reset Microphone ai.whisp.app
tccutil reset Accessibility ai.whisp.app
tccutil reset ListenEvent ai.whisp.app
```

Each `tccutil reset` re-arms the prompt on next launch.
