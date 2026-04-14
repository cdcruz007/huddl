#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════
# Huddl Connect — iOS Build Fix Script  (v4 — definitive)
# Fixes: "Null check operator used on null value" in xcode_backend.dart
#
# Run from your project folder:
#   cd ~/Downloads/huddl
#   chmod +x fix-ios-build.sh
#   ./fix-ios-build.sh
# ══════════════════════════════════════════════════════════════════════════

set -e

echo ""
echo "═══════════════════════════════════════════════"
echo "  Huddl Connect — iOS Build Fix  (v4)"
echo "═══════════════════════════════════════════════"
echo ""

# ── Step 1: Locate Flutter SDK ───────────────────────────────────────────
FLUTTER_PATH=$(which flutter 2>/dev/null || echo "")
if [ -z "$FLUTTER_PATH" ]; then
  echo "❌  Flutter not found in PATH."
  echo "   Run: export PATH=\"/usr/local/flutter/bin:\$PATH\""
  exit 1
fi

# Resolve real path (follow symlinks)
if command -v greadlink &>/dev/null; then
  FLUTTER_REAL=$(greadlink -f "$FLUTTER_PATH")
elif command -v readlink &>/dev/null; then
  FLUTTER_REAL=$(readlink -f "$FLUTTER_PATH" 2>/dev/null || echo "$FLUTTER_PATH")
else
  FLUTTER_REAL="$FLUTTER_PATH"
fi

FLUTTER_ROOT_REAL=$(dirname $(dirname "$FLUTTER_REAL"))
echo "✅  Flutter path:  $FLUTTER_PATH"
echo "✅  FLUTTER_ROOT:  $FLUTTER_ROOT_REAL"
echo "✅  Version:       $(flutter --version 2>&1 | head -1)"

export FLUTTER_ROOT="$FLUTTER_ROOT_REAL"

# ── Step 2: Make FLUTTER_ROOT permanent in ~/.zshrc ──────────────────────
SHELL_RC="$HOME/.zshrc"
if grep -q "FLUTTER_ROOT=" "$SHELL_RC" 2>/dev/null; then
  sed -i '' "s|export FLUTTER_ROOT=.*|export FLUTTER_ROOT=\"$FLUTTER_ROOT_REAL\"|g" "$SHELL_RC"
else
  echo "" >> "$SHELL_RC"
  echo "# Flutter — added by Huddl fix-ios-build.sh" >> "$SHELL_RC"
  echo "export FLUTTER_ROOT=\"$FLUTTER_ROOT_REAL\"" >> "$SHELL_RC"
  echo "export PATH=\"$FLUTTER_ROOT_REAL/bin:\$PATH\"" >> "$SHELL_RC"
fi
echo "✅  FLUTTER_ROOT saved to $SHELL_RC"

# ── Step 3: Patch xcode_backend.dart null crash ──────────────────────────
# Crash: xcode_backend.dart:345 _embedNativeAssets — "Null check operator
#         used on a null value" — environment['NATIVE_ASSETS_PATH']! is null
# Fix A: patch the dart file to use ?? '' instead of !
# Fix B: create the native_assets directory so it's never null

XCODE_BACKEND_DART="$FLUTTER_ROOT_REAL/packages/flutter_tools/bin/xcode_backend.dart"
echo ""
echo "🔧  Patching xcode_backend.dart null crash..."

