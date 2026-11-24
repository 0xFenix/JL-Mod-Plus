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
2. Create the Xcode shell per `iosApp/README.md` (Xcode 16+, personal team
   signing, run on a real iPhone, confirm AltServer re-sign works).
   Commit the resulting `.xcodeproj` + any `core/build.gradle.kts` Xcode-sync
   wiring on this branch and push.
3. P1 spike — miniJVM, not a new interpreter:
   a. Find the true miniJVM upstream, record URL + license in
      `docs/ios-port.md` ("Must verify" section). Stop and ask the user if
      the license is GPL/copyleft.
   b. Build miniJVM for `iosSimulatorArm64`, compile a hello-world MIDlet
      plus a minimal `javax` API surface with `javac --release 8`, run it.
      Reference: `jvm_bridge.{h,c}` and `j2me_api/build.sh` in j2me-ios.
   c. Success = MIDlet reaches `startApp` on simulator; record ops/sec +
      FPS of one real game. If the interpreter is too slow, stop and report
      before writing any LCDUI port.
4. Keep every new platform capability behind `PlatformSpi`
   (`core/src/commonMain/.../spi/PlatformSpi.kt`); `commonMain` must stay
   free of `android.*`, `java.*`, Darwin imports.

## Do not

- No `clean`, no Android changes, no new dependencies without asking.
- Do not port M3G/micro3D, JSR-82/camera/PIM/SIP, proxy tunnel — out of scope.
