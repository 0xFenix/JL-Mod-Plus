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
- `native/bridge/` — vendored `jvm_bridge` (slot lifecycle, JVM bootstrap),
  `j2me_render` (CoreGraphics raster + ImageIO decode + haptics), `j2me_ui`,
  `j2me_input`, `j2me_audio`. Eight of the ten files are byte-identical to the
  reference.
- `native/host/` — our UIKit host, split by layer; see
  [`ARCHITECTURE.md`](ARCHITECTURE.md) for the module map and the rules.

## What was removed

M3G (`javax.microedition.m3g`), Mascot Capsule micro3D, JBlend and Vodafone
J3D, Bluetooth, Location, AMMS, the proxy tunnel, and the server-destination
override. These are outside this port's scope; removing them also drops the
OpenGL ES and socket-interception surface.

## Licensing

`java/src` and `native/bridge/` are Apache-2.0 and carry a derivation notice. The
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
| `0002-signal-handler-safe-shutdown.patch` | The engine's signal handler kept a pointer to the last created JVM, so after a slot was destroyed a later `SIGTERM` dereferenced freed memory and dumped threads twice, ending in a second `SIGSEGV`. It now clears that pointer on destroy, refuses to re-enter the dump, and terminates with `_Exit` instead of running exit handlers. |
| `0004-close-sockets-on-jvm-destroy.patch` | Close TCP sockets a MIDlet left open when its JVM is destroyed, so closing a tab really disconnects the character. |
| `0003-file-protocol.patch` | Adds the JSR-75 `file://` protocol and `FileConnection` implementation to the runtime jar. `Connector` resolves protocol classes with the boot class loader, so a classpath copy is never found; `file:///root/` maps to `<Documents>/files`, traversal is rejected, and unimplementable size queries return 0. |

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
xcrun devicectl device process launch --device <UDID> --console io.github.0xfenix.jlmodplus
```

The device needs a profile that lists its UDID; let Xcode register the device
once (any throwaway project with the same bundle id works) before the first
device build.

`devicectl` cannot screenshot a running app, so the host can dump the frames it
already renders. Pass the app's `Documents` path (the harness prints its
`save_root` on launch; `Documents` is its parent) and a frame interval:

```sh
xcrun devicectl device process launch --device <UDID> --console \
  -e '{"RT_MIDLET_JAR":"<bundle>/jars/game.jar","RT_SNAPSHOT_DIR":"<Documents>/snaps","RT_SNAPSHOT_INTERVAL":"150"}' \
  io.github.0xfenix.jlmodplus
xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer \
  --domain-identifier io.github.0xfenix.jlmodplus \
  --source Documents/snaps --destination /tmp/devsnaps
```

`native/host/app/rt_main.c` boots one MIDlet through `jvm_bridge_init_slot` /
`jvm_bridge_run_midlet_slot`. By default it runs the UIKit host
(`native/host/game/rt_game_controller.m` drives the sessions, `rt_game_view.m`
presents the frame in a `CALayer` with the touch keypad), which
maps touches to key and pointer events through `j2me_input`.

The bottom pad is the fixed 3x3 layout (soft keys, arrows, OK, `*`, `#`).
The keyboard button in the top bar instead raises the iOS QWERTY keyboard:
every typed character is posted to the focused MIDlet as a MIDP key
press/release pair (return sends fire, delete sends the right soft key). The
hidden field keeps a run of invisible filler text and refuses every edit in the
text-field delegate. UIKit stops reporting deletes (and stops the key repeat
while the finger is held) once a field is empty, so the filler keeps delete a
normal editing key: one tap sends one RSK event, holding the key repeats it,
and neither the filler nor any real text ever changes. This is how
games that draw their own name fields receive text. Forms, lists and text
boxes keep using their native fields and the system keyboard.
`RT_SYSTEM_KEYBOARD=1` opens the keyboard and `RT_TYPE_TEXT=abc` types a string
three seconds after launch for scripted runs. Setting
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

`native/host/forms/rt_form_panel.m` renders the non-Canvas screens. `j2me_lcdui`'s
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
`build/j2me_api.jar` against the `java_native_method` tables in `native/bridge/*`.
A declaration without a matching row is an `UnsatisfiedLinkError`, which a
MIDlet cannot catch. The table class must equal the declaring Java class
exactly — `j2me_audio.m` originally registered under `org/mini/media/MiniAudio`
while the declarations live in `javax.microedition.lcdui.NativeBridge`.

## Game library

