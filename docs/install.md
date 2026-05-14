# Install OpenWispr

A step-by-step install for end users. If you want to build from
source instead, see [building.md](building.md).

## Requirements

- **macOS 13 (Ventura) or newer**
- Apple Silicon (arm64) or Intel (x86_64) Mac

## Step 1: Download

Grab the latest `OpenWispr-<version>.zip` from
[GitHub Releases](https://github.com/seeknull/openwispr/releases).

## Step 2: Move to Applications

Unzip the file. Drag `OpenWispr.app` into your `/Applications`
folder.

## Step 3: First launch (Gatekeeper)

OpenWispr ships unsigned (we don't have an Apple Developer ID yet),
so macOS Gatekeeper will block the standard double-click launch with
a message like:

> "OpenWispr" can't be opened because Apple cannot check it for
> malicious software.

To accept it once:

1. In Finder, **right-click** `OpenWispr.app`.
2. Choose **Open** from the menu.
3. macOS shows a confirmation dialog with an **Open** button. Click
   it.

Subsequent launches are normal double-click.

## Step 4: Grant permissions

OpenWispr lives in your menu bar — look for the waveform icon
(top-right of your screen). When it first launches with no
permissions, the icon will be a **red triangle** and a Settings
window will pop open automatically.

You need to grant two permissions:

### Microphone

1. In OpenWispr's Settings → **Permissions** tab, click **Request**
   next to Microphone.
2. macOS shows a prompt: "OpenWispr would like to access the
   microphone." Click **Allow**.

The row should flip to green **Granted** immediately.

### Accessibility

1. Click **Open Settings** next to Accessibility.
2. macOS opens System Settings → Privacy & Security → Accessibility.
3. Toggle OpenWispr **on**.
4. Come back to OpenWispr's Settings → Permissions tab, and click
   **Restart OpenWispr**.

After the restart, both permissions should show as **Granted** and
the menu bar icon should be a clean waveform.

### Why these two?

| Permission | What it does |
| --- | --- |
| Microphone | Capture audio for transcription. |
| Accessibility | (1) Paste / type the transcript into your focused app. (2) Observe the global Fn+Option hotkey. |

See [permissions.md](permissions.md) for the gritty TCC details.

## Step 5: Try it

Click into any text field — Notes, your browser's address bar, a
chat app, your terminal, anywhere.

Press **Fn + Option**. You'll see:

- The menu bar icon becomes a **red record dot**.
- A pulsing **red HUD pill** at the top of your screen: *"Listening…
  Fn+Option to stop."*

Speak a sentence: *"the quick brown fox jumps over the lazy dog."*

Press **Fn + Option** again to stop. Your transcript appears at the
cursor.

## What to do if it doesn't work

If the hotkey doesn't seem to do anything, the most common cause is
the Accessibility grant. Check OpenWispr's Settings → Permissions
tab; if the menu bar icon is a red triangle, click it and the
tooltip will tell you what's missing.

For everything else, see [troubleshooting.md](troubleshooting.md).
