# Troubleshooting

The most common Whisp issues — and how to fix them.

## "I granted Accessibility but Whisp still says it's not granted"

**Cause:** macOS only delivers Accessibility (and Input Monitoring) grants
to a **freshly-launched** process. The running Whisp instance keeps its
cached "denied" state until it restarts.

**Fix:** Whisp's Settings → Permissions tab shows a **Restart Whisp** banner
once you've clicked "Open Settings" for either of those permissions. Click
that, and the new instance will pick up the grant.

If for some reason that banner doesn't show:

```bash
pkill -x Whisp && open -n /path/to/Whisp.app
```

(Or just from the menu bar: Quit Whisp → relaunch.)

## "After a rebuild my permissions are gone"

**Cause:** macOS keys TCC permission grants by **bundle id + code-signing
identity**. The default Whisp build uses ad-hoc signing (`codesign --sign -`),
which produces a different signature hash every build. macOS sees the new
hash and decides "this is a new app", invalidating the grant.

**Two fixes**, pick one:

### Easy fix — re-grant once after each rebuild

Open System Settings → Privacy & Security → Accessibility (or Input
Monitoring) → toggle Whisp off and back on. Same for the others. Takes
~20 seconds.

If Whisp shows up *twice* in the list (one with the old hash, one with
the new), remove the older entry with the `−` button.

### Permanent fix — sign with a stable local identity

Run once:

```bash
./scripts/create-dev-cert.sh
```

This creates a self-signed certificate called **"Whisp Local Dev"** in
your login keychain. From then on, `scripts/build-release.sh` signs every
build with that identity, the signature hash stays identical across
rebuilds, and macOS treats successive Whisp builds as the same app —
grants survive.

The cert is local-only (never leaves your machine, never chains to
Apple), but it's enough for TCC.

## "After a reboot my permissions are gone"

Same cause as above. Take the **permanent fix** route.

## Whisp menu bar icon doesn't appear

Whisp uses `LSUIElement = true` so it has no Dock icon by design. Look for
the waveform glyph in your menu bar (right side, near the system icons).

If the icon really is missing:

```bash
log show --predicate 'subsystem == "ai.whisp.app"' --last 1m
```

That tails anything Whisp wrote to Console. Common issues that surface
there: model files not found, Moonshine framework load failure,
microphone permission denied.

## Hotkey doesn't fire

Two failure modes:

1. **Input Monitoring isn't granted yet** — open Settings → Permissions
   and verify. Restart Whisp after granting.
2. **Another app is intercepting Fn first** — e.g., the macOS "Press 🌐
   to" setting (System Settings → Keyboard → "Press 🌐 key to") might be
   trapping the Fn key for emoji or dictation. Set it to "Do Nothing" or
   change Whisp's hotkey (see Settings → General once hotkey rebinding
   ships in v0.2).

## Paste-mode insertion lands in the wrong app

Whisp posts Cmd+V to **whatever app had focus when listening started**.
If your focus has moved (e.g., you clicked elsewhere mid-recording), the
paste will land in the new focus. There's nothing Whisp can do about
this — the OS routes events to the keyboard-focused window.

## Keystroke-mode insertion drops characters

Some apps (especially Electron) rate-limit incoming synthetic events.
Switch to **clipboard paste** mode in Settings → General — it's faster
and more reliable everywhere.

## Resetting all permissions

Nuclear option, useful when things are deeply confused:

```bash
tccutil reset Microphone     ai.whisp.app
tccutil reset Accessibility  ai.whisp.app
tccutil reset ListenEvent    ai.whisp.app
```

Or do it in one shot:

```bash
./scripts/run-dev.sh --reset
```

After resetting, relaunch Whisp and walk through the Settings →
Permissions tab from scratch.

## Where Whisp logs

```bash
log stream --predicate 'subsystem == "ai.whisp.app"' --level=debug
```

`./scripts/run-dev.sh --logs` does this for you after rebuilding.
