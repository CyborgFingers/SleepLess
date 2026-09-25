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
set -u
LABEL=io.github.cyborgfingers.sleepless.lid
DIR="${SLEEPLESS_DIR:-/Library/Application Support/SleepLess}"   # overrides exist only for test-helper.sh
PMSET="${SLEEPLESS_PMSET:-/usr/bin/pmset}"
REQ="$DIR/lid"       # user-owned file in a root-owned dir: the app can rewrite it, never swap it for a link
OWNED="$DIR/owned"   # marker: the current SleepDisabled=1 is ours
BIN=/Library/PrivilegedHelperTools/$LABEL.sh
PLIST=/Library/LaunchDaemons/$LABEL.plist
STALE=90

apply() {
  want=0
  if [ "$(head -c 1 "$REQ" 2>/dev/null)" = 1 ] && [ $(( $(date +%s) - $(stat -f %m "$REQ") )) -lt $STALE ]; then
    want=1
  fi
  have=$("$PMSET" -g | awk '/SleepDisabled/ {print $2}')
  if [ $want = 1 ]; then
    [ "$have" = 1 ] || "$PMSET" -a disablesleep 1
    touch "$OWNED"
  elif [ -e "$OWNED" ]; then
    [ "$have" = 0 ] || "$PMSET" -a disablesleep 0
    rm -f "$OWNED"
  fi
}

install_helper() {
  install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools "$DIR"
  install -o root -g wheel -m 755 "$0" "$BIN"
  [ -f "$REQ" ] || echo 0 > "$REQ"
  chown "$1" "$REQ"
  chmod 644 "$REQ"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key><array><string>/bin/sh</string><string>$BIN</string></array>
	<key>WatchPaths</key><array><string>$REQ</string></array>
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
  rm -rf "$DIR" "$BIN" "$PLIST"
}

case "${1:-}" in
  install) install_helper "$2" ;;
  uninstall) uninstall_helper ;;
  *) apply ;;
esac
