#!/bin/bash
# Builds ThermalMonitor.app and, unless --no-install is passed, installs it into
# /Applications and launches it.
set -euo pipefail

cd "$(dirname "$0")"

APP="ThermalMonitor.app"
INSTALLED="/Applications/$APP"
CONTENTS="$APP/Contents"

echo "Generating icon..."
swift make_icon.swift
iconutil -c icns AppIcon.iconset -o AppIcon.icns

echo "Building release binary..."
swift build -c release

echo "Creating $APP..."
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp .build/release/ThermalMonitor "$CONTENTS/MacOS/"
cp AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
cp Info.plist "$CONTENTS/Info.plist"

# Ad-hoc signature. Enough for Gatekeeper to run a locally built app and for
# SMAppService to register it as a login item; no Apple Developer account needed.
echo "Signing..."
codesign --force --sign - "$APP"

if [ "${1:-}" = "--no-install" ]; then
    echo "Built $APP (not installed)."
    exit 0
fi

echo "Installing to $INSTALLED..."
# Quit any copy that is already running, otherwise the replaced binary keeps polling.
osascript -e 'tell application "ThermalMonitor" to quit' 2>/dev/null || true
pkill -x ThermalMonitor 2>/dev/null || true
sleep 1
rm -rf "$INSTALLED"
cp -R "$APP" "$INSTALLED"

# Drop the quarantine flag so the first launch does not need a right-click → Open.
xattr -dr com.apple.quarantine "$INSTALLED" 2>/dev/null || true

echo "Launching..."
open "$INSTALLED"

echo
echo "Done — look for the thermometer in your menu bar."
