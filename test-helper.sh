#!/bin/sh
# Checks sleepless-helper.sh's apply/watchdog logic against a fake pmset — no root needed.
set -eu
cd "$(dirname "$0")"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat > "$T/pmset" <<'EOF'
#!/bin/sh
if [ "$1" = -g ]; then printf ' SleepDisabled\t\t%s\n' "$(cat "$FAKE_STATE")"; else echo "$3" > "$FAKE_STATE"; fi
EOF
chmod +x "$T/pmset"
export SLEEPLESS_DIR="$T" SLEEPLESS_PMSET="$T/pmset" FAKE_STATE="$T/state"

run() { sh sleepless-helper.sh; }
check() { [ "$(cat "$T/state")" = "$1" ] || { echo "FAIL: $2 (SleepDisabled=$(cat "$T/state"), want $1)"; exit 1; }; echo "ok   $2"; }

echo 0 > "$T/state"; echo 1 > "$T/lid";              run; check 1 "fresh request turns sleep off"
touch -t 202001010000 "$T/lid";                        run; check 0 "stale request (app dead) restores sleep"
echo 1 > "$T/state"; echo 0 > "$T/lid";                run; check 1 "leaves a SleepDisabled someone else set"
echo 1 > "$T/lid"; run; echo 0 > "$T/lid";             run; check 0 "request 0 undoes our own SleepDisabled"

# The MagSafe light, against a fake sleepless-led that logs its argument.
printf '#!/bin/sh\necho "$1" >> "$FAKE_LED_LOG"\n' > "$T/led-tool"
chmod +x "$T/led-tool"
export SLEEPLESS_LED="$T/led-tool" FAKE_LED_LOG="$T/led.log"
calls() { tr '\n' ' ' < "$T/led.log" 2>/dev/null | sed 's/ $//'; }
led() { [ "$(calls)" = "$1" ] || { echo "FAIL: $2 (tool calls '$(calls)', want '$1')"; exit 1; }; echo "ok   $2"; }
request() { echo "$1" > "$T/led"; touch -t "$2" "$T/led"; }

request off 202601010000;             run; led "off" "lid closed: light off"
                                      run; led "off" "an unchanged request is not applied again"
request on 202601010001;              run; led "off on" "lid open: light back to normal"
request 'off; rm -rf /' 202601010002; run; led "off on" "anything but off/on never reaches the tool"
echo 1 > "$T/lid"; request off 202601010003; run; led "off on off" "light off again, lid-closed mode on"
touch -t 202001010000 "$T/lid";       run; led "off on off on" "app dead with the light off: watchdog puts it back"
                                      run; led "off on off on" "…exactly once"

# Signed helper updates, from a fake app bundle. Only a manifest signed by the (test) publisher key, with every hash
# matching and no downgrade, gets installed; everything else leaves the installed helper exactly as it was.
TOOLS="$T/tools"; mkdir -p "$TOOLS"; export SLEEPLESS_TOOLS="$TOOLS"
[ build/sign-update -nt tools/sign-update.swift ] || swiftc -O tools/sign-update.swift -o build/sign-update
[ build/helper-verify -nt tools/helper-verify.swift ] || swiftc -O tools/helper-verify.swift -o build/helper-verify
PUB=$(build/sign-update testkey "$T/key")
build/sign-update testkey "$T/badkey" >/dev/null
LABEL=io.github.cyborgfingers.sleepless.lid
RES="$T/Fake.app/Contents/Resources"; mkdir -p "$RES"
bundle() {   # $1 = version, $2 = key dir: a fake app bundle carrying this helper, a new led tool, the verifier, the key, a signed manifest
  cp sleepless-helper.sh "$RES/"; printf '#!/bin/sh\necho new-led\n' > "$RES/sleepless-led"; cp build/helper-verify "$RES/sleepless-verify"; echo "$PUB" > "$RES/cyborgfingers.pub"
  (cd "$RES" && { echo "version $1"; shasum -a 256 sleepless-helper.sh sleepless-led sleepless-verify cyborgfingers.pub; } > helper-manifest)
  build/sign-update sign "$RES/helper-manifest" --key-file "$2/private.key" >/dev/null
}
installed() {   # the installed set before the update: an old script, the verifier, the key, a 1.1.0 manifest
  echo old > "$TOOLS/$LABEL.sh"; cp build/helper-verify "$TOOLS/$LABEL.verify"; echo "$PUB" > "$TOOLS/$LABEL.pub"; echo "version 1.1.0" > "$TOOLS/$LABEL.manifest"
  rm -f "$T/update" "$T/update.applied"
}
M=0
ask() { M=$((M + 1)); echo "$T/Fake.app" > "$T/update"; touch -t "203001010100.$(printf %02d $M)" "$T/update"; run; }
untouched() { [ "$(cat "$TOOLS/$LABEL.sh")" = old ] && [ "$(cat "$TOOLS/$LABEL.manifest")" = "version 1.1.0" ] || { echo "FAIL: $1 changed the installed helper"; exit 1; }; echo "ok   $1"; }

installed; bundle 1.2.0 "$T/key"; ask
cmp -s "$TOOLS/$LABEL.sh" sleepless-helper.sh && [ "$(head -n 1 "$TOOLS/$LABEL.manifest")" = "version 1.2.0" ] && [ "$(sh "$SLEEPLESS_LED")" = new-led ] \
  && cmp -s "$TOOLS/$LABEL.verify" build/helper-verify && [ ! -e "$TOOLS/$LABEL.sh.new" ] && [ -z "$(ls -d "$T"/stage.* 2>/dev/null)" ] \
  || { echo "FAIL: a signed update was not installed"; exit 1; }; echo "ok   signed helper update installed: script, light tool, verifier, manifest; stage removed"
echo old > "$TOOLS/$LABEL.sh"; run; [ "$(cat "$TOOLS/$LABEL.sh")" = old ] || { echo "FAIL: an applied update request was applied again"; exit 1; }; echo "ok   the same request is never applied again"
installed; bundle 1.2.0 "$T/key"; echo tampered >> "$RES/sleepless-led"; ask; untouched "a file changed after signing is refused"
installed; bundle 1.2.0 "$T/badkey"; ask; untouched "a manifest signed with the wrong key is refused"
installed; bundle 1.0.0 "$T/key"; ask; untouched "a downgrade is refused"
installed; bundle 1.2.0 "$T/key"; rm "$RES/helper-manifest.sig"; ask; untouched "an unsigned bundle is refused"
installed; bundle 1.2.0 "$T/key"; ln -s "$T/Fake.app" "$T/update"; run; untouched "a symlinked request is ignored"
installed; bundle 1.2.0 "$T/key"; echo "/etc" > "$T/update"; run; untouched "a request that isn't an app bundle path is ignored"
echo "PASS"
