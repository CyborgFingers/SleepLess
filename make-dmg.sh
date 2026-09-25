#!/bin/bash
# ./make-dmg.sh  ->  build/SleepLess.dmg, the drag-to-Applications installer attached to GitHub releases.
# Keep the asset name fixed: https://github.com/CyborgFingers/SleepLess/releases/latest/download/SleepLess.dmg
# (the download button) always serves the newest release.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
VOL=SleepLess
./build.sh

WORK=$(mktemp -d)
DEV=""
cleanup() { [[ -n "$DEV" ]] && hdiutil detach "$DEV" -quiet 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
cp -R build/SleepLess.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swiftc -O assets/make-dmg-background.swift -o "$WORK/bg"
"$WORK/bg" "$VERSION" "$WORK"
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$STAGE/.background/background.tiff" 2>/dev/null

[[ -d "/Volumes/$VOL" ]] && hdiutil detach "/Volumes/$VOL" -quiet
hdiutil create -quiet -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size 24m -ov "$WORK/rw.dmg"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk '/Apple_HFS/ {print $1}')

# Window layout: 640×400 content, no toolbar, big icons over the background's label band.
osascript <<EOF
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "SleepLess.app" of container window to {160, 180}
    set position of item "Applications" of container window to {480, 180}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
# Volume icon last: hdiutil -srcfolder drops it, and the Finder layout pass above removes it too.
cp assets/AppIcon.icns "/Volumes/$VOL/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOL"
sync
hdiutil detach "$DEV" -quiet
DEV=""

rm -f build/SleepLess.dmg
hdiutil convert "$WORK/rw.dmg" -quiet -format ULFO -o build/SleepLess.dmg
# The licence agreement macOS shows (Agree / Disagree) before the DMG opens.
python3 assets/make-sla.py LICENSE "$WORK/sla.xml"
hdiutil udifrez -xml "$WORK/sla.xml" '' -quiet build/SleepLess.dmg
echo "Built build/SleepLess.dmg (SleepLess $VERSION)"
shasum -a 256 build/SleepLess.dmg
