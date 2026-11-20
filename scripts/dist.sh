#!/bin/zsh
# Builds a shareable, notarized DockPeek-<version>.dmg (drag-to-Applications installer).
#
# One-time setup (see README.md):
#   1. Xcode → Settings → Accounts → (team) → Manage Certificates → + → "Developer ID Application"
#   2. xcrun notarytool store-credentials dockpeek --apple-id <you> --team-id <TEAMID>
#
# Usage:
#   scripts/dist.sh             # build, sign, notarize, staple
#   scripts/dist.sh --no-notarize   # dry run (signs with whatever identity is available)
set -euo pipefail
cd "$(dirname "$0")/.."

# Local overrides (bundle ID, identities) — see local.env.example
[[ -f local.env ]] && { set -a; source local.env; set +a; }

NOTARIZE=1
[[ "${1:-}" == "--no-notarize" ]] && NOTARIZE=0

PROFILE="${DOCKPEEK_NOTARY_PROFILE:-dockpeek}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
OUT="dist"
APP="$OUT/DockPeek.app"
DMG="$OUT/DockPeek-$VERSION.dmg"

# Pick the Developer ID identity automatically.
IDENTITY="${DOCKPEEK_DIST_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"
if [[ -z "$IDENTITY" ]]; then
  if [[ $NOTARIZE == 1 ]]; then
    echo "✗ No 'Developer ID Application' certificate found in your keychain."
    echo "  Xcode → Settings → Accounts → your team → Manage Certificates → + → Developer ID Application"
    exit 1
  fi
  IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)
  echo "⚠︎ Dry run: signing with '$IDENTITY' (not distributable)"
fi
echo "→ Signing identity: $IDENTITY"

echo "→ Building universal binary (Apple Silicon + Intel)…"
swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release/DockPeek

if [[ ! -f Resources/AppIcon.icns ]]; then
  swift scripts/make-icon.swift Resources/AppIcon
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
  rm -rf Resources/AppIcon.iconset
fi

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DockPeek"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${DOCKPEEK_BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DOCKPEEK_BUNDLE_ID" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "→ Codesigning with hardened runtime…"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "→ Creating disk image…"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "DockPeek $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ $NOTARIZE == 1 ]]; then
  echo "→ Submitting to Apple notary service (usually 1–5 min)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  echo "→ Stapling ticket…"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

echo "✓ $DMG"
