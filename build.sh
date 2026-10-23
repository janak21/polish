#!/bin/bash
# Builds Polish.app, installs it to ~/Applications, and launches it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP="$HOME/Applications/Polish.app"

pkill -x Polish || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Polish" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp -R "$BIN"/*.bundle "$APP/Contents/Resources/" 2>/dev/null || true
cp Resources/*.png Resources/AppIcon.icns "$APP/Contents/Resources/"

# A real signature keeps the Accessibility permission across rebuilds. Without a developer
# certificate we sign ad-hoc, and Accessibility must be re-granted after each build.
IDENTITY="${SIGN_IDENTITY:-Apple Development}"
security find-identity -v -p codesigning | grep -q -- "$IDENTITY" || IDENTITY="-"
codesign --force --sign "$IDENTITY" "$APP"
/System/Library/CoreServices/pbs -update # refresh the Services menu
open "$APP"
