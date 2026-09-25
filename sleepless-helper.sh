#!/bin/sh
# SleepLess lid-closed helper — the only part that runs as root.
#   sleepless-helper.sh install <user>   one-time, from the app's admin prompt
#   sleepless-helper.sh uninstall        sudo, from ./build.sh uninstall
#   sleepless-helper.sh                  launchd: apply the app's request
#
# Only SleepDisabled (`pmset -a disablesleep 1`) beats lid-close sleep, and only root can set it.
# The app writes 1/0 to $REQ and rewrites it every 30 s while it wants lid-closed awake. launchd runs
# this on every write and every 30 s. Watchdog: a request older than 90 s (app quit, crashed or hung)
# counts as 0, so the Mac can never get stuck unable to sleep. We only undo a SleepDisabled we set.
#
# The MagSafe charging light: the app writes `off` (lid closed) or `on` (lid open) to $LEDREQ and the compiled
# sleepless-led tool applies it. Only a changed request is applied, so the 30 s runs never fight macOS; if the
# app dies with the light off, the watchdog above also puts the light back.
#
# Updating itself: a new app version writes its bundle path to $UPDREQ. The files are copied out of the bundle into a
# root-owned stage first, and installed only if sleepless-verify (root-owned, installed here at setup) accepts the
# manifest's Ed25519 signature against the root-owned publisher key, every file's hash, and the version (never a
# downgrade). So the one admin prompt at setup is the last one: later helpers arrive signed, or not at all.
set -u
LABEL=io.github.cyborgfingers.sleepless.lid
DIR="${SLEEPLESS_DIR:-/Library/Application Support/SleepLess}"   # overrides exist only for test-helper.sh
PMSET="${SLEEPLESS_PMSET:-/usr/bin/pmset}"
TOOLS="${SLEEPLESS_TOOLS:-/Library/PrivilegedHelperTools}"
REQ="$DIR/lid"       # user-owned file in a root-owned dir: the app can rewrite it, never swap it for a link
OWNED="$DIR/owned"   # marker: the current SleepDisabled=1 is ours
LEDREQ="$DIR/led"    # user-owned, like $REQ: `off` or `on`
LEDDONE="$DIR/led.applied"   # the request we last applied (mtime + token)
LEDOFF="$DIR/led.off"        # marker: the light is off because of us
UPDREQ="$DIR/update"         # user-owned, like $REQ: the path of the app bundle to take a signed helper update from
UPDDONE="$DIR/update.applied"
BIN=$TOOLS/$LABEL.sh
LED="${SLEEPLESS_LED:-$TOOLS/io.github.cyborgfingers.sleepless.led}"
VERIFY=$TOOLS/$LABEL.verify
KEY=$TOOLS/$LABEL.pub
MANIFEST=$TOOLS/$LABEL.manifest
PLIST=/Library/LaunchDaemons/$LABEL.plist
STALE=90

apply() {
  want=0
  stale=0
  if [ "$(head -c 1 "$REQ" 2>/dev/null)" = 1 ]; then
    if [ $(( $(date +%s) - $(stat -f %m "$REQ") )) -lt $STALE ]; then want=1; else stale=1; fi
  fi
  have=$("$PMSET" -g | awk '/SleepDisabled/ {print $2}')
  if [ $want = 1 ]; then
    [ "$have" = 1 ] || "$PMSET" -a disablesleep 1
    touch "$OWNED"
  elif [ -e "$OWNED" ]; then
    [ "$have" = 0 ] || "$PMSET" -a disablesleep 0
    rm -f "$OWNED"
  fi
  apply_led
  apply_update
}

apply_led() {
  [ -x "$LED" ] || return 0
  if [ $stale = 1 ] && [ -e "$LEDOFF" ]; then   # the app died with the light off
    "$LED" on && rm -f "$LEDOFF"
    return 0
  fi
  token=$(head -n 1 "$LEDREQ" 2>/dev/null)
  case "$token" in off|on) ;; *) return 0 ;; esac   # nothing else ever reaches the tool
  stamp="$(stat -f %m "$LEDREQ") $token"
  [ "$stamp" = "$(cat "$LEDDONE" 2>/dev/null)" ] && return 0
  "$LED" "$token" || return 0
  echo "$stamp" > "$LEDDONE"
  if [ "$token" = off ]; then touch "$LEDOFF"; else rm -f "$LEDOFF"; fi
}

