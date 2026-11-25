# Agent guidelines - JL-Next (iOS only)

This branch ships only the iOS emulator (`iosRuntime/`). The Android app lives
on `stable` and `feature/ios-port`.

## Build and check

```sh
export JAVA_HOME=...                      # JDK with javac, e.g. Temurin
cd iosRuntime
./scripts/build-sim.sh                    # compiles + packages build/RuntimeApp.app
./scripts/run-sim.sh 30                   # installs and runs on a simulator
./scripts/build-device.sh                 # signed iphoneos build
./scripts/audit-natives.sh                # every declared native has a table row
```

`build-app.sh` applies `iosRuntime/patches/*.patch` to the miniJVM checkout
(`MINIJVM_DIR`, default `~/dev/miniJVM`) and rebuilds the runtime jar when a
patch touches its Java sources. Never vendor miniJVM sources or jars: the C
engine is MIT, but its runtime jar carries GPL-2.0-with-Classpath files.

## Rules

- `java/src/` and `native/bridge/` are vendored and read-only; keep their
  attribution headers. Fix behavior in the host or, for engine bugs, in
  `patches/`.
- The host reaches the JVM only through `native/bridge/*.h`; new protocol
  handlers that need the boot class loader must be patches.
- A native's Java declaration and its `java_native_method` table row must match
  exactly in class, name and descriptor, or the MIDlet dies with an
  `UnsatisfiedLinkError` it cannot catch.
- Be device-lenient: never throw where a real handset did not.
- Live-verify UI work with a simulator screenshot; do not rely on builds.
- Keep the smallest complete change; no Android code, no new dependencies
  without asking.

## References

`iosRuntime/ARCHITECTURE.md`, `iosRuntime/README.md`, `docs/ios-port.md`.
