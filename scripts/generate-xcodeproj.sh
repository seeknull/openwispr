#!/usr/bin/env bash
# Generate Whisp.xcodeproj from the SwiftPM package. Useful for running
# XCUITests, which SwiftPM cannot drive directly.
#
# Usage:
#   ./scripts/generate-xcodeproj.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISP_DIR="$(dirname "$SCRIPT_DIR")"
cd "$WHISP_DIR"

# `swift package generate-xcodeproj` was removed in Swift 5.6.
# The modern approach is to open Package.swift directly in Xcode,
# which auto-generates the project.
echo "Open Package.swift in Xcode:"
echo "    open -a Xcode Package.swift"
echo
echo "Xcode will resolve the local Moonshine dependency and produce schemes"
echo "for each product/test target automatically."
