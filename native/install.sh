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
codesign --verify --deep --strict "$SOURCE"

mkdir -p "$HOME/Applications"
BACKUP=""
if [ -e "$DEST" ]; then
  if [ "${1-}" != "--replace-voice-calculator" ]; then
    echo "Install destination exists. Review it, then pass --replace-voice-calculator to update." >&2
    exit 2
  fi
  DEST_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)
  if [ "$DEST_ID" != "$BUNDLE_ID" ]; then
    echo "Refusing to replace an app with bundle identifier '$DEST_ID'." >&2
    exit 2
  fi
  BACKUP="$HOME/Applications/Voice Calculator.app.backup.$(date +%Y%m%d%H%M%S)"
  mv "$DEST" "$BACKUP"
fi

if ditto "$SOURCE" "$DEST"; then
  codesign --verify --deep --strict "$DEST"
  echo "Installed $DEST"
  if [ -n "$BACKUP" ]; then echo "Previous version preserved at $BACKUP"; fi
else
  if [ -n "$BACKUP" ] && [ ! -e "$DEST" ]; then mv "$BACKUP" "$DEST"; fi
  echo "Install failed; previous version was preserved." >&2
  exit 1
fi
