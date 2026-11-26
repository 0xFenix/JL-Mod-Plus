# Multi-MIDlet runtime

Several MIDlets run side by side in one `:midlet` process, one tab each, and the user switches
between them without losing guest state. This document owns the tab model, the state that is
shared by design, the gaps the current implementation leaves, and the plan for closing them.

## What ships today

- Up to 10 tabs (`AmsRegistry.MAX_TABS`, `AmsRegistry.java:32`); tabs can come from different
  suites or repeat one suite (`MicroActivity.duplicateSelectedTab`, `MicroActivity.java:750`).
- Each tab has its own `MicroLoader`, guest thread `MidletMain-<tab>` (`MidletThread.java:100`),
  `Display`, foreground state and event queue. Thread-to-tab routing is `MidletTabRouter`.
- The activity hosts every tab in one `RuntimeHostView`. Only the selected tab presents a
  screenable (`Display.java:604`: a background tab keeps its guest current state but mounts
  nothing); switching tabs calls `Display.refreshHostPresentation`.
- Per-tab resource roots and RMS *name caches* are tab-dispatched (`AppClassLoader.TabResources`,
  `RecordStore.MANAGERS`), so two different JARs never read each other's resources.
- `MidletKeepAliveService` keeps the process alive in the background with a partial wake lock and
  a high-performance Wi-Fi lock, so socket games stay connected while another app is foreground.

## Identity model

Two identifiers must not be confused:

| Identifier | Scope | Owner | Meaning |
| --- | --- | --- | --- |
| installed suite (`storageKey`, `LibraryAppEntity.id`) | installed app | Library (Room) | JAR, `converted/`, `configs/`, `data/`, storage lease |
| tab id | running session | `AmsRegistry` | guest thread, `Display`, UI state |

Storage is keyed by the installed suite **and the launch slot**. Two tabs of one suite each get
their own data directory: the first tab keeps `workdir/data/<storageKey>` so existing saves load
unchanged, and later tabs use `<storageKey>#2`, `#3`, … (`AppClassLoader.bindTab(tabId, slotIndex)`).
RMS files, `fileconn.dir.private` and the private file root therefore belong to a tab, which is
what makes two accounts of one game possible. The OS storage lease, the profile snapshot and the
JAR stay per installed suite — two tabs are still one install.

Slot order is open order, so closing tab 1 and opening another gives the new tab slot 2 and its
proxy/save directory. Clearing a game's data clears every `<storageKey>#N` directory beside it.

## Per-slot SOCKS5 proxy

Guest sockets are Java (`org.microemu.cldc.socket.SocketConnection`), so the proxy lives above
`java.net`, not in native code:

- `org.microemu.cldc.net.Socks5Tunnel` performs RFC 1928 CONNECT (ATYP 1 for dotted IPv4, ATYP 3
  for hostnames so the proxy resolves DNS) and RFC 1929 user/password auth.
- `io.github.h3nb.jlmodplus.net.ProxyStore` keeps the saved proxies and the per-install slot list
  (`proxy_slots_<storageKey>`), imported as `host:port[:user[:pass]]` lines or one entry at a time.
- `io.github.h3nb.jlmodplus.net.ProxyRouting` maps the calling guest thread to its tab, the tab to
  its installed suite and slot (`MicroLoader` binds both at tab creation), and returns the proxy or
  `null` for a direct connection. A slot with no assignment always connects directly; nothing
  inherits another slot's proxy.
- `SocketConnection` tunnels when a proxy applies, and `ssl/Connection` tunnels first and then wraps
  the socket with `createSocket(plain, host, port, true)`, so `socket://`, `http://` and `https://`
  all leave through the proxy. Serverside sockets and datagrams do not.

Credential storage is the plain SharedPreferences file, same as the iOS runtime. The liveness probe
connects through the saved proxy to `1.1.1.1:80`, so a proxy that filters that address reads as dead.

