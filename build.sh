#!/bin/zsh
# Builds "Notch Agents.app" next to this script.
set -euo pipefail
cd "${0:A:h}"
swift build -c release
APP="Notch Agents.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/NotchAgents "$APP/Contents/MacOS/NotchAgents"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.notch-agents</string>
<key>CFBundleName</key><string>Notch Agents</string>
<key>CFBundleExecutable</key><string>NotchAgents</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
P
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $PWD/$APP"
