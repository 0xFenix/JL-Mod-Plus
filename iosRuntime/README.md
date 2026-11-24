# iosRuntime — vendored J2ME runtime for iOS

Runtime layer for the iOS port: the MIDP/CLDC Java implementation plus the
JNI bridge that renders through CoreGraphics. It is vendored from
[J2ME-Decade (iOS Edition)](https://github.com/darkrose00x-ux/j2me-ios)
(Apache-2.0) rather than rewritten, because that project already ships a
working MIDP 2.0 stack on miniJVM.

This directory is **not** an app. The shipping iOS shell (KMP `core/` +
Swift UI, platform capabilities behind `spi/PlatformSpi`) is built
separately; this runtime is the layer it will call into.

## What was kept

- `java/src` — `javax.microedition` (lcdui, game, media, rms, messaging,
  midlet, io), OEM extension packages, and `javax.microedition.shell`
  MIDlet runner. 279 files.
- `native/` — `jvm_bridge` (slot lifecycle, JVM bootstrap), `j2me_render`
  (CoreGraphics raster + ImageIO decode + haptics), `j2me_ui`, `j2me_input`,
  `j2me_audio`. Eight of the ten files are byte-identical to the reference.

## What was removed

M3G (`javax.microedition.m3g`), Mascot Capsule micro3D, JBlend and Vodafone
J3D, Bluetooth, Location, AMMS, the proxy tunnel, and the server-destination
override. These are outside this port's scope; removing them also drops the
OpenGL ES and socket-interception surface.

## Licensing

`java/src` and `native/` are Apache-2.0 and carry a derivation notice. The
reference project states its API layer is ported from
[J2ME-Loader](https://github.com/nikita36078/J2ME-Loader), whose
`javax.microedition` sources are Apache-2.0 as well
(Copyright 2012 Kulikov Dmitriy, 2017-2020 Nikita Shakarun,
2019-2023 Yury Kharchenko). See the root `THIRD_PARTY_NOTICES.md`.

The miniJVM engine and its `minijvm_rt.jar` are **not** stored here. The C
engine is MIT; the runtime jar contains OpenJDK-derived classes under
GPL-2.0-only WITH Classpath-exception-2.0, so `build-app.sh` compiles both
from a local upstream checkout (`MINIJVM_DIR`, default `~/dev/miniJVM`).

Engine fixes live in `patches/` as ordinary diffs against that clean
checkout: `build-app.sh` applies any patch that is not applied yet and
rebuilds the runtime jar, so only our changes are versioned here and nothing
from upstream is redistributed. Patches currently present:

| Patch | Fix |
| --- | --- |
| `0001-http-content-length-case-insensitive.patch` | A MIDlet setting `Content-length` (lowercase) made the engine add a second `Content-Length`, which servers answer with `400 Bad Request` — the boot-time POST of online games failed on iOS while the same JAR worked on Android. |

## Build and run

```sh
export JAVA_HOME=/path/to/jdk17+
MINIJVM_DIR=~/dev/miniJVM MIDLET_JAR=/path/to/game.jar ./scripts/build-sim.sh
./scripts/run-sim.sh 40
```

`build-sim.sh` writes `build/RuntimeApp.app` with the engine, `j2me_api.jar`,
the upstream runtime jar, and the game jar in `jars/`. `run-sim.sh` boots a
simulator (`SPIKE_DEVICE`, default `SpikePhone`), installs, launches, then
reports `[RT] frames=… fps=…` lines, saves a screenshot to `build/run.png`,
and lists PNG snapshots written into the app's data container.

For a real iPhone, `./scripts/build-device.sh` compiles the same sources for
`iphoneos` into `build/device/RuntimeApp.app` and signs it with the first
`Apple Development` identity plus the provisioning profile whose
`application-identifier` matches the bundle id (`CODE_SIGN_IDENTITY` and
`TARGET=sim|device` override the wrapper). Install and run it with:

```sh
xcrun devicectl device install app --device <UDID> build/device/RuntimeApp.app
xcrun devicectl device process launch --device <UDID> --console io.github.h3nb.jlmodplus.runtime
```

The device needs a profile that lists its UDID; let Xcode register the device
once (any throwaway project with the same bundle id works) before the first
device build.

`native/host_main.c` boots one MIDlet through `jvm_bridge_init_slot` /
`jvm_bridge_run_midlet_slot`. By default it runs `native/host_ui.m`, a UIKit
host that presents the frame in a `CALayer` and a 12-key touch keypad, and
maps touches to key and pointer events through `j2me_input`. Setting
`RT_HEADLESS=1` runs the snapshot harness instead: it creates no window,
writes a PNG every 60 frames, and is what automated runs use.

`test/InputProbe.java` is the synthetic-input probe. With
`RT_SYNTH_INPUT=1` the host posts a key press/release and a press/drag/release
sequence a few seconds after launch, and the MIDlet prints every callback it
receives; `scripts/make-test-jar.sh` builds it into `build/test.jar`.

`test/NetworkProbe.java` (`./scripts/make-test-jar.sh test/network-probe.mf`)
checks the connection path. `scripts/net-fixtures.sh start` runs a TCP echo
server on 127.0.0.1:9099 and an HTTP server on 127.0.0.1:9098 on the host;
the probe then prints the socket echo, the HTTP status/body, and an HTTPS
result. Verified on the simulator: socket echo, `http code=200`, and
`https code=200`.

Networking comes from the engine, not from this tree: miniJVM's runtime jar
ships `javax.microedition.io` (Connector, SocketConnection, HttpConnection,
HttpsConnection) plus `org/mini/net/*` protocol handlers over BSD sockets and
mbedtls, and bootclasspath classes win over the app classpath. A hand-written
`javax.microedition.io` under `java/src` is therefore inert; only the
interfaces the engine lacks (CommConnection, PushRegistry, SecureConnection,
UDPDatagramConnection) are kept. App Transport Security does not apply to BSD
sockets, so no `NSAppTransportSecurity` entry is needed.

`native/host_form.m` renders the non-Canvas screens. `j2me_lcdui`'s
`Form`, `List`, `Alert` and `TextBox` each publish their model to
`j2me_ui.m` and then call `formShow()`; the host installs a
`j2me_ui_set_callback` handler, reads the model through the
`j2me_ui_get_*` accessors, and builds a UIKit panel (labels, text fields,
option rows, command buttons). Choices are tappable: the option list is
serialized into the item text by `Form.showNative`, so a tap rewrites that
text through `j2me_ui_set_form_item_text` and `Form.syncFromNative` picks up
the selection when a command fires. UI events travel back through
`j2me_input_post_ui_event` (command action, list select, alert dismissed,
list set index). Verified on the simulator with
`test/FormProbe.java` (`./scripts/make-test-jar.sh test/form-probe.mf`):
the login Form with a password field and a two-option ChoiceGroup, the
TextBox, the List, and the Alert all render, and the same run covers the
Canvas screen with `Avatar_LAPRO`.

`scripts/audit-natives.sh` compares every `native` declaration in
`build/j2me_api.jar` against the `java_native_method` tables in `native/*`.
A declaration without a matching row is an `UnsatisfiedLinkError`, which a
MIDlet cannot catch. The table class must equal the declaring Java class
exactly — `j2me_audio.m` originally registered under `org/mini/media/MiniAudio`
while the declarations live in `javax.microedition.lcdui.NativeBridge`.

## Game library

The app starts in a library when no game is passed in (`RT_MIDLET_JAR`
unset): `native/host_shell.m` lists the JARs in `Documents/games`, reads each
title from `META-INF/MANIFEST.MF` with `native/host_jar.c` (the engine's
miniz, no JVM needed), and pushes `RTViewController` for the tapped game.
Each game keeps its own resolution/FPS settings and save directory.

`Documents/games` is reachable from the Files app because the Info.plist sets
`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`; the `+`
button also imports through `UIDocumentPickerViewController`.

`./scripts/run-sim.sh` drives this from the shell: `RT_SHELL=1` copies the
jar into `Documents/games` and launches the library, and `RT_AUTOLAUNCH=1`
opens the first row after 0.3 s because `simctl` cannot tap.

## Known gaps

- `file://` has no protocol handler: the engine ships no
  `javax.microedition.io.file` implementation and the interfaces alone cannot
  open a stream.

- Frames are delivered to a single full-screen view; there is no multi-tab
  UI. The `‹ Thư viện` button overlaps the top-left of the canvas.
- The library sorts by filename and has no per-game icon or rename.
- `j2me_audio.m` natives are silent stubs in the reference project, and its
  bundled SoundFont is a 1-byte placeholder.
- Native image memory is not counted toward the GC budget: the reference
  patches `garbage.c` with a `g_native_extra_heap` counter that upstream
  miniJVM does not have, so `host_main.c` provides a no-op definition.
- The iOS build is interpreter-only (`jit.h` disables JIT for `__JVM_OS_IOS__`;
  upstream sljit does not compile for iOS targets anyway).
