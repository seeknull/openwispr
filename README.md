# OpenWispr

**Speak. The text appears where your cursor is.**
Free, open source, fully on-device dictation for macOS.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-brightgreen)

---

OpenWispr is a tiny menu-bar app. Press **Fn + Option**, talk, press
again to stop. Your words appear in whatever app has your cursor:
your editor, your terminal, Slack, Gmail, Notes, anywhere.

That's it. No accounts. No keys. No subscription. No data leaves your
Mac.

## Why OpenWispr

🪶  **Truly local.** The speech-to-text model runs on your CPU. There
is no network call in the entire dictation path. Pull the ethernet
cable and OpenWispr keeps working.

🔒  **Your voice never leaves your machine.** No telemetry. No
analytics. No "anonymous usage data." We built it so we *can't* see
what you say.

🪟  **Open source, MIT-licensed.** Inspect the code. Fork it. Audit
the audio path yourself in
[`Sources/OpenWispr/DictationEngine.swift`](Sources/OpenWispr/DictationEngine.swift).
The [MIT license](LICENSE) lets you do whatever you want with it,
including selling derivatives.

🎯  **Fast.** Powered by [Moonshine](https://moonshine.ai), which is
~5× faster than Whisper at similar accuracy and was designed for
live dictation, not 30-second batch chunks.

🪵  **Tiny.** Pure Swift, no Electron, no Python runtime. ~50 MB of
binary, ~280 MB once you bundle the default model.

⌨️  **Works in every app.** Two insertion modes: clipboard paste
(fast, universal) or synthesized keystrokes (no clipboard
interference). Whichever your workflow prefers.

## How it works

```
You press Fn + Option
   ↓
OpenWispr captures audio from your mic
   ↓
Moonshine transcribes it as you speak (on your CPU)
   ↓
You press Fn + Option again
   ↓
The transcript appears at your cursor
```

That's the whole story. There is no step where audio leaves your
machine.

## Install

Download `OpenWispr-<version>.zip` from
[GitHub Releases](https://github.com/seeknull/openwispr/releases),
unzip, drag `OpenWispr.app` to `/Applications`, right-click → **Open**
the first time, grant **Microphone** and **Accessibility** in
Settings. Done.

Detailed walkthrough: [docs/install.md](docs/install.md).

## Build from source

OpenWispr depends on the [Moonshine](https://github.com/moonshine-ai/moonshine)
Swift package as a sibling directory. The short version:

```bash
git clone https://github.com/moonshine-ai/moonshine.git
git clone https://github.com/seeknull/openwispr.git
cd openwispr
./scripts/run-dev.sh
```

`run-dev.sh` autodetects what's needed (Moonshine framework, models,
permissions) and walks you through the rest.

Full prerequisites and dev workflow: [docs/building.md](docs/building.md).

## Privacy

OpenWispr makes a stronger privacy claim than most "private" apps. We
don't *promise* not to send your data anywhere — we made it
**architecturally impossible**. The dictation path has no networking
code at all: no `URLSession`, no analytics SDK, no telemetry.

Verify it in three minutes:

```bash
grep -r "URLSession\|URLRequest\|http://\|https://" Sources/
```

The only matches are in `SettingsView.swift` (a link to this repo)
and code comments. The actual transcription path touches nothing but
local files and your microphone.

More on what permissions OpenWispr asks for and why: [docs/permissions.md](docs/permissions.md).

## License — MIT

OpenWispr is released under the [MIT License](LICENSE) — the most
permissive standard open-source license.

**You may** use, copy, modify, merge, publish, distribute, sublicense,
and sell copies of OpenWispr, with or without modification, in
commercial or non-commercial projects.

**You must** include the copyright notice and the MIT license text in
substantial portions of any copy or derivative work.

**There is no warranty.** OpenWispr is provided "as is."

We chose MIT specifically because we want OpenWispr to be widely
usable — including inside commercial products. If you ship a tool
that embeds OpenWispr or its ideas, you don't owe us anything beyond
the attribution clause.

## Documentation

| Doc | Audience |
| --- | --- |
| [docs/install.md](docs/install.md) | End users installing OpenWispr |
| [docs/usage.md](docs/usage.md) | How to use it day-to-day |
| [docs/permissions.md](docs/permissions.md) | What macOS permissions OpenWispr asks for and why |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Hotkey not firing? Settings stuck? Start here. |
| [docs/architecture.md](docs/architecture.md) | How the codebase is organized — for contributors |
| [docs/building.md](docs/building.md) | Building from source, dev workflow, tests |
| [docs/distribution.md](docs/distribution.md) | Producing release builds, signing, notarization |
| [docs/roadmap.md](docs/roadmap.md) | What's coming in v0.2 and beyond |

## Status

**v0.1 — early but working.** Core dictation loop is solid. Hotkey
rebinding, launch-at-login, and notarized distribution are on
[the roadmap](docs/roadmap.md).

## Contributing

OpenWispr is small (~1800 lines of Swift) and the codebase is
well-commented. Start at
[Sources/OpenWispr/OpenWisprApp.swift](Sources/OpenWispr/OpenWisprApp.swift)
and trace outward. PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Acknowledgements

- [Moonshine](https://moonshine.ai) — the on-device speech-to-text
  engine. The reason OpenWispr is fast.
- Inspired by [VoiceInk](https://github.com/Beingpax/VoiceInk) and
  [OpenSuperWhisper](https://github.com/Starmel/OpenSuperWhisper) —
  open-source dictation apps that paved the way.