# One request per bundle path and modification time, tried once whatever happens. Only regular copies are verified
# and installed; each file lands with a rename, so a half-written helper can never exist.
apply_update() {
  [ -f "$UPDREQ" ] && [ ! -L "$UPDREQ" ] || return 0
  stamp="$(stat -f %m "$UPDREQ") $(head -c 1024 "$UPDREQ" | head -n 1)"
  [ "$stamp" = "$(cat "$UPDDONE" 2>/dev/null)" ] && return 0
  echo "$stamp" > "$UPDDONE"
  app=${stamp#* }
  case "$app" in /*.app) ;; *) return 0 ;; esac
  res="$app/Contents/Resources"
  [ -d "$res" ] && [ -x "$VERIFY" ] || return 0
  stage=$(mktemp -d "$DIR/stage.XXXXXX") || return 0
  ok=1
  for f in sleepless-helper.sh sleepless-led sleepless-verify cyborgfingers.pub helper-manifest helper-manifest.sig; do
    cp "$res/$f" "$stage/$f" 2>/dev/null || ok=0
  done
  if [ $ok = 1 ] && "$VERIFY" "$KEY" "$stage" "$MANIFEST" >/dev/null 2>&1; then
    for f in sleepless-helper.sh:"$BIN" sleepless-led:"$LED" sleepless-verify:"$VERIFY" cyborgfingers.pub:"$KEY" helper-manifest:"$MANIFEST"; do
      case "${f%%:*}" in *.pub|helper-manifest) mode=644 ;; *) mode=755 ;; esac
      cp "$stage/${f%%:*}" "${f#*:}.new" && chmod $mode "${f#*:}.new" && mv -f "${f#*:}.new" "${f#*:}"
    done
  fi
  rm -r "$stage"
}

install_helper() {
  install -d -o root -g wheel -m 755 "$TOOLS" "$DIR"
  install -o root -g wheel -m 755 "$0" "$BIN"
  install -o root -g wheel -m 755 "$(dirname "$0")/sleepless-led" "$LED"   # copied: never run from the user-writable bundle
  install -o root -g wheel -m 755 "$(dirname "$0")/sleepless-verify" "$VERIFY"
  install -o root -g wheel -m 644 "$(dirname "$0")/cyborgfingers.pub" "$KEY"
  install -o root -g wheel -m 644 "$(dirname "$0")/helper-manifest" "$MANIFEST"
  [ -f "$REQ" ] || echo 0 > "$REQ"
  [ -f "$LEDREQ" ] || echo on > "$LEDREQ"
  [ -f "$UPDREQ" ] || : > "$UPDREQ"
  chown "$1" "$REQ" "$LEDREQ" "$UPDREQ"
  chmod 644 "$REQ" "$LEDREQ" "$UPDREQ"
  echo "$(stat -f %m "$UPDREQ") $(head -n 1 "$UPDREQ")" > "$UPDDONE"   # whatever is in it now is not a new request
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key><array><string>/bin/sh</string><string>$BIN</string></array>
	<key>WatchPaths</key><array><string>$REQ</string><string>$LEDREQ</string><string>$UPDREQ</string></array>
	<key>StartInterval</key><integer>30</integer>
	<key>ThrottleInterval</key><integer>2</integer>
	<key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
  chown root:wheel "$PLIST"
  chmod 644 "$PLIST"
  launchctl bootout system/$LABEL 2>/dev/null
  launchctl bootstrap system "$PLIST"
}

uninstall_helper() {
  launchctl bootout system/$LABEL 2>/dev/null
  [ -f "$REQ" ] && echo 0 > "$REQ"
  apply
  [ -e "$LEDOFF" ] && [ -x "$LED" ] && "$LED" on
  rm -rf "$DIR" "$BIN" "$LED" "$VERIFY" "$KEY" "$MANIFEST" "$PLIST"
}

case "${1:-}" in
  install) install_helper "$2" ;;
  uninstall) uninstall_helper ;;
  *) apply ;;
esac
