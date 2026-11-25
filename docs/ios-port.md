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

### 18. Files share sheet and About sheet — 2026-11-25

The app registers itself as a handler for JAR files with two owner-ranked
document types: an imported UTI `io.github.0xfenix.jlmodplus.jar` and a
concrete-type entry covering `com.sun.java-archive`, `public.zip-archive` and
`com.pkware.zip-archive`. iOS resolves `.jar` to `com.sun.java-archive` (a
simulator `UTType` lookup and macOS `mdls` both confirm it), and claiming only
`com.pkware.zip-archive` at alternate rank left the app buried under the share
sheet's "More" list; declaring `com.sun.java-archive` at owner rank puts it in
the main row. Either entry routes the file through the import path below. `scene:openURLContexts:` and the
cold-start `scene:willConnectToSession:` both route file URLs through
`rt_import_jar_path()`, which copies into `Documents/games` with a
non-clashing name, honours the security-scoped URL, and posts
`RTGamesChanged` so the visible library rescans and pops to the game list.

The game chrome gained an `!` button next to the FPS toggle; it presents the
About alert (app name, author Trần Đức Huy, third-party credits J2ME Loader and
miniJVM).

Verification on the simulator: launching with `RT_OPEN_JAR=/tmp/rotate2.jar`
copied the file into `Documents/games/rotate2.jar` and the library listed it as
"Avatar" (6 titles, screenshot read); `RT_SHOW_ABOUT=1` produced the About
alert over the running game (screenshot read); a normal library launch shows
the top bar with back chevron, title, keyboard, speedometer and `!`
(screenshot read). User-verified on the iPhone, 2026-11-25: sharing a `.jar`
from Files now lists JL-Next in the main share sheet, not under "More".

### 19. Save data per tab — 2026-11-25

A JAR used to own one save directory, so launching the same title in a second
tab made both tabs share their RecordStores. Save directories are now claimed
per session: the first tab keeps `<save>/<jar name>`, later tabs take the first
free `<jar name> 2`, ` 3`, and so on, chosen against the directories of the
tabs that are currently open. The choice is logged as
`[RT] slot N save=<dir>`. Deleting a game removes the base directory and every
`<jar name> N` sibling, so an account created in a second tab is cleaned up
with the title.

Verified on the simulator by opening Avatar LAPRO twice: slot 0 logged
`save=game`, slot 1 logged `save=game 2`, both rendered concurrently, and the
two directories contained independent `rms/*.rsh` files.

### 20. Per-game keypad layout editor — 2026-11-25

Games disagree about which keys matter, so the fixed compact/full presets are
now backed by an editor. `rt_keypad_editor.m` presents a table of slots on the
same three-column grid (three to six rows); each slot is assigned LSK, RSK, an
arrow, fire, a digit, `*`, `#` or left blank (`0`). Choosing save writes the
comma-separated MIDP codes into the game's `keys` config entry, and
`RTKeypadView` renders an explicit layout in preference to the preset, sizing
itself from the row count. Blank slots are real gaps, not disabled keys.

Verified on the simulator: the editor renders every slot with its key name and
the row controls; `RT_KEYS="-6,-1,-7"` produced the expected single row, and
the six-row preset with digits still renders unchanged.

### 21. Closing running games from the library — 2026-11-25

The library's aggregate "Đang chơi" row used to show the system delete
affordance, but its commit handler returned early, so the button did nothing.
The row now has its own trailing swipe action, **Đóng tất cả**: it drops every
session and calls `jvm_bridge_request_stop_slot` for each one, leaving the run
threads to destroy their JVMs and socket fix-up to patch 0004. Game rows got an
explicit **Xoá** action with the existing confirmation, and full-swipe is off
for both so a stray gesture cannot destroy state.

Verified on the simulator with two running tabs: the close-all path logged
`[RT] closing all sessions`, then a stop request per slot and one
`Destroying slot N JVM` per slot, with no crash.

