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
cp sleepless-helper.sh LICENSE cyborgfingers.pub "$APP/Contents/Resources/"
clang -O2 -Wall -target arm64-apple-macosx13.0 -o "$APP/Contents/Resources/sleepless-led" sleepless-led.c -framework IOKit -framework CoreFoundation
# The root-side gate on helper updates, and the manifest it checks: signed here when the publisher key is in the
# Keychain (release.sh insists on it); otherwise this build's helper can only be installed through the setup prompt.
[[ build/helper-verify -nt tools/helper-verify.swift ]] || swiftc -O tools/helper-verify.swift -o build/helper-verify
cp build/helper-verify "$APP/Contents/Resources/sleepless-verify"
(cd "$APP/Contents/Resources" && { echo "version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ../Info.plist)"
   shasum -a 256 sleepless-helper.sh sleepless-led sleepless-verify cyborgfingers.pub; } > helper-manifest)
if security find-generic-password -a cyborgfingers-updates -s "CyborgFingers update signing key" >/dev/null 2>&1; then
  [[ build/sign-update -nt tools/sign-update.swift ]] || swiftc -O tools/sign-update.swift -o build/sign-update
  build/sign-update sign "$APP/Contents/Resources/helper-manifest" >/dev/null
else
  echo "note: no publisher key in the Keychain, helper-manifest left unsigned (an installed helper won't update itself from this build)"
fi
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
