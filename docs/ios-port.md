# iOS port — reference: j2me-ios (J2ME-Decade iOS Edition)

Source: <https://github.com/darkrose00x-ux/j2me-ios> (reviewed 2026-11-24).
Same family as this repo (J2ME-Loader-derived), runs MIDP 2.0 / CLDC 1.1 games
on iPhone/iPad. This note exists so P1-P3 do not reinvent what is proven there.

## Reference architecture (4 layers)

```
iOS App (Swift/UIKit): game grid, game screen, virtual keys, long-press settings
Native Bridge (C/Obj-C): render, audio, input, forms UI, 3D, proxy tunnel
J2ME API (Java, j2me_api.jar): MIDP/CLDC classes ported from J2ME-Loader,
                               platform calls routed to the native bridge
miniJVM (C): bytecode interpreter, GC, threads, POSIX networking
```

Key decision: they did **not** write a JVM. They embed
[miniJVM](https://github.com/niclet/mini_jvm) (C, version 2.0.0, external
checkout — NOT vendored in their repo) and compile the Java API layer with
`javac --release 8` against `minijvm_rt.jar` (`j2me_api/build.sh`).
Games run as plain `.class` files inside the `.jar` — no DEX conversion.

## Bridge inventory (`J2MEEmulator/NativeBridge/`)

| File | Role | Maps to our P-phase |
|---|---|---|
| `jvm_bridge.{h,c}` (~20 KB) | JVM lifecycle, **multi-slot** (0..15), focus, stop, proxy config, server-redirect rules | P1 + multi-tab model |
| `j2me_render.{h,m}` (~51 KB) | Canvas/Graphics/Image via `CGBitmapContext` | P2 rendering |
| `j2me_ui.{h,m}` (~20 KB) | Form/List/Alert/TextBox as native UIKit views | P2 forms |
| `j2me_audio.{h,m}` (~3 KB) | WAV/MP3 via `AVAudioPlayer`, MIDI via `AVMIDIPlayer` + SoundFont (`gs_instruments.sf2`), ToneControl | P3 audio |
| `j2me_input.{h,c}` (~5 KB) | Touch → pointer events, 8-way joystick + numpad mapping | P2 input |
| `j2me_micro3d_gl.{h,m}` (~45 KB) + `m3g/` | MascotCapsule (GLES2) and M3G JSR-184 (GLES1) | Out of scope for spike |
| `decade_proxy_tunnel.{h,c}` (~13 KB) | SOCKS5/HTTP proxy tunnel, per-tab proxy | Their ecosystem feature; not our scope |

`j2me_api/src/` mirrors the MIDP shape: `java/`, `javax/`, `com/` (OEM: Nokia,
Siemens, Samsung, Motorola…), `mmpp/`.

## Multi-slot = precedent for our multi-tab

`jvm_bridge.h` runs up to 16 independent slots, each with its own
`res_root`/`save_root`, plus `set_focused_slot` (only the focused slot renders
to the main screen and receives input). That is the same model as our
`AmsRegistry` tabs (one runtime per tab, audio/input on the foreground tab).
If we adopt miniJVM, one miniJVM instance per tab is the natural mapping —
and per-slot `save_root` gives tab data isolation for free.

## What changes in our plan

- **P1 (interpreter): CANCEL writing a CLDC interpreter in Kotlin.**
  Replace with a miniJVM spike: build miniJVM for `iosArm64` + simulator,
  compile a minimal Java API surface, run a hello-world MIDlet.
  Estimated effort drops from 1–2 months to 1–3 weeks for first light.
- **P2 (LCDUI): port, don't invent.** Our `app/src/main/java/javax/microedition`
  (364 files) is the same lineage as their `j2me_api/src`. Work becomes:
  split Android-coupled code (`android.*` imports, 88 files) behind a
  native-call seam, compile the pure part with `javac --release 8`.
- **`core/` KMP module: keep as SPI + tooling, not as the VM.**
  `PlatformSpi` stays valid as the contract the future `iosMain` adapter
  implements; the interpreter itself lives in C (miniJVM), not Kotlin.
