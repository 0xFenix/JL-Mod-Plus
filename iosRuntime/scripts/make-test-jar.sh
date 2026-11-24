#!/bin/bash
# Compile iosRuntime/test/MIDlet sources into build/test.jar for automated runs.
#   ./make-test-jar.sh            (all sources under test/)
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
: "${JAVA_HOME:?set JAVA_HOME to a JDK 17+ install}"
export PATH="$JAVA_HOME/bin:$PATH"

API="$ROOT/build/j2me_api.jar"
OUT="$ROOT/build/test.jar"
[ -f "$API" ] || { echo "missing $API (run build-sim.sh first)" >&2; exit 1; }

rm -rf "$ROOT/build/test-classes"
mkdir -p "$ROOT/build/test-classes"
find "$ROOT/test" -name '*.java' > "$ROOT/build/test-sources.txt"
javac --release 8 -nowarn -cp "$API" -d "$ROOT/build/test-classes" @"$ROOT/build/test-sources.txt"
jar cfm "$OUT" "$ROOT/test/manifest.mf" -C "$ROOT/build/test-classes" .
rm -f "$ROOT/build/test-sources.txt"
echo "built: $OUT"
