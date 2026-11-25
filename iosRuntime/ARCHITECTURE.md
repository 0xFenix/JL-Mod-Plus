# iosRuntime architecture

The runtime is two layers: a vendored J2ME implementation (read-only) and our
iOS host (editable). Keeping the boundary explicit is what makes upgrades of
the vendored layer possible without untangling our UI from it.

```
host/app/rt_main.c            entry point, env parsing, UI vs headless
host/api/rt_host.h            public C API for the host (create/open games)
host/library/rt_game_store    installed JARs, settings, names — no JVM, no views
host/library/rt_library_vc    library list UI
host/library/rt_jar_manifest  manifest + icon extraction via miniz (no JVM)
host/game/rt_game_view        framebuffer view, touch mapping, keypad
host/game/rt_game_controller  JVM sessions, tabs, flush, app/scene delegates
host/forms/rt_form_panel      Form/List/Alert/TextBox over the j2me_ui model
host/theme/rt_theme.h         colors, radii, spacing
----------------------------------------------- layer boundary
native/bridge/                vendored: jvm_bridge, j2me_render, j2me_ui,
                              j2me_input, j2me_audio (Apache-2.0)
java/src/                     279 vendored javax.microedition classes
patches/                      engine fixes applied to the miniJVM checkout
```

## Rules

- `native/bridge/` and `java/src/` are **read-only**. Changes there go through
  `patches/*.patch` (engine) or a documented, justified edit plus a provenance
  note (Java API layer). Never rewrite them to make host code easier.
- Host code reaches the emulator only through `jvm_bridge.h`, `j2me_render.h`,
  `j2me_input.h`, `j2me_ui.h` (controller/forms), and through `rt_host.h` for
  game lifecycle. The library never links a JVM symbol.
- One public header per module; everything else stays `static` in its `.m`.
- Aim for files under ~300 lines. When one grows past that, look for a missing
  module rather than a new section comment.
- UI text and behaviour live here, not in the vendored layer.

## Where to add code

| Task | File |
| --- | --- |
| New library row/action (sort, import, delete) | `host/library/rt_library_vc.m` |
| New per-game setting | `host/library/rt_game_store.{h,m}` |
| JAR metadata (icon, manifest field) | `host/library/rt_jar_manifest.{h,c}` |
| Canvas size, keypad layout, touch mapping | `host/game/rt_game_view.m` |
| Tab behaviour, focus, per-slot lifecycle | `host/game/rt_game_controller.m` |
| Window switcher grid (cards, close, scroll) | `host/game/rt_tab_grid.m` |
| Native screen (Form/List/Alert) rendering | `host/forms/rt_form_panel.m` |
| Colour, spacing, corner radius | `host/theme/rt_theme.h` |
| Engine fix | `patches/` (never edit `~/dev/miniJVM` in place) |
| New `Connector` protocol (needs the boot class loader) | `patches/` — see `0003-file-protocol.patch` |

## Build

```
export JAVA_HOME=~/.sdkman/candidates/java/25.0.5.0+8-tem
./scripts/build-sim.sh       # simulator app
./scripts/build-device.sh    # iphoneos build, signs with the dev profile
./scripts/run-sim.sh 40      # install + launch on the simulator
```

`build-app.sh` compiles `java/src` into `build/j2me_api.jar`, applies every
patch in `patches/` to the external miniJVM checkout and rebuilds its runtime
jar when a patch touches Java. The miniJVM checkout is never committed.

## Testing without a person

`scripts/run-sim.sh` forwards `SIMCTL_CHILD_*` env vars that the host reads:
`RT_SHELL`, `RT_AUTOLAUNCH`, `RT_AUTOLAUNCH_ALL`, `RT_EXTRA_JAR`,
`RT_FOCUS_CYCLE`, `RT_CLOSE_AFTER`, `RT_SHOTS`, `RT_SNAPSHOT_*`,
`RT_SYNTH_INPUT`. Probes in `test/` (`InputProbe`, `FormProbe`, `NetworkProbe`,
`HttpProbe`) exercise input, screens and networking; `make-test-jar.sh`
packages them.
