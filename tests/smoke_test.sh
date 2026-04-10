#!/bin/bash
# Smoke tests — CI-safe checks on build output. No permissions required.
set -euo pipefail

PASS=0
FAIL=0

check() {
    local label="$1"
    if eval "$2" >/dev/null 2>&1; then
        echo "  PASS  $label"
        ((PASS++)) || true
    else
        echo "  FAIL  $label"
        ((FAIL++)) || true
    fi
}

echo "Cypher smoke tests"
echo "─────────────────────────────────────────"

# ── Build output ─────────────────────────────
echo ""
echo "Build output"
check "binary exists"              "test -f cypher"
check "binary is executable"       "test -x cypher"
check "app bundle exists"          "test -d cypher.app"
check "binary in bundle"           "test -f cypher.app/Contents/MacOS/cypher"
check "Info.plist in bundle"       "test -f cypher.app/Contents/Info.plist"
check "icon in bundle"             "test -f cypher.app/Contents/Resources/cypher.icns"

# ── Bundle metadata ───────────────────────────
echo ""
echo "Bundle metadata"
check "bundle ID correct"   "grep -q 'com.vaughan2.cypher' cypher.app/Contents/Info.plist"
check "bundle name correct" "grep -q '<string>cypher</string>' cypher.app/Contents/Info.plist"
check "LSUIElement set"     "grep -q 'LSUIElement' cypher.app/Contents/Info.plist"

# ── Binary integrity ──────────────────────────
echo ""
echo "Binary integrity"
check "binary is Mach-O"    "file cypher | grep -q Mach-O"
check "binary is arm64"     "file cypher | grep -q arm64"
check "code signed"         "codesign -v cypher.app"
check "signature valid"     "codesign --verify --deep --strict cypher.app"

# ── Linked frameworks ─────────────────────────
echo ""
echo "Linked frameworks"
check "links Cocoa"              "otool -L cypher | grep -q Cocoa"
check "links Carbon"             "otool -L cypher | grep -q Carbon"
check "links CoreGraphics"       "otool -L cypher | grep -q CoreGraphics"
check "links ServiceManagement"  "otool -L cypher | grep -q ServiceManagement"

echo ""
echo "─────────────────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
    echo "✓  All $PASS smoke tests passed."
    exit 0
else
    echo "✗  $FAIL failed, $PASS passed."
    exit 1
fi