The app starts in a library when no game is passed in (`RT_MIDLET_JAR`
unset): `native/host/library/rt_library_vc.m` lists the JARs in
`Documents/games`, reads each title from `META-INF/MANIFEST.MF` with
`rt_jar_manifest.c` (the engine's miniz, no JVM needed), and adds the tapped
game to the running host. `rt_game_store.m` owns the settings, names and
save-directory bookkeeping.
Each game keeps its own resolution/FPS settings and save directory.

The host keeps several games running at once, one engine slot each. The top
bar shows a `▢ n` button once more than one game runs; it opens
`native/host/game/rt_tab_grid.m`, a window switcher with two columns and
exactly two rows visible — four cards — and vertical scrolling beyond that.
Each card shows the slot's latest frame and title. Tapping a card focuses that
slot and returns to it; `✕` stops and destroys the slot in place. The focused
card carries the amber border and the grid scrolls to it on open, so the active
game is always visible. When the last card closes the host returns to the
library, which then shows an `Đang chơi (n)` row. Only the focused slot renders
to the screen, but every slot reports its frames (`[RT] slot N frames=…`).

The library also shows the game's own icon — the one named in the `MIDlet-1`
manifest field, extracted from the JAR and scaled with nearest-neighbour
filtering so small icons stay sharp. The ⓘ button opens per-game options:
rename (stored in `NSUserDefaults`, the JAR keeps its filename), screen
resolution and FPS, delete. Deleting removes the JAR, its save directory and
its stored settings, behind a confirmation. Swipe-to-delete does the same.
Sorting is by name, last played or file size; the list supports pull-to-refresh
and the picker accepts several JARs at once.

`Documents/games` is reachable from the Files app because the Info.plist sets
`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`; the `+`
button also imports through `UIDocumentPickerViewController`.

`./scripts/run-sim.sh` drives this from the shell: `RT_SHELL=1` copies the
jar into `Documents/games` and launches the library, and `RT_AUTOLAUNCH=1`
opens the first row after 0.3 s because `simctl` cannot tap.

## Per-game controls

The options sheet in the library (long-press a row, or the `⋯`/context menu)
carries two control settings next to resolution and FPS:

- **Bàn phím: 3 × 3 (gọn) / đầy đủ (có số)** - the compact pad has soft keys,
  arrows, fire, `*` and `#`; the full layout adds the ten digits and grows the
  keypad container from 190 to 340 pt. Games that ask for a number at a menu
  need the full layout.
- **Turbo khi giữ OK** - while enabled, holding fire sends a press/release
  pulse every 80 ms instead of one press, for titles that expect rapid tapping.

Both are stored per JAR under the `RTGameConfig` defaults key (added as `kb`
and `turbo`) and follow the focused tab, because one keypad serves every
session. `RT_FULL_KEYBOARD=1` and `RT_TURBO=1` set the same flags for
scripted single-game runs.

## Background keep-alive

A J2ME title keeps one TCP socket open for the whole session, and iOS suspends
a normal app seconds after it leaves the foreground, which freezes that socket
and drops the game offline. The host therefore runs `rt_background.m`: an
`AVAudioPlayer` loops half a second of inaudible PCM under the `playback`
category with `MixWithOthers`, and the Info.plist declares `audio` in
`UIBackgroundModes`. Audio keeps the process eligible for background execution,
so the socket, the JVM threads and the render loop all keep running while the
user switches apps or locks the screen; nothing is audible and other apps are
not interrupted. A background task is also begun on `didEnterBackground` as a
belt-and-braces window during the transition.

The cost is battery: the app stays fully active in the background. If a title
does not need a persistent connection, closing its tab still tears the JVM down
immediately.

## Visual design

The host chrome is a dark console around the frame: near-black ink, quiet
surfaces, one warm amber accent, SF Symbols, 44 pt touch targets and Dynamic
Type where the text is user-facing. Tokens live in `native/host/theme/rt_theme.h`
and are shared by the library, game and form modules. The app declares
`UIUserInterfaceStyle` Dark in its Info.plist so system sheets, alerts and the
keyboard match the screens instead of rendering light chrome over ink.

The library draws its own large title inside the table header: on the iOS 26
SDK the system large-title label is never built for this bar, and the slot it
reserves stays blank. A `UIRefreshControl` is deliberately not used for the
same reason (the SDK docks it into that slot); the library rescans on every
appearance and the `Sắp xếp` action changes the order.

While a non-Canvas screen (Form, List, Alert, TextBox) is up, the panel dims
the game and hides the keypad, because those screens bring their own command
buttons and the pad would otherwise peek out around the sheet.

## Socket lifetime when a tab closes

A MIDlet normally relies on the process exiting to close its connection, so a
game that never calls `Socket.close()` leaves an established TCP connection
behind. On a multi-slot host that fd survives until the whole app quits, which
keeps the character online on the game server after its tab is closed.
`patches/0004-close-sockets-on-jvm-destroy.patch` records every socket the
engine opens against its JVM and shuts it down (then closes it) when that JVM
is destroyed. Closing a tab is therefore a real disconnect: the connection
leaves `ESTABLISHED` immediately. `RT_CLOSE_FOCUSED=<seconds>` closes the
focused session during automated runs, which is how this was verified.

## Known gaps

- Four titles have been run (Avatar LAPRO, Avatar 2, Avatar AngelChip, Ninja
  School); deeper gameplay on the newer ones is still unverified.
- `file://` is implemented (patch 0003) with a single sandboxed root:
  `file:///root/...` maps to `<Documents>/files`, traversal is rejected, and
  size queries the sandbox cannot answer return 0. Long-path and hidden-file
  behaviour follows the device file system.

- FPS is hidden behind the speedometer toggle by default (`RTShowFPS`).
- The library reads the icon named by `MIDlet-1`; titles without one fall
  back to a generic glyph. Renaming changes the display name only, never the
  file on disk.
- `j2me_audio.m` natives are silent stubs in the reference project, and its
  bundled SoundFont is a 1-byte placeholder.
- Native image memory is not counted toward the GC budget: the reference
  patches `garbage.c` with a `g_native_extra_heap` counter that upstream
  miniJVM does not have, so `host_main.c` provides a no-op definition.
- The iOS build is interpreter-only (`jit.h` disables JIT for `__JVM_OS_IOS__`;
  upstream sljit does not compile for iOS targets anyway).
