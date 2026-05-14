# Using OpenWispr

How to actually use OpenWispr day-to-day, plus the configuration
knobs that exist.

## The basic loop

1. Click into any text field anywhere on your Mac.
2. Press **Fn + Option**. Menu bar icon turns red, HUD pill appears.
3. Speak. Pause naturally between sentences.
4. Press **Fn + Option** again. Your transcript drops at the cursor.

That's the whole interaction model. You're not switching apps,
opening windows, or copy-pasting — you're just talking and the words
arrive.

## Tips for better results

**Pause clearly between sentences.** Moonshine uses speech pauses
to detect sentence boundaries and decide where to insert
punctuation. A clear pause makes the difference between
*"hello world how are you"* and *"hello world. how are you?"*

**Speak at a natural pace.** Faster than typing is fine.
Significantly slower than your normal speaking pace actually hurts
accuracy — the model is trained on conversational speech.

**The first second is often less accurate.** If you're dictating a
short phrase, lead with a throwaway word ("uh, send the report") and
delete it after.

**Don't move your cursor while dictating.** OpenWispr pastes into
whatever app had focus *when listening started*. If you click away
mid-recording, the paste lands wherever you clicked.

## Menu bar icon states

| Icon | Meaning |
| --- | --- |
| **Waveform** (clean) | OpenWispr is healthy and idle |
| **Red dot** | Listening — speak |
| **Red triangle** | Self-test failed — permissions or model missing |
| **Amber triangle** | Self-test warning — degraded |

Hover the icon at any time to see the current status as a tooltip.

The menu (left-click the icon) has a **Status:** line that tells you
the same thing in words.

## Settings

Open Settings from the menu bar icon → **Settings…** (or `⌘,` while
the window is focused).

### General tab

- **Insertion mode** — how OpenWispr puts the transcript into the
  focused app.
  - *Paste via clipboard* (default): saves your clipboard, writes
    the transcript to it, posts Cmd+V, restores the clipboard
    ~120ms later. Fast, works everywhere. Briefly touches the
    clipboard.
  - *Synthesize keystrokes*: posts one CGEvent per character. No
    clipboard interference, but slower for long transcripts and can
    drop characters in apps that rate-limit synthetic events
    (Electron, web apps).
- **Show listening indicator** — toggles the red HUD pill at the top
  of the screen. Some users find it distracting; turn it off and
  rely on the menu bar icon.
- **Hotkey** — currently shows "Fn + Option" with no way to change.
  Rebinding is on [the roadmap](roadmap.md) for v0.2.

### Permissions tab

Status of the two macOS permissions OpenWispr needs. Each row has
a button to grant or open System Settings to the right pane.

The **Hard Reset** button at the bottom is the nuclear option: it
runs `tccutil reset All dev.openwispr.app`, opens System Settings,
and quits OpenWispr. Use it when permissions are in a confused state
(usually after a build update changed OpenWispr's signature). See
[troubleshooting.md](troubleshooting.md) for the full story.

### About tab

Version, license link, source link. Not much to configure.

## Keyboard shortcuts

| Shortcut | What it does |
| --- | --- |
| Fn + Option (anywhere) | Toggle dictation on/off |
| ⌘ , (with Settings open) | (Reserved — standard macOS Settings shortcut) |
| ⌘ Q (from menu) | Quit OpenWispr |

## Insertion-mode tradeoffs in detail

Clipboard paste vs. synthesized keystrokes — which one to pick:

**Pick clipboard paste if:**
- You dictate long transcripts (multiple sentences)
- You use Electron apps or web apps (Slack, Discord, Notion, Linear)
- You don't mind your clipboard briefly changing

**Pick synthesized keystrokes if:**
- You're a password-manager user who keeps secrets on the clipboard
- You dictate very short bursts and the difference is imperceptible
- You hit weird issues with paste in a specific app

Both modes require the **Accessibility** permission.

## What OpenWispr does NOT do (yet)

These are on the roadmap:

- Hotkey rebinding (currently hard-coded to Fn+Option)
- Launch at login
- Push-to-talk mode (hold to record, release to stop)
- Model selection in-app (you currently get whatever was bundled)
- Voice commands ("scratch that", "new line", "send")

See [roadmap.md](roadmap.md) for the full list.

## Where to get help

- [troubleshooting.md](troubleshooting.md) — common issues
- [GitHub Issues](https://github.com/seeknull/openwispr/issues) —
  bug reports and feature requests