The list screen (`ProxyListActivity`, opened from Settings → SOCKS5 proxy or the runtime Proxy
dialog's Manage action) runs in the `:midlet` process, so its writes and `ProxyRouting`'s reads
share one SharedPreferences cache. The Settings subtitle count is read from the main process and can
lag until that process restarts. The runtime menu's Proxy entry assigns the selected tab's slot and
applies to its next connection; already-open sockets keep their route.

## State that follows the selected tab

These are process-wide today and apply last-tab-wins; while two tabs run they can leak one tab's
configuration into another:

- `ContextHolder.getVk()` and `currentActivity` (`util/ContextHolder.java:57`).
- `Canvas.settings`, `Canvas.fpsLimit`, timing-overlay flags.
- `Displayable.virtualWidth/Height`, `KeyMapper.androidToMIDP`, `SkinLayer.instance`,
  `MidletSystem.PROPERTY`.
- Audio: `RuntimeAudioCoordinator` has one active session and an audible-tab filter; memory
  editor has one target (`MemoryRuntimeSession`).

The intended rule is: a tab owns its configuration, and switching tabs re-applies it. A global
setting changed from the runtime menu applies to the tab it was made in, not to the process.

## Known gaps

1. Runtime menu actions use the activity's original `microLoader` instead of the selected tab's
   loader (`MicroActivity.java:551`, `:624`, `:1047`, `:1098`), so speed, class loading and
   profile edits can hit the wrong game. This is a defect, not a design choice.
2. Library play opens the runtime by replacing the process (`RuntimeReplacementActivity`), so a
   second game from the Library closes every running tab. Opening a tab must be possible without
   a replacement.
3. Launch clears shared scratch (`workdir/cache`, `dex_opt`) on every start
   (`MicroLoader.java:240`, `:579`), which a second tab would disturb.
4. `MidletSessionStore` keeps one route record, and death/restore restores one app; there is no
   per-tab restore contract.
5. Closing a tab calls `destroyApp` but the process (and the guest heap) lives on. Sockets a
   guest never closed can stay open, which is exactly how a character stayed online on iOS until
   the engine was patched to close a destroyed runtime's sockets. Android needs the same
   verification.
6. ~~No SOCKS proxy support exists on Android at all~~ — implemented, see "Per-slot SOCKS5 proxy";
   which is what makes several accounts of one online game usable.

## Plan

Ordered so each step is shippable alone:

1. Target the selected tab in every runtime-menu and tab action (gap 1).
2. Open a game from the Library as a new tab when a runtime is already live, keeping the process
   (gap 2); stop clearing shared scratch on launch (gap 3).
3. Apply per-tab configuration on tab switch: canvas settings, FPS limit, key mapping, skin,
   system properties (section above).
4. Verify that closing a tab releases the guest's sockets and network threads (gap 5); add an
   explicit close path for the runtime if it does not.
5. ~~Decide storage isolation~~ — done: per-slot data directories, first slot keeps the old path.
6. ~~Per-tab proxy list and routing~~ — done: tunnel, store, routing, slot binding, the proxy list
   screen, and the runtime per-tab picker.

Out of scope until the above lands: more than 10 tabs, per-tab processes, per-tab audio mixing
(one tab is audible at a time), and restoring tabs after process death.

## Contracts this feature must keep

- [Runtime UI](runtime-ui.md): one current `Displayable` per tab, presentation transactions, the
  `RuntimeHostView` boundary between guest screens and app chrome.
- [Preset, configuration, and installed identity](preset-config-contract.md): runtime storage is
  leased per installed identity and fenced on delete/replace; a tab boundary must not bypass it.
- [Library data](library-data-contract.md): `converted/`, `configs/`, `data/` ownership, catalog
  state kept only in the Library.
- [Java ME compatibility](java-me-compatibility.md): foreground ownership — Android task
  foreground, AMS foreground and LCDUI foreground are different things; a background tab is not
  a Home press.
- [UI ownership](ui-ownership-map.md) and [app UI development](app-ui-development.md): the tab
  strip and runtime menu stay app-owned Compose/View code around the compatibility-sensitive
  host.

## Verification

Unit tests that already cover the model and must stay green when extending it:
`AmsRegistryTest`, `MidletTabRouterTest`, `RecordStoreTabIsolationTest`, `MidletThreadOwnershipTest`.

Manual matrix for any change here:

- Two tabs of different suites: each renders, keeps state across switches, menu edits the
  selected one.
- Two tabs of one suite: state of both tabs survives a switch; document whether they share data.
- Close one tab while a sibling runs: no process death, no leftover socket, guest destroyed once.
- Background/foreground with two tabs: keep-alive holds, audio follows the selected tab.
- Library play with a live runtime: opens a tab instead of replacing the process.
