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

## Reference build flow (for `iosApp/README.md` later)

macOS + Xcode 26+ + JDK 17+: `miniJVM-2.0.0/binary/build_jar.sh` (one-time) →
`j2me_api/build.sh` → open `.xcodeproj` → run. Games go in the app Documents
folder (Files app / Xcode transfer); per-game config via long-press
(resolution presets 101x80–480x800, FPS cap, 3D supersampling 3x).
