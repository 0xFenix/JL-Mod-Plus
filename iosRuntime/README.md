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
GPL-2.0-only WITH Classpath-exception-2.0, so `build-sim.sh` compiles both
from a local upstream checkout (`MINIJVM_DIR`, default `~/dev/miniJVM`).

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

## Known gaps

- Frames are delivered to a single full-screen view; there is no multi-tab
  UI, and native form UI (Form/List/Alert) is not exercised yet.
- `j2me_audio.m` natives are silent stubs in the reference project, and its
  bundled SoundFont is a 1-byte placeholder.
- Native image memory is not counted toward the GC budget: the reference
  patches `garbage.c` with a `g_native_extra_heap` counter that upstream
  miniJVM does not have, so `host_main.c` provides a no-op definition.
- The iOS build is interpreter-only (`jit.h` disables JIT for `__JVM_OS_IOS__`;
  upstream sljit does not compile for iOS targets anyway).