- **Audio solved by reference:** `AVAudioPlayer` + `AVMIDIPlayer` + SoundFont
  answers the open P3 MIDI question (no need to port sonivox).
- **Out of scope for spike, same as before:** JSR-82/camera/PIM/SIP, M3G/micro3D.

## Must verify before vendoring (blocking)

1. **miniJVM license — VERIFIED 2026-11-24, USER CHOSE external-checkout spike.**
   True upstream: <https://github.com/digitalgust/miniJVM> (branch `master`,
   "Cross platform java virtual machine, the minimal jvm").
   Their README links (`niclet/mini_jvm`, `niclet/J2ME-Loader`) are both dead
   (404); the j2me-ios reference is <https://github.com/darkrose00x-ux/j2me-ios>
   (its vendored `J2MEEmulator/minijvm/{jvm,utils}` is an OLDER snapshot, not
   master: no `immix`, no `mimalloc`, no `heapdump_hprof`, many files differ;
   only `sljit/` is identical).
   Per upstream `LICENSE`: the C code is **MIT** (fine), BUT the Java runtime
   `minijvm_rt.jar` contains OpenJDK-derived files under
   **GPL-2.0-only WITH Classpath-exception-2.0** — distributions of the jar
   must keep its `META-INF/{MIT_LICENSE,LICENSE,CLASSPATH_EXCEPTION,NOTICE}`.
   => The C engine is Apache-2.0-compatible; the *runtime jar is NOT
   Apache-2.0-clean*. User decision: spike with an EXTERNAL checkout only
   (`~/dev/miniJVM`, `~/dev/j2me-ios`, `~/dev/spike`) — NOTHING vendored into
   this repo.
2. **miniJVM spike step 3b — PASS on simulator 2026-11-24.**
   Recipe (all outside this repo): built `minijvm_rt.jar` from upstream
   `minijvm/java` with `javac --release 8`; wrote minimal `javax` surface
   (`MIDlet`, `MIDletStateChangeException`, stub `Display`) + `HelloMidlet`
   reaching `startApp`; compiled engine for `iosSimulatorArm64`
   (`xcrun -sdk iphonesimulator clang -arch arm64
   -mios-simulator-version-min=17.0`) + tiny harness (`jvm_create` /
   `jvm_init` / `call_main`), packaged as ad-hoc-signed `.app`, ran via
   `simctl install` + `simctl launch --console` on iPhone 16 Pro / iOS 27.0:
   `[HelloMidlet] startApp reached`, exit ret=0.
   Findings: (a) host mac-arm64 run also passes (0.5 s incl. JVM boot);
   (b) upstream `sljit/` does NOT compile for iOS targets (missing
   `SLJIT_UPDATE_WX_FLAGS` in the non-OSX branch) — spike runs
   interpreter-only, which `jit.h` already selects via `JIT_ENABLE=0` for
   `__JVM_OS_IOS__` (same as upstream's own `iosapp.xcodeproj`: `jit.c`
   without sljit). JIT-on-iOS is therefore a separate work item with its own
   license/build cost — do NOT assume the "bonus JIT" until measured.
   First-boot note: this Mac had no simulator runtimes; `xcodebuild
   -downloadPlatform iOS` (~8 GB) was required before any `simctl` run.
2. **JNI-style binding mechanism.** `jvm_bridge.c` shows how Java native
   methods bind to C on iOS — read it fully on the Mac before designing our
   `javax` → bridge seam (it decides how much of our `javax` tree is reusable
   as-is).
