#!/bin/bash
# Compile iosRuntime/test/*.java into a runnable MIDlet jar.
#   ./make-test-jar.sh                          -> build/test.jar (test/manifest.mf, InputProbe)
#   ./make-test-jar.sh test/network-probe.mf    -> build/network-probe.jar (NetworkProbe)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
: "${JAVA_HOME:?set JAVA_HOME to a JDK 17+ install}"
export PATH="$JAVA_HOME/bin:$PATH"

MANIFEST="${1:-$ROOT/test/manifest.mf}"
[ -f "$MANIFEST" ] || { echo "missing manifest $MANIFEST" >&2; exit 1; }
case "$MANIFEST" in
    *network-probe.mf) OUT="$ROOT/build/network-probe.jar" ;;
    *) OUT="$ROOT/build/test.jar" ;;
esac

API="$ROOT/build/j2me_api.jar"
[ -f "$API" ] || { echo "missing $API (run build-sim.sh first)" >&2; exit 1; }
# javax.microedition.io lives in the engine runtime jar (miniJVM ships its own
# Connector), so probes compile against both jars.
BOOT="$ROOT/build/RuntimeApp.app/jars/minijvm_rt.jar"
[ -f "$BOOT" ] || { echo "missing $BOOT (run build-sim.sh first)" >&2; exit 1; }

rm -rf "$ROOT/build/test-classes"
mkdir -p "$ROOT/build/test-classes"
find "$ROOT/test" -name '*.java' > "$ROOT/build/test-sources.txt"
javac --release 8 -nowarn -cp "$BOOT:$API" -d "$ROOT/build/test-classes" @"$ROOT/build/test-sources.txt"
jar cfm "$OUT" "$MANIFEST" -C "$ROOT/build/test-classes" .
rm -f "$ROOT/build/test-sources.txt"
echo "built: $OUT"
