#!/bin/bash
# Install and run RuntimeApp.app on a simulator, then report rendering output.
#   ./run-sim.sh [seconds]      (default 40)
# Env: SPIKE_DEVICE (device name, default SpikePhone), BUNDLE_ID, RT_* passthrough.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SECS="${1:-40}"
DEVICE="${SPIKE_DEVICE:-SpikePhone}"
BUNDLE_ID="io.github.h3nb.jlmodplus.runtime"
APP="$ROOT/build/RuntimeApp.app"
LOG="$ROOT/build/run.log"

[ -d "$APP" ] || { echo "missing $APP (run build-sim.sh)" >&2; exit 1; }

UDID=$(xcrun simctl list devices -j | python3 -c '
import json,sys
name=sys.argv[1]
d=json.load(sys.stdin)["devices"]
for runtime,devs in d.items():
    for dev in devs:
        if dev["name"]==name:
            print(dev["udid"]); raise SystemExit
' "$DEVICE")
if [ -z "$UDID" ]; then
    UDID=$(xcrun simctl create "$DEVICE" com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro)
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
BUNDLE=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" app)
mkdir -p "$DATA/save" "$DATA/snap"
rm -f "$DATA"/snap/*.png 2>/dev/null || true

GAME_JAR="$BUNDLE/jars/game.jar"
if [ -n "$MIDLET_JAR" ]; then
    # The runtime reads game jars from the bundle; a host path outside the app
    # container stalls in the zip reader on the simulator.
    cp "$MIDLET_JAR" "$GAME_JAR"
fi
echo "device=$DEVICE udid=$UDID bundle=$BUNDLE jar=$GAME_JAR"
SIMCTL_CHILD_RT_RES_ROOT="$BUNDLE/jars" \
SIMCTL_CHILD_RT_SAVE_ROOT="$DATA/save" \
SIMCTL_CHILD_RT_SNAPSHOT_DIR="$DATA/snap" \
SIMCTL_CHILD_RT_MIDLET_JAR="$GAME_JAR" \
SIMCTL_CHILD_RT_WIDTH="${RT_WIDTH:-240}" \
SIMCTL_CHILD_RT_HEIGHT="${RT_HEIGHT:-320}" \
SIMCTL_CHILD_RT_FPS_LIMIT="${RT_FPS_LIMIT:-0}" \
xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" > "$LOG" 2>&1 &
LP=$!
if [ -n "$RT_SHOTS" ]; then
    # RT_SHOTS="10 18 26": screenshot at each elapsed second, e.g. to verify
    # successive Displayable screens in one run.
    PREV=0
    for T in $RT_SHOTS; do
        sleep $((T - PREV))
        PREV=$T
        xcrun simctl io "$UDID" screenshot "$ROOT/build/shot-$T.png" >/dev/null 2>&1 || true
    done
else
    sleep "$SECS"
    xcrun simctl io "$UDID" screenshot "$ROOT/build/run.png" >/dev/null 2>&1 || true
fi
kill $LP 2>/dev/null || true

echo "=== log: $LOG ==="
grep -E '^\[RT\]|JVM Bridge|Display|MIDletRunner|error|Error|crash' "$LOG" | tail -40 || tail -40 "$LOG"
echo "=== screenshot: $ROOT/build/run.png ==="
echo "=== snapshots ==="
ls -la "$DATA/snap" 2>/dev/null | tail -5
echo "$DATA/snap"