### 22. Screen forms start at the top — 2026-11-26

The Form/List/Alert/TextBox panel used to bottom-anchor its stack like a sheet,
so a form with text fields slid under the keyboard as soon as one was focused.
The panel now pins the stack to the top of a full-height container inside the
scroll view and ends the scroll view at `keyboardLayoutGuide.topAnchor`; short
forms read from the top down, long ones scroll, and the keyboard only shrinks
the visible area instead of covering the field.

Verified on the simulator with FormProbe: the login form renders title, fields,
choice rows and the OK button from the top of the panel.

### 23. Commands: soft types stay out, the rest fold into a menu — 2026-11-26

A MIDlet can attach any number of commands. The types a handset keeps on
screen — `Command.OK`, `BACK`, `CANCEL`, `EXIT` — are rendered as buttons: OK
(or the first of them when there is no OK) takes the amber full-width slot and
the remaining soft commands sit two per fill-equally row at half width, with a
blank slot when the count is odd so a lone button does not stretch. Every other type
(`SCREEN`, `ITEM`, `HELP`, `STOP`) folds into a `Tùy chọn (n)` button that
opens an action sheet, matching J2ME Loader. A screen with only ordinary
commands keeps the previous behaviour: one command is a plain button, several
collapse into a single menu. Whenever the half-width buttons would come out odd
— a two-command screen, or OK plus three soft commands — the primary shrinks to
half width and takes the free slot, so every row is full instead of ending in a
lonely button. Long-pressing a list row sets that row as the
selected index (`J2ME_UI_LIST_SET_INDEX`) and then opens a menu with every
command, so commands act on the held item.

Verified on the simulator with `test/CommandProbe.java` (OK, Back, Cancel,
Exit, Help, Save): the panel showed `Chọn` full width, `Quay lại` / `Huỷ` at
half width, `Thoát` at half width and `Tùy chọn (2)` sharing the last row. Commands are
separated by 10 pt gaps.

### 25. Selected list row and row spacing — 2026-11-26

List rows used to run together as one continuous block. They are now separate
44 pt targets with a 6 pt gap, and the selected row is filled with the accent
at 16% alpha with an amber semibold title, so the current item is obvious. The
The bridge model had no selection at all, so the host guessed index 0 and every
list looked like its first row was current. `List` now reports its
`selectedIndex` through `NativeBridge.setListSelectedIndex` from
`showNative()`, `setSelectedIndex()` and `handleListSelect()`, and the panel
renders whatever the guest says while still updating immediately on taps and
long-presses (clamped when the list shrinks). Verified on the simulator with
`test/ListProbe.java`, which preselects index 3: `Mục 4` highlighted, rows
separated, commands visible below.

One vendored accessor was added for this (`List`, `NativeBridge.java`,
`j2me_ui.m/.h`), because a host-only guess cannot know the guest's selection.

### 26. Alert commands behave like a phone — 2026-11-26

`Alert` used to be a dead end: the host drew its text with one hardcoded `OK`
button that posted `J2ME_UI_ALERT_DISMISSED`, so a MIDlet's own alert commands
were never rendered and its `CommandListener.commandAction` never ran.

Now the Java side follows J2ME-Loader's `Alert`: the implicit
`DISMISS_COMMAND` is present from construction, `addCommand` drops it as soon
as the MIDlet adds a real command and `removeCommand` puts it back when the
list empties, and `setCommandListener(null)` installs a default listener that
dismisses to the displayable given to `Display.setCurrent(alert, next)`.

The host renders the alert title and text, then reuses the normal command
buttons, so a tap posts `J2ME_UI_COMMAND_ACTION` with the alert's real command
id and `Display` fires `commandAction` on the alert like any other
`Displayable`. The old `J2ME_UI_ALERT_DISMISSED` branch and the
`dismissAlert:` button are gone.

