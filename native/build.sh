#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NATIVE="$ROOT/native"
APP="$NATIVE/dist/Voice Calc Studio.app"
BUILD_ROOT="$NATIVE/.build"

if [ -e "$APP" ] && [ "${1-}" != "--replace-build" ]; then
  echo "Build output already exists. Review it, then pass --replace-build to replace it." >&2
  exit 2
fi

mkdir -p "$BUILD_ROOT" "$NATIVE/dist"
if [ -e "$APP" ]; then rm -rf "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$BUILD_ROOT/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>VoiceCalcStudio</string>
  <key>CFBundleIdentifier</key><string>com.gmperkinsmba.voicecalcstudio.native</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Voice Calc Studio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Voice Calc Studio listens while you hold the selected shortcut.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Voice Calc Studio converts your spoken calculation into text on this Mac.</string>
</dict>
</plist>
PLIST

swiftc -parse-as-library -O \
  "$NATIVE/Sources/MathParser.swift" \
  "$NATIVE/Sources/VoiceCalcCore.swift" \
  "$NATIVE/Sources/main.swift" \
  -framework AppKit -framework AVFoundation -framework ApplicationServices \
  -framework CoreGraphics -framework Speech \
  -o "$APP/Contents/MacOS/VoiceCalcStudio"
cp "$BUILD_ROOT/Info.plist" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP"
