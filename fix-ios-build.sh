#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════
# Huddl Connect — iOS Build Fix Script
# Run this ONCE from your project folder on your Mac:
#   cd ~/Downloads/huddl
#   chmod +x fix-ios-build.sh
#   ./fix-ios-build.sh
# ══════════════════════════════════════════════════════════════════════════

set -e   # Stop on first error

echo ""
echo "═══════════════════════════════════════════════"
echo "  Huddl Connect — iOS Build Fix"
echo "═══════════════════════════════════════════════"
echo ""

# ── Step 1: Locate Flutter SDK ───────────────────────────────────────────
FLUTTER_PATH=$(which flutter 2>/dev/null || echo "")
if [ -z "$FLUTTER_PATH" ]; then
  echo "❌  Flutter not found in PATH."
  echo "   Add Flutter to PATH first, e.g.:"
  echo "   export PATH=\"/usr/local/flutter/bin:\$PATH\""
  exit 1
fi

# Resolve the real Flutter root (follow symlinks)
FLUTTER_ROOT_REAL=$(dirname $(dirname $(readlink -f "$FLUTTER_PATH" 2>/dev/null || echo "$FLUTTER_PATH")))
echo "✅  Flutter found: $FLUTTER_PATH"
echo "✅  FLUTTER_ROOT:  $FLUTTER_ROOT_REAL"

# ── Step 2: Export FLUTTER_ROOT so pub get uses the correct path ─────────
export FLUTTER_ROOT="$FLUTTER_ROOT_REAL"

# ── Step 3: Ensure FLUTTER_ROOT is permanent in shell config ─────────────
SHELL_RC="$HOME/.zshrc"
if ! grep -q "FLUTTER_ROOT=" "$SHELL_RC" 2>/dev/null; then
  echo "" >> "$SHELL_RC"
  echo "# Flutter SDK — added by Huddl fix-ios-build.sh" >> "$SHELL_RC"
  echo "export FLUTTER_ROOT=\"$FLUTTER_ROOT_REAL\"" >> "$SHELL_RC"
  echo "export PATH=\"$FLUTTER_ROOT_REAL/bin:\$PATH\"" >> "$SHELL_RC"
  echo "✅  FLUTTER_ROOT added permanently to $SHELL_RC"
else
  # Update existing line
  sed -i '' "s|export FLUTTER_ROOT=.*|export FLUTTER_ROOT=\"$FLUTTER_ROOT_REAL\"|g" "$SHELL_RC"
  echo "✅  FLUTTER_ROOT updated in $SHELL_RC"
fi

# ── Step 4: Clean Flutter artifacts ─────────────────────────────────────
echo ""
echo "🧹  Cleaning Flutter build artifacts..."
flutter clean

# ── Step 5: Regenerate Generated.xcconfig with correct FLUTTER_ROOT ──────
echo ""
echo "📦  Running flutter pub get (regenerates Generated.xcconfig)..."
flutter pub get

# Verify Generated.xcconfig has the correct path
XCCONFIG="ios/Flutter/Generated.xcconfig"
if [ -f "$XCCONFIG" ]; then
  CURRENT_ROOT=$(grep "^FLUTTER_ROOT=" "$XCCONFIG" | cut -d'=' -f2)
  if [ "$CURRENT_ROOT" != "$FLUTTER_ROOT_REAL" ]; then
    echo "⚠️  Generated.xcconfig has wrong FLUTTER_ROOT: $CURRENT_ROOT"
    echo "   Patching to: $FLUTTER_ROOT_REAL"
    sed -i '' "s|FLUTTER_ROOT=.*|FLUTTER_ROOT=$FLUTTER_ROOT_REAL|g" "$XCCONFIG"
  fi
  echo "✅  Generated.xcconfig FLUTTER_ROOT: $(grep '^FLUTTER_ROOT=' $XCCONFIG)"
else
  echo "❌  Generated.xcconfig not found — flutter pub get may have failed."
  exit 1
fi

# ── Step 6: Fix xcconfig files (ensure they only have clean includes) ─────
echo ""
echo "🔧  Fixing Flutter xcconfig files..."

DEBUG_XCCONFIG="ios/Flutter/Debug.xcconfig"
RELEASE_XCCONFIG="ios/Flutter/Release.xcconfig"
PROFILE_XCCONFIG="ios/Flutter/Profile.xcconfig"

# Write clean xcconfig files (prevents duplicate-include issues)
cat > "$DEBUG_XCCONFIG" << 'EOF'
#include "Generated.xcconfig"
EOF

cat > "$RELEASE_XCCONFIG" << 'EOF'
#include "Generated.xcconfig"
EOF

cat > "$PROFILE_XCCONFIG" << 'EOF'
#include "Generated.xcconfig"
EOF

echo "✅  xcconfig files reset to clean state"

# ── Step 7: Reinstall CocoaPods ──────────────────────────────────────────
echo ""
echo "📦  Installing CocoaPods dependencies..."
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
echo "  1. Open Xcode:  open ios/Runner.xcworkspace"
echo "  2. In Xcode → Runner target → Signing & Capabilities:"
echo "     - Team: Conrad D'Cruz (or huddl project)"
echo "     - Automatically manage signing: ✅"
echo "     - Remove iCloud capability (not needed)"
echo "  3. Product → Archive"
echo ""
