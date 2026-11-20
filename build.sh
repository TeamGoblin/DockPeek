#!/bin/zsh
# Builds DockPeek.app, signs it, and (with --install) installs to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")"

# Local overrides (bundle ID, identities) — see local.env.example
[[ -f local.env ]] && { set -a; source local.env; set +a; }

# Any local "Apple Development" identity works; override with DOCKPEEK_SIGN_IDENTITY.
IDENTITY="${DOCKPEEK_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
IDENTITY="${IDENTITY:--}"  # fall back to ad-hoc signing
APP="build/DockPeek.app"

# Builds for the Mac you are on (Apple Silicon or Intel).
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

if [[ ! -f Resources/AppIcon.icns ]]; then
  swift scripts/make-icon.swift Resources/AppIcon
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
  rm -rf Resources/AppIcon.iconset
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DockPeek" "$APP/Contents/MacOS/DockPeek"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${DOCKPEEK_BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DOCKPEEK_BUNDLE_ID" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x DockPeek 2>/dev/null && sleep 0.5 || true
  rm -rf /Applications/DockPeek.app
  cp -R "$APP" /Applications/DockPeek.app
  open /Applications/DockPeek.app
  echo "Installed and launched /Applications/DockPeek.app"
fi