Verified on the simulator with `test/AlertProbe.java`: log shows
`[ALERT] confirm commands=2`, `[ALERT] silent commands=1`,
`[ALERT] commandAction label=Đồng ý on=javax.microedition.lcdui.Alert`, then
the implicit-dismiss alert closes silently and
`[ALERT] commandAction label=Đóng on=javax.microedition.lcdui.Form`; the
screenshot shows the title, body, amber `Đồng ý` at full width and `Để sau` at
half width. Alert timeouts and the indicator gauge are still not implemented.

### 24. Long lists scroll so commands stay visible — 2026-11-26

A List with more items than fit used to grow the panel until the command
buttons were pushed below the screen. Rows now live in an inner scroll view
capped at 360 pt (short lists still shrink to their content), and the command
buttons are laid out after the card, so they remain visible while the list
scrolls.

Verified on the simulator with `test/ListProbe.java` (30 items): the panel
showed the title, rows 1–8 inside the bounded card and both commands right
below it.

### 27. Per-tab SOCKS5 proxy — 2026-11-26

The target titles are online and some only accept connections from their
region, while a MIDlet has no proxy API. The engine now offers a SOCKS5 tunnel
per JVM: `patches/0005-socks5-proxy-per-jvm.patch` stores one proxy per
`MiniJVM`, and `connect0` connects to the proxy instead of the target, performs
the RFC 1928 handshake (RFC 1929 when user/password are set), then returns the
socket to the guest. Domain targets are sent as domains so the proxy resolves
them. `sslc_connect` (https) builds its own connection and stays direct.

The host keeps proxies in `NSUserDefaults` (`RTProxies`) with a stable
`host:port:user` id and offers two add flows in the library: a four-field form
and a bulk paste of `ip:port:user:pass` lines (blank user/password allowed).
Each tab picks from that list with the network button next to About; the active
one is marked ✓ and the choice is saved per JAR in `RTGameConfig`, so it is
reapplied on the next launch. Changing it on a running tab calls
`jvm_bridge_set_slot_proxy`, which applies immediately for new connections.

Verified on the simulator against `scripts/socks-fixture.sh` (anonymous 1080 and
authenticated 1081): with a proxy selected the fixture logged
`CONNECT 127.0.0.1:9099 via 1080` / `via 1081` and the network probe still got
`[NET] socket echo=ECHO PING` and `[NET] http code=200`; Avatar LAPRO logged
`CONNECT upxu.net:80 via 1080` and kept rendering at ~18.6 fps, i.e. its own
online traffic went through the tunnel. The patch was validated from a clean
engine checkout (0002, 0004 and 0005 applied in order).

### 28. Proxy liveness test — 2026-11-26

The proxy list gained an amber **Kiểm tra tất cả** card above the rows that probes
every saved proxy. The host opens a TCP connection with a 4 s connect deadline, sends the
RFC 1928 greeting (offering no-auth and, when a user is set, username/password),
answers RFC 1929 when the proxy asks for it, then asks the proxy to CONNECT to
`1.1.1.1:80`; the reply code decides the verdict. Each row shows `Sống · <ms>` in
green or `Chết · <reason>` in red, and the card summarises `N sống · M chết`. Probes run concurrently on a global queue so a black-holed host cannot
stall the list, and both socket timeouts are 5 s.

Verified on the simulator with `socks-fixture.sh` (anonymous 127.0.0.1:1080,
user/password 127.0.0.1:1081) plus a closed port 127.0.0.1:1099: the log printed
`[PROXY] test 127.0.0.1:1080 -> Sống · 48ms`, `…1081 -> Sống · 49ms`,
`…1099 -> Chết · không kết nối được`, and the screenshot showed the two green
verdicts, the red failure and the amber action card reading `2 sống · 1 chết`.

The probe target is a compromise: a proxy that filters `1.1.1.1` reports dead
even though it can still carry the game's traffic.

`RT_PROXY_TEST=1` opens the list and runs the probe automatically for scripted
runs (simctl cannot tap).

