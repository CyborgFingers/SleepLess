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
echo "PASS"