3. **Performance baseline.** miniJVM is an AST/walking interpreter; still
   measure FPS on a real iPhone with one of our 3 acceptance JARs (P1 exit
   criterion unchanged). Simulator 3b passed (interpreter-only).
   3c interim 2026-11-24 (first user JAR: `Avatar_LAPRO.jar`, TeaMobi,
   `vn.lapro.GameMidlet`, MIDP-2.0/CLDC-1.0, 519 classes, 44 PNGs, needs
   socket+http+sms): on host miniJVM the MIDlet **instantiates and enters
   `startApp`** (Runner via reflection; `Display.getDisplay`/`setCurrent`
   stubbed). `startApp` then stops at the first real LCDUI class in its
   path (`vo` → … → `Canvas`). Static scan (`strings` over all classes)
   gives the exact port backlog, in dependency order: lcdui `Displayable`,
   `Canvas`, `Graphics`, `Image`, `Command`, `Display`(+`vibrate`,
   `setCurrent`), `Form`/`List`/`ChoiceGroup`/`StringItem`/`TextField`/
   `Ticker`/`Alert`/`AlertType`, `Displayable`; media `Manager`/`Player`/
   `Control`; rms `RecordStore`; io `Connector`/`HttpConnection`/
   `SocketConnection` (already in `minijvm_rt.jar`); wireless-messaging SMS
   (promo feature, last). No `lcdui/game/*` usage — plain `Canvas` render
   loop. Engine quirk found: `Class.getResourceAsStream` with a relative
   name throws `IncompatibleClassChangeError` inside `String.startsWith`
   (line 355) — game catches it and continues, but resource loading needs
   an engine-side look before assets (PNG) can load. FPS cannot be measured
   until the LCDUI port renders frames (P2); host `test.ExecuteSpeed`
   baseline turned out to be a quadratic `String` stress loop after 2h11m —
   discarded in favour of purpose-built benchmarks.
4. **Runtime layer inherited, not rewritten — DECIDED 2026-11-24.**
   Reference <https://github.com/darkrose00x-ux/j2me-ios> builds on Xcode 27
   and runs, and its `javax.microedition` + native bridge compile with zero
   errors against our upstream `minijvm_rt.jar`, so there is no engine-version
   skew. Vendored into `iosRuntime/` (see its README): 279 Java files plus
   five native modules, with M3G, micro3D, JBlend/Vodafone J3D, Bluetooth,
   Location, AMMS, proxy tunnel and server override removed. Licensing holds:
   the reference is Apache-2.0 and its API layer derives from J2ME-Loader,
   whose `javax.microedition` sources are Apache-2.0 as well; derivation
   notices are restored on every adopted file and recorded in
   `THIRD_PARTY_NOTICES.md`. The Swift app shell is NOT adopted — the iOS
   product keeps the KMP `core/` + `PlatformSpi` boundary.
   Result: Avatar LAPRO boots and renders on `iosSimulatorArm64`,
   `[RT] frames=60 5.2s fps=11.5 240x320`, first real interpreter-only iOS
   frame rate. Avatar is an online game and self-exits when its data fetch
   fails, which caps automated observation; device measurement is still owed.
5. **Networking — VERIFIED on simulator 2026-11-24.**
   Games are mostly online and light (no 3D, no audio), so the connection path
   matters more than offline frame rate. `test/NetworkProbe.java` reports
   `socket echo=ECHO PING`, `http code=200`, and `https code=200` against host
   fixtures (`scripts/net-fixtures.sh`). All of it comes from the engine:
   miniJVM's runtime jar ships `javax.microedition.io` and `org/mini/net/*`
   handlers over BSD sockets and mbedtls, and bootclasspath classes win over
   the app classpath — a hand-written `javax.microedition.io` in `java/src` is
   inert and was deleted. ATS does not apply to BSD sockets, so no Info.plist
   exception is needed. `file://` remains unsupported (no handler ships).
   `scripts/audit-natives.sh` guards the seam: a `native` declaration without
   a matching `java_native_method` row is an `UnsatisfiedLinkError` that a
   MIDlet cannot catch, which is how the audio table was found registered
   under the wrong class.
   **Engine patch, device-verified 2026-11-25:** the game's first request
   returned `400 Bad Request` on iOS while the same JAR works on Android.
   Trace of the wire bytes showed the engine sending two `Content-Length`
   headers: the MIDlet set `Content-length` (lowercase) and
   `sendRequestHeader()` only checked the exact spelling `Content-Length`
   before adding its own. Servers reject duplicated `Content-Length`, so the
   POST failed and the game gave up. The guard now checks all three
   capitalisations. `iosRuntime/patches/` holds this as a patch against a
   clean miniJVM checkout, applied by `build-app.sh` (which rebuilds the
   runtime jar after applying it) — the engine is still never vendored.
   **Socket protocol, user-verified 2026-11-25:** after that fix the game was
   played on the iPhone and a login completed successfully, so the title's own
   socket protocol (not only `http://`) works through the engine's
   `javax.microedition.io` / `org.mini.net.socket` path. Frame dumps from the
   same session show server content (ticker, announcement dialog) at a steady
   18.3 fps, 240x320.
