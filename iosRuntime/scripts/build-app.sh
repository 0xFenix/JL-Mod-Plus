#!/bin/bash
# Build RuntimeApp.app around the vendored J2ME runtime.
#
#   TARGET        sim (default) or device
#   MINIJVM_DIR   upstream miniJVM checkout (default ~/dev/miniJVM)
#   MIDLET_JAR    game jar to bundle (default ~/Downloads/Avatar_LAPRO.jar)
#   JAVA_HOME     JDK with javac/jar
#   CODE_SIGN_IDENTITY  device only; default is the single Apple Development
#                       identity in the keychain
#
# Output: iosRuntime/build/RuntimeApp.app for sim,
#         iosRuntime/build/device/RuntimeApp.app for device, plus build/j2me_api.jar.
# The miniJVM runtime jar is built from upstream sources at build time and is
# NOT stored in the repository (GPL-2.0 + Classpath-exception licensing).
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TARGET="${TARGET:-sim}"
case "$TARGET" in
    sim)
        SDK=iphonesimulator
        ARCH_FLAGS="-arch arm64 -mios-simulator-version-min=17.0"
        APP_DIR="$ROOT/build"
        ;;
    device)
        SDK=iphoneos
        ARCH_FLAGS="-arch arm64 -miphoneos-version-min=17.0"
        APP_DIR="$ROOT/build/device"
        ;;
    *) echo "TARGET must be sim or device" >&2; exit 1 ;;
esac
MINIJVM_DIR="${MINIJVM_DIR:-$HOME/dev/miniJVM}"
MIDLET_JAR="${MIDLET_JAR:-$HOME/Downloads/Avatar_LAPRO.jar}"
BUILD="$ROOT/build"
CSRC="$MINIJVM_DIR/minijvm/c"
RT_JAR="$MINIJVM_DIR/binary/lib/minijvm_rt.jar"
APP="$APP_DIR/RuntimeApp.app"
BUNDLE_ID="io.github.h3nb.jlmodplus.runtime"

: "${JAVA_HOME:?set JAVA_HOME to a JDK 17+}"
PATH="$JAVA_HOME/bin:$PATH"

[ -f "$CSRC/jvm/jvm.c" ] || { echo "miniJVM sources not found at $MINIJVM_DIR" >&2; exit 1; }

if [ ! -f "$RT_JAR" ]; then
    echo "building minijvm_rt.jar"
    ( cd "$MINIJVM_DIR/binary" && ./build_jar.sh >/dev/null )
fi

# Engine fixes live as patches against a clean checkout, not as a vendored
# fork: the runtime jar carries GPL-2.0 files, so only our diff is stored.
REBUILD_RT=0
for patch in "$ROOT"/patches/*.patch; do
    [ -e "$patch" ] || continue
    if ( cd "$MINIJVM_DIR" && git apply --reverse --check "$patch" >/dev/null 2>&1 ); then
        continue
    fi
    echo "applying $(basename "$patch")"
    ( cd "$MINIJVM_DIR" && git apply "$patch" ) || { echo "patch failed: $patch" >&2; exit 1; }
    # Only a patch that touches Java sources needs the runtime jar rebuilt; C
    # engine patches are picked up by the compile below.
    if grep -q '^+++ b/minijvm/java/' "$patch"; then
        REBUILD_RT=1
    fi
done

if [ "$REBUILD_RT" = 1 ]; then
    echo "rebuilding minijvm_rt.jar"
    ( cd "$MINIJVM_DIR/binary" && ./build_jar.sh >/dev/null )
fi

echo "building j2me_api.jar"
rm -rf "$BUILD/classes"
mkdir -p "$BUILD/classes"
find "$ROOT/java/src" -name '*.java' > "$BUILD/sources.txt"
javac --release 8 -nowarn -cp "$RT_JAR" -d "$BUILD/classes" @"$BUILD/sources.txt"
jar cf "$BUILD/j2me_api.jar" -C "$BUILD/classes" .

INCS="-I$CSRC -I$CSRC/jvm -I$CSRC/utils -I$CSRC/utils/https -I$CSRC/utils/https/mbedtls/include -I$CSRC/utils/mimalloc/include -I$ROOT/native"

echo "compiling runtime app ($TARGET)"
CC="xcrun -sdk $SDK clang $ARCH_FLAGS -O2 -fobjc-arc -Wno-everything"

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
    "$ROOT/native/host_jar.c" \
    "$ROOT/native/host_ui.m" \
    "$ROOT/native/host_shell.m" \
    "$ROOT/native/host_form.m" \
    -framework Foundation -framework CoreGraphics -framework ImageIO -framework CoreText \
    -framework AudioToolbox -framework AVFoundation -framework UIKit -framework CoreHaptics \
    -framework QuartzCore -framework UniformTypeIdentifiers \
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
  <key>NSLocalNetworkUsageDescription</key><string>Kết nối tới máy chủ game trong mạng nội bộ.</string>
  <key>UIFileSharingEnabled</key><true/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>JAR</string>
    <key>CFBundleTypeExtensions</key><array><string>jar</string></array>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>com.pkware.zip-archive</string></array>
  </dict></array>
</dict></plist>
PLIST

if [ "$TARGET" = sim ]; then
    codesign -f -s - --timestamp=none "$APP" >/dev/null 2>&1 || true
else
    # Device builds need a real identity plus the provisioning profile Xcode
    # created for this device; both are resolved from the keychain/profile
    # directory so no project file has to carry signing state.
    IDENTITY="${CODE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)}"
    [ -n "$IDENTITY" ] || { echo "no Apple Development identity in keychain" >&2; exit 1; }
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    PROFILE=""
    for p in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision; do
        [ -f "$p" ] || continue
        security cms -D -i "$p" > "$TMP/profile.plist" 2>/dev/null || continue
        appid="$(plutil -extract Entitlements.application-identifier raw -o - "$TMP/profile.plist" 2>/dev/null || true)"
        case "$appid" in
            *"$BUNDLE_ID") PROFILE="$p"; break ;;
        esac
    done
    [ -n "$PROFILE" ] || { echo "no provisioning profile for $BUNDLE_ID" >&2; exit 1; }
    cp "$PROFILE" "$APP/embedded.mobileprovision"
    plutil -extract Entitlements xml1 -o "$TMP/entitlements.plist" "$TMP/profile.plist"
    codesign -f -s "$IDENTITY" --entitlements "$TMP/entitlements.plist" \
        --timestamp=none "$APP" >/dev/null
    echo "signed with: $IDENTITY"
    echo "profile: $PROFILE"
fi
echo "built: $APP"
