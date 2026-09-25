#!/bin/bash
# ./build.sh            -> build/SleepLess.app
# ./build.sh install    -> also copy to /Applications and launch
# ./build.sh uninstall  -> remove the root lid helper (restoring normal sleep) and the app
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "uninstall" ]]; then
  pkill -x SleepLess || true
  sudo /bin/sh sleepless-helper.sh uninstall
  rm -rf /Applications/SleepLess.app
  echo "Removed. Also untick SleepLess in System Settings > General > Login Items if it's still listed."
  exit 0
fi

APP=build/SleepLess.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
cp sleepless-helper.sh LICENSE "$APP/Contents/Resources/"
clang -O2 -Wall -target arm64-apple-macosx13.0 -o "$APP/Contents/Resources/sleepless-led" sleepless-led.c -framework IOKit -framework CoreFoundation
[[ -f assets/AppIcon.icns ]] && cp assets/AppIcon.icns "$APP/Contents/Resources/"
swiftc -O -parse-as-library -target arm64-apple-macosx13.0 *.swift -o "$APP/Contents/MacOS/SleepLess"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x SleepLess || true
  rm -rf /Applications/SleepLess.app
  cp -R "$APP" /Applications/
  open /Applications/SleepLess.app
  echo "Installed + launched /Applications/SleepLess.app"
fi
