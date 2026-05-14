# Distribution

OpenWispr ships as an unsigned `.zip` on GitHub Releases. This is the simplest
path that doesn't cost $99/year for an Apple Developer ID. If you fork
OpenWispr and want to publish signed builds, see [Signing & notarization](#signing--notarization)
at the bottom.

## What `scripts/build-release.sh` produces

```
build/OpenWispr.app                       # ready-to-run bundle
dist/OpenWispr-<version>.zip              # zipped via `ditto`, for GitHub Releases
```

The zip preserves macOS metadata (`ditto --sequesterRsrc --keepParent`)
so users can unzip with the Finder without losing the bundle's
executable bit.

## Publishing a release

1. Bump the version in `Sources/OpenWispr/Resources/Info.plist`
   (`CFBundleShortVersionString`).
2. `./scripts/build-release.sh`
3. Test the produced `.app` on a clean Mac (or `tccutil reset` your own).
4. `gh release create v<version> dist/OpenWispr-<version>.zip --notes-from-tag`

## Gatekeeper on first launch

Because the .app is unsigned, macOS Gatekeeper blocks the standard
double-click launch with:

> "OpenWispr" can't be opened because Apple cannot check it for malicious
> software.

The user accepts once with:

1. **Right-click** `OpenWispr.app` → **Open**.
2. macOS shows a confirmation dialog with an **Open** button.
3. After the first accept, subsequent launches are normal.

This is documented in the README and shown on the GitHub Release page.

## Why not Homebrew Cask?

Homebrew Casks expect a stable URL and (ideally) a signed app. Once
OpenWispr has a Developer ID, a cask becomes straightforward:

```ruby
cask "openwispr" do
  version "0.2.0"
  sha256 "..."
  url "https://github.com/seeknull/openwispr/releases/download/v#{version}/OpenWispr-#{version}.zip"
  name "OpenWispr"
  desc "Open-source dictation for macOS"
  homepage "https://github.com/seeknull/openwispr"
  app "OpenWispr.app"
end
```

## Signing & notarization (future)

When we get a Developer ID:

```bash
# Code-sign
codesign --force --deep --options runtime \
    --sign "Developer ID Application: Your Name (TEAMID)" \
    --entitlements Sources/OpenWispr/Resources/OpenWispr.entitlements \
    build/OpenWispr.app

# Notarize
ditto -c -k --keepParent build/OpenWispr.app dist/OpenWispr.zip
xcrun notarytool submit dist/OpenWispr.zip \
    --apple-id you@example.com \
    --team-id TEAMID --password "@keychain:notarytool" \
    --wait

# Staple the ticket
xcrun stapler staple build/OpenWispr.app
```

Once notarized, the `.zip` opens with a standard double-click.

## Auto-updates

Not implemented yet. The roadmap is to add [Sparkle](https://sparkle-project.org/)
once notarization is in place. Until then, point users at the GitHub
Releases page.
