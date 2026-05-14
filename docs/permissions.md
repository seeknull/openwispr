# Permissions

OpenWispr needs **two** macOS privacy permissions. This page documents each
one, what triggers the prompt, and how to recover if a user denied it.

> **Heads up:** earlier versions of OpenWispr also required Input Monitoring
> (for a `CGEventTap`-based hotkey). The current code uses
> `NSEvent.addGlobalMonitorForEvents` which only needs Accessibility,
> halving the permission surface. The Input Monitoring section is gone.

## Microphone

**What:** Read audio from the system default input device.
**TCC bundle:** `kTCCServiceMicrophone`.
**System Settings pane:** Privacy & Security → Microphone.

Triggered by the first call to `AVCaptureDevice.requestAccess(for: .audio)`,
which happens when the user clicks **Request** on the Settings →
Permissions tab. macOS presents a standard system prompt.

The grant flows through to the running process immediately — no restart
needed. If denied, the user re-grants in System Settings; OpenWispr's
Settings tab shows a red "Denied" pill and a button to open the right
pane.

## Accessibility

**What:** Two related capabilities, both gated by this one grant:

1. **Post synthetic input events** into the focused application
   (`Cmd+V` for clipboard-paste insertion, per-character keystrokes for
   keystroke mode).
2. **Observe modifier keys globally** via
   `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`. This is
   how OpenWispr watches for the Fn+Option hotkey.

**TCC bundle:** `kTCCServiceAccessibility`.
**System Settings pane:** Privacy & Security → Accessibility.

Triggered by `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`,
which causes macOS to display a prompt **and** open the Settings pane.
The user has to flip OpenWispr on manually — macOS does not let an app
toggle this itself.

After granting, **OpenWispr must be re-launched** for the grant to take
effect for the running process. `AXIsProcessTrusted()` caches its
answer per-process. OpenWispr's Settings → Permissions tab has a "Restart
OpenWispr" button for this.

## Why not the App Sandbox?

The App Sandbox can't grant the Accessibility entitlement, so a
sandboxed OpenWispr would not work. OpenWispr ships unsandboxed; the
entitlements file (`Sources/OpenWispr/Resources/OpenWispr.entitlements`) makes
this explicit.

## Resetting permissions during development

If you need to re-test the onboarding flow, the in-app **Hard Reset**
button (Settings → Permissions) is the recommended path. It calls
`tccutil reset All dev.openwispr.app`, opens System Settings, and quits OpenWispr.

Equivalent from a shell:

```bash
tccutil reset All dev.openwispr.app
```

Each reset re-arms the prompt on next launch.
