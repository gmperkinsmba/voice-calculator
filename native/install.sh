#!/bin/sh
set -eu

NATIVE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE="$NATIVE/dist/Voice Calculator.app"
DEST="$HOME/Applications/Voice Calculator.app"
BUNDLE_ID="com.gmperkinsmba.voicecalcstudio.native"

if [ ! -x "$SOURCE/Contents/MacOS/VoiceCalcStudio" ]; then
  echo "Build the app first with native/build.sh." >&2
  exit 2
fi
SOURCE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")
if [ "$SOURCE_ID" != "$BUNDLE_ID" ]; then
  echo "Refusing unexpected app bundle identifier: $SOURCE_ID" >&2
  exit 2
fi
if [ -e "$DEST" ] && [ "${1-}" != "--replace-voice-calculator" ]; then
  echo "Install destination exists. Review it, then pass --replace-voice-calculator to update." >&2
  exit 2
fi

exec python3 "$NATIVE/../install_security.py" \
  --source "$SOURCE" \
  --destination "$DEST" \
  --bundle-id "$BUNDLE_ID"
