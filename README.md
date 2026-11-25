# JL-Next

A J2ME (MIDP 2.0 / CLDC 1.1) emulator for iPhone and iPad. You add `.jar`
files, the app runs them: virtual keypad, per-game layouts, multiple games at
once with tabs, Form/List/Alert/TextBox screens, RecordStore persistence,
sockets, HTTP and HTTPS, background keep-alive and per-tab save data.

The runtime layer is inherited from J2ME-Decade (iOS edition, Apache-2.0) and
the JVM is [miniJVM](https://github.com/digitalgust/miniJVM), which the build
compiles from a local checkout. See `THIRD_PARTY_NOTICES.md`.

## Layout

```
iosRuntime/           the app: runtime layer, host UI, scripts, engine patches
  java/src/           MIDP/CLDC API layer (vendored, read-only)
  native/bridge/      JVM <-> host bridge (vendored, read-only)
  native/host/        our UIKit host: library, game view, forms, keypad editor
  patches/            engine fixes applied at build time
  scripts/            build-app.sh, build-sim.sh, build-device.sh, run-sim.sh
  ARCHITECTURE.md     layers, rules and where to add code
docs/                 iOS port notes and handoff
```

## Requirements

- Xcode 27 or newer with an iOS simulator runtime.
- A JDK: `export JAVA_HOME=...` (Temurin 21 or newer).
- A miniJVM checkout outside this repo, default `~/dev/miniJVM`
  (override with `MINIJVM_DIR`). Its runtime jar is built locally at build
  time and is never stored here.

## Build and run

```sh
export JAVA_HOME=...                      # JDK for javac
cd iosRuntime
./scripts/build-sim.sh                    # -> build/RuntimeApp.app
./scripts/run-sim.sh 40                   # boots a simulator, installs, runs
```

On a device, first register the phone with an Xcode project using the same
bundle id once, then:

```sh
./scripts/build-device.sh                 # -> build/device/RuntimeApp.app
xcrun devicectl device install app --device <UDID> build/device/RuntimeApp.app
xcrun devicectl device process launch --device <UDID> io.github.0xfenix.jlmodplus
```

## Adding games

Use **+** in the library, share a `.jar` to JL-Next from the Files app, or drop
files into the app's `Documents/games` folder. Long-press a game for rename,
screen size and FPS, keypad layout, turbo fire, or delete.

## Documentation

- `iosRuntime/ARCHITECTURE.md` - layers and where code belongs.
- `iosRuntime/README.md` - runtime details, flags and known gaps.
- `docs/ios-port.md` - what was verified and how.
- `docs/ios-port-handoff.md` - short status handoff.
