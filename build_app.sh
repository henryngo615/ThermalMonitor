#!/bin/bash
set -e

APP="ThermalMonitor.app"
BINARY="ThermalMonitor"
BUNDLE="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"

echo "Generating icon..."
swift make_icon.swift 2>/dev/null
iconutil -c icns AppIcon.iconset -o AppIcon.icns

echo "Building release binary..."
swift build -c release

echo "Creating .app bundle..."
rm -rf "$APP"
mkdir -p "$BUNDLE" "$RESOURCES"

cp .build/release/$BINARY "$BUNDLE/"
cp AppIcon.icns "$RESOURCES/AppIcon.icns"

# Info.plist — LSUIElement hides Dock icon, required for menu bar apps
cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ThermalMonitor</string>
    <key>CFBundleIdentifier</key>
    <string>com.thermalmonitor.app</string>
    <key>CFBundleName</key>
    <string>ThermalMonitor</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
</dict>
</plist>
EOF

echo "Signing ad-hoc (no Apple Developer account required)..."
codesign --force --deep --sign - "$APP"

echo "Packaging..."
tar -czf ThermalMonitor.tar.gz "$APP"

echo ""
echo "Done!"
echo "  App bundle : $APP"
echo "  Shareable  : ThermalMonitor.tar.gz"
echo ""
echo "To install:"
echo "  tar -xzf ThermalMonitor.tar.gz"
echo "  mv ThermalMonitor.app /Applications/"
echo "  open /Applications/ThermalMonitor.app"