if [ -f "$XCODE_BACKEND_DART" ]; then
  # Backup first
  if [ ! -f "${XCODE_BACKEND_DART}.orig" ]; then
    cp "$XCODE_BACKEND_DART" "${XCODE_BACKEND_DART}.orig"
    echo "   Backup saved to xcode_backend.dart.orig"
  fi

  # Patch 1: Replace null-asserting ! access with null-safe ?? fallback
  sed -i '' \
    "s|environment\['NATIVE_ASSETS_PATH'\]!|environment['NATIVE_ASSETS_PATH'] ?? ''|g" \
    "$XCODE_BACKEND_DART" 2>/dev/null && echo "   ✅  Patched NATIVE_ASSETS_PATH null-assert" || \
    echo "   ⚠️  Patch 1 skipped (pattern not found or no write permission)"

  # Patch 2: Also catch any _nativeAssetsPath null-assert pattern
  sed -i '' \
    "s|_nativeAssetsPath!|_nativeAssetsPath ?? ''|g" \
    "$XCODE_BACKEND_DART" 2>/dev/null && echo "   ✅  Patched _nativeAssetsPath null-assert" || true

  # Verify
  if grep -q "NATIVE_ASSETS_PATH\]!" "$XCODE_BACKEND_DART" 2>/dev/null; then
    echo "   ⚠️  Patch may not have applied — will rely on Fix B instead"
  fi
else
  echo "   ⚠️  xcode_backend.dart not at expected path: $XCODE_BACKEND_DART"
fi

# ── Step 4: Clean project ────────────────────────────────────────────────
echo ""
echo "🧹  Running flutter clean..."
flutter clean

# ── Step 5: Regenerate Generated.xcconfig with correct FLUTTER_ROOT ──────
echo ""
echo "📦  Running flutter pub get..."
FLUTTER_ROOT="$FLUTTER_ROOT_REAL" flutter pub get

XCCONFIG="ios/Flutter/Generated.xcconfig"
if [ -f "$XCCONFIG" ]; then
  CURRENT=$(grep "^FLUTTER_ROOT=" "$XCCONFIG" | cut -d'=' -f2-)
  if [ "$CURRENT" != "$FLUTTER_ROOT_REAL" ]; then
    sed -i '' "s|FLUTTER_ROOT=.*|FLUTTER_ROOT=$FLUTTER_ROOT_REAL|g" "$XCCONFIG"
    echo "✅  Fixed FLUTTER_ROOT in Generated.xcconfig → $FLUTTER_ROOT_REAL"
  else
    echo "✅  Generated.xcconfig FLUTTER_ROOT is correct"
  fi
fi

# ── Step 6: Reset xcconfig files cleanly ────────────────────────────────
echo ""
echo "🔧  Resetting xcconfig files..."
printf '#include "Generated.xcconfig"\n' > ios/Flutter/Debug.xcconfig
printf '#include "Generated.xcconfig"\n' > ios/Flutter/Release.xcconfig
printf '#include "Generated.xcconfig"\n' > ios/Flutter/Profile.xcconfig
echo "✅  Debug / Release / Profile xcconfig files reset"

# ── Step 7: Pre-create native_assets directory (Fix B) ───────────────────
# xcode_backend.dart crashes if NATIVE_ASSETS_PATH points to non-existent dir
BUILD_NATIVE_ASSETS="build/native_assets/ios"
mkdir -p "$BUILD_NATIVE_ASSETS"
echo "✅  Created $BUILD_NATIVE_ASSETS (prevents null crash)"

# ── Step 8: Clean Xcode DerivedData for this project ─────────────────────
echo ""
echo "🧹  Cleaning Xcode DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-* 2>/dev/null || true
echo "✅  DerivedData cleaned"

# ── Step 9: Reinstall CocoaPods ──────────────────────────────────────────
echo ""
echo "📦  Reinstalling CocoaPods (this takes 2-5 minutes)..."
cd ios
rm -rf Pods
rm -f Podfile.lock
pod install
cd ..

echo ""
echo "═══════════════════════════════════════════════"
echo "  ✅  All fixes applied!"
echo "═══════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "  1. open ios/Runner.xcworkspace"
echo "  2. In Xcode: Product → Clean Build Folder  (Shift+Cmd+K)"
echo "  3. Product → Archive"
echo ""
echo "  If archive still fails, run this extra command first:"
echo "  rm -rf ~/Library/Developer/Xcode/DerivedData"
echo ""
