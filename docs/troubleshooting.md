# Troubleshooting

The most common Whisp issues — and how to fix them.

## "I granted Accessibility but Whisp still says it's not granted"

There are **two** reasons this happens, and they look identical:

### Reason 1: TCC caches per-process

macOS only delivers Accessibility / Input Monitoring grants to a freshly-
launched process. The running Whisp instance keeps its cached "denied"
state until it restarts.

**Fix:** click **Restart Whisp** in the blue banner on Settings →
Permissions. If the banner isn't there:

```bash
pkill -x Whisp && open -n /path/to/Whisp.app
```

(Or: menu bar → Quit Whisp → relaunch.)

### Reason 2: Stale TCC entry from a previous build

If you've rebuilt Whisp at least once since the original grant, the
System Settings UI may show Whisp as "on" but TCC's actual decision is
keyed to an obsolete CDHash. **Restarting alone won't fix this** because
the new Whisp still doesn't match the stored CDHash either.

**Symptom:** restart → still "Needed" → reopen System Settings → toggle
still appears on → repeat forever.

**Fix:** see ["After a rebuild my permissions are gone"](#after-a-rebuild-my-permissions-are-gone)
below — you need to remove the entry with the `−` button and re-add it,
not just toggle.

## "After a rebuild my permissions are gone"

**Cause:** macOS keys TCC grants by **bundle id + code-signing requirement**.
Whisp's dev builds use ad-hoc signing, which produces a different CDHash
every build. The System Settings UI keeps showing the toggle as "on"
based on bundle id, but TCC's internal decision check matches against
the old CDHash and fails.

**Fix (recommended): do the full reset cycle.**

```bash
./scripts/run-dev.sh --reset --no-build
```

Then in **System Settings → Privacy & Security**:

1. Open **Accessibility**. If Whisp is listed, click it and press the
   **−** button to fully remove the entry. Don't just toggle off — the
   stale entry can keep the bad CDHash mapping alive.
2. Do the same for **Input Monitoring**.
3. Come back to Whisp's Settings → Permissions and click **Open
   Settings** for Accessibility. This makes Whisp request the prompt
   fresh, which adds a new entry tied to the *current* CDHash.
4. Toggle it on. The Whisp Settings window will see the grant within
   ~2 seconds (it polls).
5. Repeat for Input Monitoring.

**Why "toggle off and back on" sometimes isn't enough:** Toggling
operates on the existing entry, which is bound to the *old* signature.
Removing with the `−` button and re-adding is what creates a fresh
binding to the current signature.

This is the trade-off OpenSuperWhisper and VoiceInk ship with too.
The only way to skip the dance after every rebuild is signing with an
Apple-issued Developer ID certificate ($99/year, opt-in via the
`WHISP_SIGN_IDENTITY` env var). Self-signed certs *seem* like a middle
ground but macOS Sequoia/26 silently distrusts them.

## "After a reboot my permissions are gone"

Same cause: ad-hoc signature drift. Use the reset cycle above.

## Whisp menu bar icon doesn't appear

Whisp uses `LSUIElement = true` so it has no Dock icon by design. Look for
the waveform glyph in your menu bar (right side, near the system icons).

If the icon really is missing:

```bash
log show --predicate 'subsystem == "ai.whisp.dev"' --last 1m
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
tccutil reset Microphone     ai.whisp.dev
tccutil reset Accessibility  ai.whisp.dev
tccutil reset ListenEvent    ai.whisp.dev
```

Or do it in one shot:

```bash
./scripts/run-dev.sh --reset
```

After resetting, relaunch Whisp and walk through the Settings →
Permissions tab from scratch.

## Where Whisp logs

```bash
log stream --predicate 'subsystem == "ai.whisp.dev"' --level=debug
```

`./scripts/run-dev.sh --logs` does this for you after rebuilding.