6. **Screen UI (Form/List/Alert/TextBox) — VERIFIED on simulator 2026-11-24.**
   The vendored `j2me_ui.m` keeps a per-slot model of the current screen and
   reports it through a callback; the reference app rendered that model in
   Swift. `native/host_form.m` does the same in UIKit: it reads the model
   through the `j2me_ui_get_*` accessors, builds a panel (title, item rows,
   text fields, tappable option rows, command buttons), and posts the four UI
   events back through `j2me_input_post_ui_event`. `test/FormProbe.java`
   covers a login Form with a password field and a two-option `ChoiceGroup`,
   a `TextBox`, a `List`, and an `Alert`; each was confirmed from simulator
   screenshots. `ChoiceGroup` state is not a separate native field — Java
   serializes it into the item text (`<selected>\n<choice>\t…\n<flags>`) and
   `Form.syncFromNative` re-reads it, so a native tap rewrites that text.
   Note: the host starts the MIDlet about four seconds after launch, so
   screenshot timing must account for that offset.
7. **App shell — VERIFIED on simulator 2026-11-24.** `native/host_shell.m`
   is the library: all `Documents/games/*.jar` are listed by MIDlet name
   (read straight from each manifest by `host_jar.c` over the engine's miniz,
   with no JVM), each with a per-game canvas size and FPS cap stored in
   `NSUserDefaults` and a per-game save directory. Import goes through
   `UIDocumentPickerViewController`; `UIFileSharingEnabled` and a `.jar`
   document type make the folder visible in the Files app. Selecting a row
   pushes a `RTViewController` with a `‹ Thư viện` control. Verified with
   Avatar end to end: library → game boot → `startApp` → frames → back.
   The icon from `MIDlet-1`, renaming, sorting and deletion were added later
   (commit `cf7af85b`).
8. **Process shutdown — FIXED 2026-11-25.** Ending a session on the iPhone
   logged `[SIGNAL]jvm sig:15` followed by a second dump and a `SIGSEGV`.
   The engine's signal handler kept a static pointer to the last created
   JVM; once a slot was destroyed that pointer dangled, so the first `SIGTERM`
   dumped a freed JVM, faulted inside the dump, re-entered the handler and
   faulted again. Patch `0002-signal-handler-safe-shutdown.patch` clears the
   pointer in `jvm_destroy`, makes the handler refuse re-entry, and terminates
   with `_Exit` instead of running exit handlers while other slots may still
   own memory. Verified on the simulator (two slots, one closed with
   `RT_CLOSE_AFTER=…`, then the process killed) and on the iPhone: one dump
   for the live JVM, one line and no dump when no JVM is left, and no second
   signal in either case.

9. **Host chrome redesigned — 2026-11-25.** The UIKit chrome moved to a dark
   "console" language driven by `iosRuntime/native/host_theme.h`: ink
   background, surface cards, one amber accent, SF Symbols, 44 pt targets and
   Dynamic Type. The library uses an inset-grouped list with custom 56 pt icon
   cells, a `Đang chơi` section, a context menu (rename, resolution/FPS,
   delete) and an empty state with an import button. The game screen has a
   single 44 pt back chevron instead of three competing controls, tab pills
   that scroll to the focused session, FPS hidden behind a speedometer toggle
   persisted as `RTShowFPS`, a framed canvas that keeps nearest-neighbour
   scaling, and a rebuilt keypad (arrow SF Symbols, amber OK, haptics). Form,
   List, Alert and TextBox render as a dimmed bottom sheet and hide the keypad
   while they are up.
   Two iOS 26 SDK behaviours shaped this: the system large-title label is
   never built for that bar (the library draws its own header and the slot
   stayed blank), and `UIRefreshControl` is docked into the same slot, so the
   library rescans on appearance instead of using pull-to-refresh. The app
   declares `UIUserInterfaceStyle` Dark so system sheets and the keyboard
   match. Verified on SpikePhone with screenshots of the library, a running
   game, two tabs and the Form/List/Alert/TextBox probe.

