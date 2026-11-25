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
BUNDLE_ID="io.github.0xfenix.jlmodplus"

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
# While editing the engine for the next patch the checkout no longer matches
# the stored patches; RT_SKIP_PATCHES=1 builds whatever is checked out.
for patch in "$ROOT"/patches/*.patch; do
    [ "${RT_SKIP_PATCHES:-}" = "1" ] && break
    [ -e "$patch" ] || continue
    if ( cd "$MINIJVM_DIR" && git apply --reverse --check "$patch" >/dev/null 2>&1 ); then
        continue
    fi
    # A later patch can sit inside an earlier patch's context, which defeats
    # the reverse check above. Fall back to looking for one line the patch
    # adds: if the checkout already contains it, the patch is applied.
    applied_target=$(awk '/^\+\+\+ b\//{f=$2; sub("^b/", "", f)} /^\+[^+]/{l=substr($0,2); if (length(l) > 20) {print f; exit}}' "$patch")
    applied_marker=$(awk '/^\+\+\+ b\//{f=$2; sub("^b/", "", f)} /^\+[^+]/{l=substr($0,2); if (length(l) > 20) {print l; exit}}' "$patch")
    if [ -n "$applied_target" ] && [ -n "$applied_marker" ] && grep -Fq -- "$applied_marker" "$MINIJVM_DIR/$applied_target"; then
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

INCS="-I$CSRC -I$CSRC/jvm -I$CSRC/utils -I$CSRC/utils/https -I$CSRC/utils/https/mbedtls/include -I$CSRC/utils/mimalloc/include -I$ROOT/native/bridge -I$ROOT/native/host/api -I$ROOT/native/host/app -I$ROOT/native/host/theme -I$ROOT/native/host/library -I$ROOT/native/host/game -I$ROOT/native/host/forms"

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
    "$ROOT/native/bridge/jvm_bridge.c" \
    "$ROOT/native/bridge/j2me_render.m" \
    "$ROOT/native/bridge/j2me_ui.m" \
    "$ROOT/native/bridge/j2me_input.c" \
    "$ROOT/native/bridge/j2me_audio.m" \
    "$ROOT/native/host/app/rt_main.c" \
    "$ROOT/native/host/app/rt_background.m" \
    "$ROOT/native/host/library/rt_jar_manifest.c" \
    "$ROOT/native/host/library/rt_game_store.m" \
    "$ROOT/native/host/library/rt_library_vc.m" \
    "$ROOT/native/host/library/rt_keypad_editor.m" \
            "$ROOT/native/host/library/rt_proxy_store.m" \
            "$ROOT/native/host/library/rt_proxy_list.m" \
    "$ROOT/native/host/game/rt_game_view.m" \
    "$ROOT/native/host/game/rt_keys.m" \
    "$ROOT/native/host/game/rt_game_controller.m" \
    "$ROOT/native/host/game/rt_tab_grid.m" \
    "$ROOT/native/host/forms/rt_form_panel.m" \
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
  <key>CFBundleName</key><string>JL-Next</string>
  <key>CFBundleDisplayName</key><string>JL-Next</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UILaunchScreen</key><dict/>
  <key>UIBackgroundModes</key><array><string>audio</string></array>
  <key>UIUserInterfaceStyle</key><string>Dark</string>
  <key>NSLocalNetworkUsageDescription</key><string>Kết nối tới máy chủ game trong mạng nội bộ.</string>
  <key>UIFileSharingEnabled</key><true/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
  <key>UTImportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>io.github.0xfenix.jlmodplus.jar</string>
    <key>UTTypeDescription</key><string>J2ME Application</string>
    <key>UTTypeConformsTo</key><array><string>com.sun.java-archive</string><string>public.zip-archive</string><string>public.data</string></array>
    <key>UTTypeTagSpecification</key><dict>
      <key>public.filename-extension</key><array><string>jar</string></array>
      <key>public.mime-type</key><array><string>application/java-archive</string></array>
    </dict>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array>
    <dict>
      <key>CFBundleTypeName</key><string>J2ME Application</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>CFBundleTypeExtensions</key><array><string>jar</string></array>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>io.github.0xfenix.jlmodplus.jar</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Java archive</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>CFBundleTypeExtensions</key><array><string>jar</string></array>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>com.sun.java-archive</string><string>public.zip-archive</string><string>com.pkware.zip-archive</string></array>
    </dict>
  </array>
</dict></plist>
PLIST

# App icon: compile the single-size 1024 asset into Assets.car and merge the
# icon keys actool writes (CFBundleIcons) into the Info.plist above.
ICON_PLIST="$(mktemp -t rt-icon).plist"
if xcrun actool "$ROOT/assets/Assets.xcassets" \
        --compile "$APP" \
        --platform "$SDK" \
        --minimum-deployment-target 17.0 \
        --app-icon AppIcon \
        --target-device iphone --target-device ipad \
        --output-partial-info-plist "$ICON_PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Merge $ICON_PLIST" "$APP/Info.plist" >/dev/null 2>&1 || true
else
    echo "warning: actool failed; the app will use the default icon" >&2
fi
rm -f "$ICON_PLIST"

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
