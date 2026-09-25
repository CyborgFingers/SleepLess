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
echo "PASS"