### 29. No empty card on a fresh tab — 2026-11-26

Opening a second tab drew a stray rounded dark strip across the top of the game
chrome until the MIDlet painted. `-focusSlot:` asks the bridge for that slot's
active screen action, and a slot that has not shown anything yet reports 0;
`rt_form_ui_present` only removed the panel for `SHOW_CANVAS` (1), so 0 fell
through to `rebuildForAction:` where no branch matched and an empty surface card
was left in the stack. The guard is now `action < J2ME_UI_ACTION_SHOW_FORM`,
which clears the panel for 0 and for Canvas alike. Verified on the simulator by
opening two tabs and reading the screenshot: normal chrome, no strip.

### 30. Proxy choice is remembered per game — 2026-11-26

The in-tab picker already wrote `RTGameConfig[proxy]`, but nothing proved it
survived a restart and the library gave no sign of it. Verified with a
temporary picker hook (removed): picking `127.0.0.1:1080` logged `proxy=…` on
the next launch with no proxy environment variable. `rt_store_game_config` now
calls `-synchronize` so a pick cannot be lost when the app is closed right
after, and the library subtitle shows `qua host:port` ahead of the last-played
phrase, so truncation cuts the date first. `test/ListProbe`/`NetworkProbe` rows
are unaffected.

### 31. Proxy is remembered per slot and per game — 2026-11-26

A tab keeps its own proxy while it runs, and the pick is also written to the
game's config, so a new tab of that game starts on the same proxy and the
library row shows `qua host:port`. Sharing one proxy between two tabs is
allowed on purpose: a player may run two accounts behind the same exit while
another tab uses a different one. An earlier rule that rotated a fresh tab onto
an unused proxy was removed — it made a plain second tab diverge from the game's
saved proxy. Verified on the simulator by opening the same JAR twice: both slots
logged the game's saved proxy.

### 32. HTTP through a proxy works again — 2026-11-26

With a proxy selected, games logged in over their socket but every `http://`
request failed with `Socket connect error` (reproduced on the iPhone and on the
simulator with a real proxy). The tunnel was sending the CONNECT request with
`host_len` counting the NUL the engine appends to the host byte array, so the
proxy saw a domain one byte too long and closed the connection — no reply code,
hence the silent failure. `socks5_tunnel` now trims trailing zero bytes before
building the request. curl through the same proxy always worked, which is what
pointed at our request rather than the proxy. Verified from a clean engine
checkout: patches 0002/0004/0005 applied in order, `[HTTP] code=200` through
`113.160.166.35:35944`, Avatar still at ~18 fps.

### 33. Proxy is remembered per launch slot of a game — 2026-11-26

Closing the app lost the per-tab proxy because only one value was stored per
game. Each tab of a game is now numbered by the order it is opened, and the
picker writes the id to `RTGameConfig[slots][n]` for that game (`-tabIndexForSession:`
counts sibling sessions sharing the jar). `addGame:` reads that entry first and
falls back to the game's single proxy. Verified on the simulator: run 1 opened
the same JAR twice and picked 1080 for tab 1 and 1081 for tab 2; run 2 launched
a fresh process with no picks and logged `proxy=127.0.0.1:1080:` for slot 0 and
`proxy=127.0.0.1:1081:game` for slot 1.

### 34. A slot without a proxy goes direct — 2026-11-26

Launching a tab used to fall back to the game's last picked proxy, so a fresh
slot silently reused an IP another slot had chosen. `launchGame:` now passes an
empty proxy and `addGame:` only adopts the value saved for its own tab number;
everything else connects directly. The per-game `proxy` key and the `qua
host:port` library hint were dropped with it — a row no longer claims a proxy
the game may not use. Environment runs still select one through `RT_PROXY`.
Verified on the simulator: `test.jar` has no saved slot proxy and logged
`proxy=-` with no `[SOCKS]` line, while an earlier tab of another game kept its
saved `127.0.0.1:1080:`.

