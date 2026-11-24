#!/bin/bash
# Build RuntimeApp.app (iosSimulatorArm64) around the vendored J2ME runtime.
#
#   MINIJVM_DIR   upstream miniJVM checkout (default ~/dev/miniJVM)
#   MIDLET_JAR    game jar to bundle (default ~/Downloads/Avatar_LAPRO.jar)
#   JAVA_HOME     JDK with javac/jar
#
# Output: iosRuntime/build/RuntimeApp.app plus build/j2me_api.jar.
# The miniJVM runtime jar is built from upstream sources at build time and is
# NOT stored in the repository (GPL-2.0 + Classpath-exception licensing).
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MINIJVM_DIR="${MINIJVM_DIR:-$HOME/dev/miniJVM}"
MIDLET_JAR="${MIDLET_JAR:-$HOME/Downloads/Avatar_LAPRO.jar}"
BUILD="$ROOT/build"
CSRC="$MINIJVM_DIR/minijvm/c"
RT_JAR="$MINIJVM_DIR/binary/lib/minijvm_rt.jar"
APP="$BUILD/RuntimeApp.app"
BUNDLE_ID="io.github.h3nb.jlmodplus.runtime"

: "${JAVA_HOME:?set JAVA_HOME to a JDK 17+}"
PATH="$JAVA_HOME/bin:$PATH"

[ -f "$CSRC/jvm/jvm.c" ] || { echo "miniJVM sources not found at $MINIJVM_DIR" >&2; exit 1; }

if [ ! -f "$RT_JAR" ]; then
    echo "building minijvm_rt.jar"
    ( cd "$MINIJVM_DIR/binary" && ./build_jar.sh >/dev/null )
fi

echo "building j2me_api.jar"
rm -rf "$BUILD/classes"
mkdir -p "$BUILD/classes"
find "$ROOT/java/src" -name '*.java' > "$BUILD/sources.txt"
javac --release 8 -nowarn -cp "$RT_JAR" -d "$BUILD/classes" @"$BUILD/sources.txt"
jar cf "$BUILD/j2me_api.jar" -C "$BUILD/classes" .

INCS="-I$CSRC -I$CSRC/jvm -I$CSRC/utils -I$CSRC/utils/https -I$CSRC/utils/https/mbedtls/include -I$CSRC/utils/mimalloc/include -I$ROOT/native"

echo "compiling runtime app (iosSimulatorArm64)"
CC="xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -O2 -fobjc-arc -Wno-everything"

# Engine: everything except the desktop entry point and the JIT backend
# (sljit does not compile for iOS targets; jit.h selects the interpreter).
# One compile+link invocation keeps the working tree clean of object files.
$CC -o "$BUILD/RuntimeApp" $INCS \
    $(find "$CSRC" -type f -name '*.c' \
        -not -name 'main.c' \
        -not -path "$CSRC/utils/sljit/*" \
        -not -path "$CSRC/utils/mimalloc/src/*" \
        -not -path "$CSRC/cmake-*" -not -path "$CSRC/.*") \
    "$CSRC/utils/mimalloc/src/static.c" \
    "$ROOT/native/jvm_bridge.c" \
    "$ROOT/native/j2me_render.m" \
    "$ROOT/native/j2me_ui.m" \
    "$ROOT/native/j2me_input.c" \
    "$ROOT/native/j2me_audio.m" \
    "$ROOT/native/host_main.c" \
    "$ROOT/native/host_ui.m" \
    "$ROOT/native/host_form.m" \
    -framework Foundation -framework CoreGraphics -framework ImageIO -framework CoreText \
    -framework AudioToolbox -framework AVFoundation -framework UIKit -framework CoreHaptics \
    -framework QuartzCore \
    -lpthread -lm

echo "packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/jars"
cp "$BUILD/RuntimeApp" "$APP/RuntimeApp"
cp "$RT_JAR" "$APP/jars/minijvm_rt.jar"
cp "$BUILD/j2me_api.jar" "$APP/jars/j2me_api.jar"
cp "$MIDLET_JAR" "$APP/jars/game.jar"
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>RuntimeApp</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>JLModPlusRuntime</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
codesign -f -s - --timestamp=none "$APP" >/dev/null 2>&1 || true
echo "built: $APP"
