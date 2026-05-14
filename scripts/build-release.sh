#!/usr/bin/env bash
# Build a packaged Whisp.app for release.
#
# Output:
#   build/Whisp.app          — the .app bundle
#   dist/Whisp-<version>.zip — zipped for GitHub Releases
#
# Pre-reqs:
#   * scripts/bootstrap.sh has been run (Moonshine.xcframework exists)
#   * scripts/download-models.sh has been run (model in Resources/models/)
#
# This script does NOT codesign or notarize. See docs/distribution.md for
# what folks installing the unsigned .zip need to do (right-click → Open
# once to satisfy Gatekeeper).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISP_DIR="$(dirname "$SCRIPT_DIR")"
cd "$WHISP_DIR"

# Read CFBundleShortVersionString from the Info.plist. The key and value
# live on separate lines, so we grab the next <string> after the key.
VERSION="$(awk '/CFBundleShortVersionString/{getline; gsub(/.*<string>|<\/string>.*/,""); print; exit}' \
    Sources/Whisp/Resources/Info.plist)"
VERSION="${VERSION:-0.0.0}"
BUILD_DIR="$WHISP_DIR/build"
APP_DIR="$BUILD_DIR/Whisp.app"
DIST_DIR="$WHISP_DIR/dist"

rm -rf "$APP_DIR" "$BUILD_DIR/swift-release"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$DIST_DIR"

# Architecture selection. Default: host arch only. Set WHISP_UNIVERSAL=1 to
# attempt a universal (arm64 + x86_64) build — note that the MoonshineVoice
# objc metadata currently fails to link universal under release mode, so the
# universal path is best-effort.
HOST_ARCH="$(uname -m)"
ARCH_ARGS=("--arch" "$HOST_ARCH")
if [ "${WHISP_UNIVERSAL:-0}" = "1" ]; then
    ARCH_ARGS=("--arch" "arm64" "--arch" "x86_64")
fi

echo "==> Building Whisp executable (release, ${ARCH_ARGS[*]})..."
swift build \
    -c release \
    "${ARCH_ARGS[@]}" \
    --build-path "$BUILD_DIR/swift-release"

# Locate the produced binary. SwiftPM lays out per-arch products as
# `<arch>-apple-macosx/release/Whisp`, and universal builds at
# `apple/Products/Release/Whisp`.
BIN_PATH=""
for candidate in \
    "$BUILD_DIR/swift-release/apple/Products/Release/Whisp" \
    "$BUILD_DIR/swift-release/release/Whisp" \
    "$BUILD_DIR/swift-release/${HOST_ARCH}-apple-macosx/release/Whisp"
do
    if [ -f "$candidate" ]; then BIN_PATH="$candidate"; break; fi
done

if [ ! -f "$BIN_PATH" ]; then
    echo "error: could not locate built Whisp binary" >&2
    exit 1
fi

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/Whisp"
cp Sources/Whisp/Resources/Info.plist "$APP_DIR/Contents/Info.plist"

# Copy bundled resources next to the binary.
if [ -d "Sources/Whisp/Resources/models" ]; then
    cp -R Sources/Whisp/Resources/models "$APP_DIR/Contents/Resources/models"
fi

# Copy the SwiftPM-built resources bundle (asset catalogue) if present.
RES_BUNDLE="$(find "$BUILD_DIR/swift-release" -name "Whisp_Whisp.bundle" -type d | head -n1 || true)"
if [ -n "${RES_BUNDLE:-}" ] && [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

# Copy the Moonshine.xcframework's macOS slice so the dylib resolves.
MOONSHINE_FRAMEWORK="$WHISP_DIR/../moonshine/swift/Moonshine.xcframework/macos-arm64_x86_64"
if [ ! -d "$MOONSHINE_FRAMEWORK" ]; then
    echo "error: Moonshine.xcframework macOS slice missing — run scripts/bootstrap.sh" >&2
    exit 1
fi

# Sign the bundle. macOS TCC (Microphone / Accessibility / Input Monitoring)
# refuses to attribute permissions to a bundle with no signature at all,
# so we always sign — at minimum ad-hoc.
#
# Two paths:
#   * Ad-hoc (default): `codesign --sign -`. Sufficient for first-launch
#     grants. The signature hash differs across rebuilds, so macOS may
#     decide a rebuilt Whisp is a "new" app and invalidate the grant —
#     re-grant once when that happens. Same trade-off OpenSuperWhisper /
#     VoiceInk ship with.
#   * Stable local identity: if you've run `scripts/create-dev-cert.sh`,
#     the build picks up that cert and grants persist across rebuilds.
#
# `xattr -cr` strips the quarantine attribute so Gatekeeper doesn't
# block our own dev launches.
SIGN_IDENTITY="${WHISP_SIGN_IDENTITY:-Whisp Local Dev}"
ENTITLEMENTS="$WHISP_DIR/Sources/Whisp/Resources/Whisp.entitlements"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "==> Codesigning with stable identity: $SIGN_IDENTITY"
    codesign --force --deep --options runtime \
        --sign "$SIGN_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        "$APP_DIR" >/dev/null
else
    echo "==> Ad-hoc codesigning (grants may invalidate on rebuild)"
    codesign --force --deep \
        --sign - \
        --entitlements "$ENTITLEMENTS" \
        "$APP_DIR" >/dev/null
fi
xattr -cr "$APP_DIR"

echo "==> Zipping release..."
cd "$BUILD_DIR"
ZIP_NAME="Whisp-${VERSION}.zip"
rm -f "$DIST_DIR/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent Whisp.app "$DIST_DIR/$ZIP_NAME"

echo
echo "Built: $APP_DIR"
echo "Zip:   $DIST_DIR/$ZIP_NAME"
echo
echo "Next: drag Whisp.app to /Applications and launch."
echo "Unsigned: first launch needs right-click → Open to satisfy Gatekeeper."
