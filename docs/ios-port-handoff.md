# iOS port — handoff for the Mac session

Read this first, then `docs/ios-port.md` (reference architecture).
Reply to the user in Vietnamese; code and identifiers in English.

## Where things stand

- Branch: `feature/ios-port` (cut from `stable`, pushed to `origin`).
  Work here. Do not touch `app/`, `dexlib/`, Android CI.
- P0 is DONE on the repo side: KMP `core/` module (JVM + iosArm64 +
  iosSimulatorArm64, static framework `Core`), 7 platform SPIs in
  `core/.../spi/PlatformSpi.kt`, GitHub workflow `ios.yml` green on macOS
  (`assembleCoreXCFramework` → artifact `Core-XCFramework`).
- Open decisions (asked 2026-11-24, user answered):
  - miniJVM license → VERIFIED NOT Apache-2.0-clean (C code MIT, but
    `minijvm_rt.jar` is GPL-2.0-only WITH Classpath-exception-2.0). User
    chose: spike with an EXTERNAL checkout only — DO NOT vendor miniJVM
    sources or jars into this repo. External checkout lives OUTSIDE the
    repo (see step 3b).
  - 3 acceptance JARs → user will provide the actual files. Step 3c waits
    for them; do not substitute other JARs without asking.
  - Device run (step 4) → user runs on their own iPhone and reports back
    (Team ID to be added to the project when they provide it).

## Do now, in order

1. `git checkout feature/ios-port && git pull`.
   Verify: `./gradlew :core:jvmTest` passes (needs JDK 21, no Xcode needed).
2. **Xcode shell** — DONE on the repo side (`iosApp/` builds for the
   simulator). Device run (personal team + AltServer re-sign) still owed by
   the user.
3. **P1 spike** — DONE, superseded by the inherited runtime:
   a. Upstream + license recorded (see `docs/ios-port.md` §Must verify).
      User chose an external checkout; nothing of miniJVM is vendored.
   b. miniJVM + hello MIDlet reached `startApp` on the simulator
      (interpreter-only; sljit does not compile for iOS targets).
   c. FPS: first interpreter-only iOS number = **11.5 fps @ 240x320** on the
      iPhone 16 Pro simulator, from the vendored runtime (`iosRuntime/`).
      Avatar is an online game and self-exits, so device measurement is the
      next honest data point.
4. **Runtime decision** — the J2ME runtime layer is inherited from
   J2ME-Decade (iOS) into `iosRuntime/` (Apache-2.0, attribution restored,
   3D/proxy removed); the KMP shell + `PlatformSpi` boundary stays ours.
   `iosSpike/` is the superseded hand-written A/B reference and is still
   untracked.
5. **Input + window** — DONE on the simulator. `iosRuntime/native/host_ui.m`
   presents the frame in a UIKit window with a 3-column virtual keypad and
   maps touches into `j2me_input`; `test/InputProbe.java` with
   `RT_SYNTH_INPUT=1` prints every key and pointer callback, and all five
   arrive (`keyPressed 53`, `keyReleased 53`, pointer press/drag/release).
   App-life cycle must be scene-based on Xcode 27 SDKs.
6. Keep every new platform capability behind `PlatformSpi`
   (`core/src/commonMain/.../spi/PlatformSpi.kt`); `commonMain` must stay
   free of `android.*`, `java.*`, Darwin imports.

## Do not

- No `clean`, no Android changes, no new dependencies without asking.
- Do not port M3G/micro3D, JSR-82/camera/PIM/SIP, proxy tunnel — out of scope.