### 10. Host layout split by layer — 2026-11-25

`iosRuntime/native/` mixed vendored runtime code with our UIKit host. It now
has an explicit boundary: `native/bridge/` holds the five vendored modules
(read-only), and `native/host/` is ours split into `app` (entry point), `api`
(the `rt_host.h` C surface), `library` (`rt_game_store` data model,
`rt_library_vc` list UI, `rt_jar_manifest` miniz manifest/icon reader),
`game` (`rt_game_view` canvas and keypad, `rt_game_controller` sessions, tabs
and delegates), `forms` (`rt_form_panel`) and `theme` (`rt_theme.h`). No host
file reaches the JVM except through the bridge headers, and the library never
links a JVM symbol. `ARCHITECTURE.md` documents the module map plus a
"where to add code" table; `java/README.md` marks the vendored API tree
read-only. Behaviour is unchanged: the simulator still runs Avatar at ~18.7
fps and two-game tabs still switch with focus cycling.

### 11. Window switcher grid — 2026-11-25

The inline tab strip was replaced by a card grid
(`native/host/game/rt_tab_grid.m`): two columns, exactly two rows visible (four
cards), vertical scrolling for more, the focused card outlined in amber and
scrolled into view on open. Tapping a card focuses that slot and dismisses;
`✕` stops and destroys the slot in place. The top bar now shows a `▢ n` button
instead of the strip. Verified on the simulator with five sessions: four cards
fill the screen, the fifth is reachable by scrolling, and the active card is
brought into view.

### 12. System QWERTY input — 2026-11-25

Games that draw their own text fields read characters from
`Canvas.keyPressed`, so the top-bar keyboard button now raises the iOS QWERTY
keyboard through a hidden `UITextField` in `rt_game_controller.m`. Each
committed character is posted as a MIDP key press/release pair (return sends
fire, backspace sends `KEY_CLEAR`), and the button turns amber while the field
is first responder. The bottom pad stays the compact 3x3 layout; no digit keys
were added. Verified with `InputProbe`: typing `5a` produced
`keyPressed 53`/`97` plus their releases. `RT_SYSTEM_KEYBOARD=1` and
`RT_TYPE_TEXT=abc` drive the same path from `run-sim.sh`.

### 13. Compatibility round — 2026-11-25

Three more titles were supplied and run unmodified: `Avatar2x_2.7.4_2211_TX`
(`main.DebugToDeath`), `avatar_angelchip_build11` (`main.AngelChip`) and
`NSO_1-49_ZangVPS` (`MrQuyet.MrQuyet`, Ninja School). All three reach
`startApp`, render their menus and keep painting; no missing MIDP class was
reported and no engine change was needed.

| Title | Simulator | Real iPhone |
| --- | --- | --- |
| Avatar 2 (2.7.4) | ~28 fps | 29.6 fps |
| Avatar AngelChip (build 11) | ~22.5 fps | not run |
| Ninja School (NSO 1-49) | ~22.9 fps | 18.5-18.8 fps |
| Avatar LAPRO (earlier) | ~18.6 fps | 18.3 fps |

AngelChip and Ninja School both pull a live ticker from their server, so the
online path covers more than one title. The only log noise is the expected
first-run `RecordStoreNotFoundException` / `openRecordStore: not found` for
their own stores, which the games handle and which disappear on the second
launch. Ninja School references `javax.microedition.io.file` and
`com.nokia.mid.ui.FullCanvas`; the latter exists in `java/src`, the former
still has no protocol handler (known gap) and was not exercised at boot.

### 14. File protocol (`file://`) — 2026-11-25

Ninja School references `javax.microedition.io.file`, so JSR-75 is now
implemented. The discovery that shaped it: `Connector` resolves
"<protocolpath>.<scheme>.Protocol" with `Class.forName`, and a boot-class
caller gets the boot class loader, which cannot see the app classpath. A
protocol class placed in `java/src` is therefore never found, and one that
implements an app-side `FileConnection` would also fail the cast across two
class loaders. The implementation ships inside the runtime jar through
`iosRuntime/patches/0003-file-protocol.patch` (protocol plus the JSR-75
interfaces and connection), and the five files were removed from
`java/src`.

