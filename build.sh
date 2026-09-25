#!/bin/bash
# ./build.sh            -> build/SleepLess.app
# ./build.sh install    -> also copy to /Applications and launch
# ./build.sh uninstall  -> remove the root lid helper (restoring normal sleep), the package receipt and the app
set -euo pipefail
cd "$(dirname "$0")"

# A quit event, not a kill: only a proper quit runs the app's hand-backs (brightness, the keyboard light, the charging light).
quit_app() {
  osascript -e 'tell application id "io.github.cyborgfingers.sleepless" to quit' 2>/dev/null || true
  for _ in $(seq 1 50); do pgrep -x SleepLess >/dev/null || return 0; sleep 0.2; done
  pkill -x SleepLess || true
}

if [[ "${1:-}" == "uninstall" ]]; then
  quit_app
  sudo /bin/sh sleepless-helper.sh uninstall
  sudo pkgutil --forget io.github.cyborgfingers.sleepless.pkg 2>/dev/null || true   # the Installer package's receipt, if it came that way
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
# The root-side gate on helper updates (tools/helper-verify.swift), cached: it only changes when its source does.
[[ build/helper-verify -nt tools/helper-verify.swift ]] || swiftc -O tools/helper-verify.swift -o build/helper-verify
cp build/helper-verify "$APP/Contents/Resources/sleepless-verify"
[[ -f assets/AppIcon.icns ]] && cp assets/AppIcon.icns "$APP/Contents/Resources/"
swiftc -O -parse-as-library -target arm64-apple-macosx13.0 *.swift -o "$APP/Contents/MacOS/SleepLess"

# Signing: Developer ID when the certificate is in the keychain (or CF_SIGN_APP names an identity), ad-hoc otherwise —
# hardened runtime either way, so a dev build behaves like a release. The tools first (their hashes go into the helper
# manifest), the manifest next (signed with the publisher key when it is in the Keychain; release.sh insists on it —
# without it, an installed helper can't update itself from this build), the app last, sealing all of it.
SIGN_APP=${CF_SIGN_APP:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application:/ {print $2; exit}')}
if [[ -n "$SIGN_APP" ]]; then
  SIGN=(--sign "$SIGN_APP" --options runtime --timestamp)
else
  SIGN=(--sign - --options runtime)
  echo "note: no Developer ID Application certificate in the keychain — ad-hoc signed (a download of this build would need Gatekeeper's Open Anyway)"
fi
codesign --force "${SIGN[@]}" "$APP/Contents/Resources/sleepless-led" "$APP/Contents/Resources/sleepless-verify"
(cd "$APP/Contents/Resources" && { echo "version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ../Info.plist)"
   shasum -a 256 sleepless-helper.sh sleepless-led sleepless-verify cyborgfingers.pub; } > helper-manifest)
if security find-generic-password -a cyborgfingers-updates -s "CyborgFingers update signing key" >/dev/null 2>&1; then
  [[ build/sign-update -nt tools/sign-update.swift ]] || swiftc -O tools/sign-update.swift -o build/sign-update
  build/sign-update sign "$APP/Contents/Resources/helper-manifest" >/dev/null
else
  echo "note: no publisher key in the Keychain, helper-manifest left unsigned (an installed helper won't update itself from this build)"
fi
codesign --force "${SIGN[@]}" "$APP"
echo "Built $APP${SIGN_APP:+ (Developer ID: $SIGN_APP)}"

if [[ "${1:-}" == "install" ]]; then
  quit_app
  rm -rf /Applications/SleepLess.app
  cp -R "$APP" /Applications/
  open /Applications/SleepLess.app
  echo "Installed + launched /Applications/SleepLess.app"
fi
