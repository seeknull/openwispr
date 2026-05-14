#!/usr/bin/env bash
# Create a self-signed local code-signing certificate so dev rebuilds of
# Whisp share a stable code-signing identity. macOS TCC keys permission
# grants by (bundle id + signing identity), so without this every rebuild
# produces a different identity and your Accessibility / Input Monitoring
# grants vanish.
#
# Run this once. Stays in your login keychain forever (or until you delete
# it). The certificate is local-only — it does not chain to Apple, can't
# be used to ship to other Macs, and proves nothing to other users. It
# just gives the local machine a stable handle for "this is Whisp".
#
# Usage:
#   ./scripts/create-dev-cert.sh
#
# After this, re-run scripts/build-release.sh and the build will sign
# with the new identity.
set -euo pipefail

IDENTITY_NAME="${WHISP_SIGN_IDENTITY:-Whisp Local Dev}"

if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
    echo "==> Identity '$IDENTITY_NAME' already exists in the login keychain."
    echo "    To force-recreate, delete it from Keychain Access first."
    exit 0
fi

# Generate a self-signed X.509 cert with the codeSigning EKU.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/cert.conf" <<EOF
[ req ]
distinguished_name = req_dn
prompt = no
[ req_dn ]
CN = $IDENTITY_NAME
[ v3 ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "==> Generating self-signed certificate..."
openssl req \
    -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" \
    -x509 -days 3650 \
    -config "$TMP/cert.conf" -extensions v3 \
    -out "$TMP/cert.pem" >/dev/null 2>&1

openssl pkcs12 -export \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY_NAME" \
    -password pass: \
    -out "$TMP/cert.p12" >/dev/null

echo "==> Importing into login keychain..."
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$TMP/cert.p12" \
    -k "$KEYCHAIN" \
    -P "" \
    -T /usr/bin/codesign \
    -A >/dev/null

# Allow codesign to use the private key without an interactive prompt.
# This is the bit that lets the build script sign in CI / batch mode.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -k "" \
    -s -l "$IDENTITY_NAME" \
    "$KEYCHAIN" >/dev/null 2>&1 || true

echo
echo "Created identity '$IDENTITY_NAME' in your login keychain."
security find-identity -v -p codesigning | grep "$IDENTITY_NAME"
echo
echo "Next steps:"
echo "  1. Re-run ./scripts/build-release.sh — it will sign with this identity."
echo "  2. ./scripts/run-dev.sh --reset    # clear stale TCC, then re-grant once."
echo "  3. From now on, rebuilds keep your Accessibility / Input Monitoring grants."