Roots: `FileSystemRegistry.listRoots()` reports `root/`, and
`file:///root/...` maps to `<Documents>/files` (sibling of `save`, so game
files never mix with RMS). Paths containing `..` are rejected.

Verified with `test/FileProbe.java` on the simulator and on the iPhone:
create, write (12-byte UTF), read back, rename, directory listing, `mkdir`,
`setFileConnection("..")` and delete all succeed. Avatar LAPRO still boots at
18-20 fps afterwards, so the jar rebuild is not a regression.

## Reference build flow (for `iosApp/README.md` later)

macOS + Xcode 26+ + JDK 17+: `miniJVM-2.0.0/binary/build_jar.sh` (one-time) →
`j2me_api/build.sh` → open `.xcodeproj` → run. Games go in the app Documents
folder (Files app / Xcode transfer); per-game config via long-press
(resolution presets 101x80–480x800, FPS cap, 3D supersampling 3x).

### 15. Per-game controls: full keypad and turbo — 2026-11-25

`RTKeypadView` gained two per-game options, both stored in the same
`RTGameConfig` dictionary as resolution and FPS (`kb`, `turbo`) and both
applied from the focused session, since one pad serves every tab:

- the full layout adds the ten digits (21 keys, 340 pt container) beside the
  compact 3x3 pad (190 pt), for titles that ask for a number at a menu;
- turbo repeats fire: holding OK posts a release/press pulse every 80 ms.

The library's options sheet toggles both. `rt_present_game` takes the two
flags and `RTViewController addGame:...fullKeyboard:turbo:` stores them on the
session; `applySessionControls:` resizes the pad when the focused tab changes.
Scripted runs use `RT_FULL_KEYBOARD=1` / `RT_TURBO=1`.

Verification: simulator run of `build/test.jar` with both flags logged
`[RT] keypad full=1 turbo=1`, the screenshot showed the six-row pad including
digits, and a temporary 1 s synthetic hold produced 14 `keyPressed -5` lines
in InputProbe, i.e. the repeat timer works.

### 16. Background keep-alive for socket games — 2026-11-25

Socket titles hold one TCP connection for the whole session, and iOS suspends a
normal app seconds after it leaves the foreground. The app now declares
`UIBackgroundModes = [audio]` and `native/host/app/rt_background.m` plays
half a second of 16-bit silence in a loop (`AVAudioSessionCategoryPlayback` +
`MixWithOthers`). Audio keeps the process running in the background, so the
socket, JVM threads and render loop survive app switching and screen lock while
nothing is audible. `beginBackgroundTaskWithName:` is also started on
`didEnterBackground` to cover the transition, and the session is reactivated
after an interruption ends.

Verification on the simulator: with Avatar LAPRO running, launching Settings
did not suspend the app — frame logging continued from `frames=60 3.3s` to
`frames=300 16.4s` and then `frames=690 39.5s` while Settings was on screen.

### 17. Closing a tab really disconnects — 2026-11-25

Closing a tab stopped the MIDlet and destroyed its JVM, but the character
stayed online. A game normally relies on the process exiting to close its
socket, so a title that never calls `Socket.close()` left an ESTABLISHED TCP
connection behind; with several slots in one process that fd lived until the
app quit. `lsof` on the simulator showed the connection surviving the slot
destroy and sitting in `CLOSE_WAIT` after the server gave up.

`patches/0004-close-sockets-on-jvm-destroy.patch` tracks every socket created
by `org.mini.net.SocketNative` against its JVM (`bind0`, `connect0`, `accept0`,
untracked in `close0`) and, in `jvm_destroy`, shuts the surviving fds down
before waiting for threads and closes them once the threads are gone.
Verified from a clean engine checkout (patches 0002 and 0004 applied by
`build-app.sh`, `git status` left with only the expected files): the game's
connection to its server was `ESTABLISHED` before the close and gone entirely
after `Destroying slot 0 JVM`, while single-session play still runs at
~18.6 fps.

