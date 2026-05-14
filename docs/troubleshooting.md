# Troubleshooting

The most common Whisp issues — and how to fix them.

## "I granted Accessibility but Whisp still says Needed"

Two distinct causes, identical symptom:

### Reason 1: TCC caches per-process

macOS delivers the Accessibility grant only to a **freshly-launched**
process. The running Whisp keeps its cached "denied" state until it
restarts.

**Fix:** click **Restart Whisp** in Settings → Permissions, or from
the menu bar: Quit Whisp → relaunch.

### Reason 2: Stale TCC entry from a previous build

If you've rebuilt Whisp since the original grant, the System Settings
toggle may still appear "on" but TCC's actual decision is keyed to an
obsolete CDHash. **Restarting alone won't fix this.**

**Symptom:** restart → still "Needed" → toggle in System Settings looks
on → repeat forever.

**Fix:** click **Hard Reset** in Settings → Permissions. Whisp clears
all its TCC entries via `tccutil reset All ai.whisp.dev` and quits.
Then in System Settings → Privacy & Security → Accessibility, **remove
the stale "Whisp" row with the `−` button** (don't just toggle), relaunch
Whisp, and grant fresh. The new entry binds to the current build's
signature.

## "After a rebuild my permissions are gone"

**Cause:** macOS keys TCC grants by **bundle id + code-signing
requirement**. Ad-hoc builds produce a different CDHash every build, so
the previous grant doesn't authenticate against the new binary.

**Fix:** same as Reason 2 above — Hard Reset, remove the stale row with
`−`, re-grant.

This is the trade-off OpenSuperWhisper and VoiceInk ship with too. The
only way to skip the dance permanently is signing with an Apple-issued
Developer ID certificate ($99/year, opt-in via the `WHISP_SIGN_IDENTITY`
env var). Self-signed certs *seem* like a middle ground but macOS
Sequoia/26 silently distrusts them.

## "After a reboot my permissions are gone"

Same cause: ad-hoc signature drift. Use Hard Reset + re-grant.

## Whisp menu bar icon doesn't appear

Whisp uses `LSUIElement = true` so it has no Dock icon by design. Look
in your menu bar (right side) for the **waveform** glyph, the **red
record dot** (listening), or a **red/amber triangle** (something
broken).

If the icon really is missing:

```bash
log show --predicate 'subsystem == "ai.whisp.dev"' --last 1m
```

That tails anything Whisp wrote to Console. Common issues that surface
there: model files not found, Moonshine framework load failure,
microphone permission denied.

## Hotkey doesn't fire

Two failure modes:

1. **Accessibility isn't granted** — Whisp's hotkey monitor uses
   `NSEvent.addGlobalMonitorForEvents`, which requires the Accessibility
   permission. Open Settings → Permissions and grant. Restart Whisp
   after granting.

2. **Another app is intercepting Fn first** — macOS's "Press 🌐 key to"
   setting (System Settings → Keyboard → "Press 🌐 key to") may trap
   Fn for emoji or dictation. Set it to "Do Nothing" or change Whisp's
   hotkey (hotkey rebinding ships in v0.2).

The menu bar icon should turn into a **red triangle** if Whisp's
self-test detects this; hover for a tooltip explaining what's broken.

## Paste-mode insertion lands in the wrong app

Whisp posts Cmd+V to **whatever app had focus when listening started**.
If your focus has moved (e.g., you clicked elsewhere mid-recording), the
paste lands in the new focus. The OS routes events to the keyboard-
focused window; Whisp can't override that.

## Keystroke-mode insertion drops characters

Some apps (especially Electron) rate-limit incoming synthetic events.
Switch to **clipboard paste** mode in Settings → General — faster and
more reliable everywhere.

## Resetting all permissions

The in-app **Hard Reset** button (Settings → Permissions) is the
recommended path. Equivalent from a shell:

```bash
tccutil reset All ai.whisp.dev
```

Or via the dev script:

```bash
./scripts/run-dev.sh --reset
```

After resetting, relaunch Whisp and re-grant via Settings → Permissions.

## Where Whisp logs

```bash
log stream --predicate 'subsystem == "ai.whisp.dev"' --level=debug
```

`./scripts/run-dev.sh --logs` does this for you after rebuilding.

A separate category called `SelfTest` reports the result of the
launch-time health check:

```bash
log stream --predicate 'subsystem == "ai.whisp.dev" AND category == "SelfTest"'
```
