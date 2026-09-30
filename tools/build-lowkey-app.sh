#!/usr/bin/env bash
# Build Lowkey.app (the native menu-bar dictation app) and install it to
# ~/Applications. Needs only the Command Line Tools.
#
#   tools/make-signing-identity.sh   # once
#   tools/build-lowkey-app.sh        # build, sign, install
#   tools/build-lowkey-app.sh --no-install --out /tmp/Lowkey.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/tmux-whisperd"
APP_NAME="Lowkey"
BUNDLE_ID="com.ricardo-nth.lowkey"
IDENTITY="${LOWKEY_SIGNING_IDENTITY:-Lowkey Local Code Signing}"
OUT="$HOME/Applications/$APP_NAME.app"
INSTALL=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift ;;
    --no-install) INSTALL=0 ;;
    --identity) IDENTITY="$2"; shift ;;
    *) echo "usage: $0 [--out PATH.app] [--no-install] [--identity NAME]" >&2; exit 2 ;;
  esac
  shift
done

version="$(sed -n 's/^TMUX_WHISPER_CLI_VERSION="\(.*\)"$/\1/p' "$ROOT/bin/tmux-whisper")"
build_number="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

echo "Building $APP_NAME $version ($build_number)…"
(cd "$PKG" && swift build -c release --product "$APP_NAME")
binary="$PKG/.build/release/$APP_NAME"
[[ -x "$binary" ]] || { echo "build did not produce $binary" >&2; exit 1; }

stage="$(mktemp -d)/$APP_NAME.app"
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources"
cp "$binary" "$stage/Contents/MacOS/$APP_NAME"
cat >"$stage/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleName</key><string>$APP_NAME</string>
	<key>CFBundleDisplayName</key><string>$APP_NAME</string>
	<key>CFBundleExecutable</key><string>$APP_NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$version</string>
	<key>CFBundleVersion</key><string>$build_number</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSMicrophoneUsageDescription</key><string>Lowkey records your voice while dictation is active and transcribes it locally on this Mac.</string>
</dict>
</plist>
PLIST
plutil -lint "$stage/Contents/Info.plist" >/dev/null

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --options runtime --timestamp=none \
    --entitlements "$PKG/App/Lowkey.entitlements" \
    --sign "$IDENTITY" "$stage"
  echo "Signed with: $IDENTITY"
else
  echo "warning: signing identity \"$IDENTITY\" not found; signing ad hoc." >&2
  echo "         Permissions will reset on every rebuild. Run tools/make-signing-identity.sh." >&2
  codesign --force --options runtime --entitlements "$PKG/App/Lowkey.entitlements" --sign - "$stage"
fi
codesign --verify --strict "$stage"

if [[ "$INSTALL" == "1" || "$OUT" != "$HOME/Applications/$APP_NAME.app" ]]; then
  mkdir -p "$(dirname "$OUT")"
  if [[ -d "$OUT" ]]; then
    # Quit a running copy so the new build takes over.
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    sleep 0.5
    rm -rf "$OUT"
  fi
  ditto "$stage" "$OUT"
  echo "Installed: $OUT"
fi
rm -rf "$(dirname "$stage")"
