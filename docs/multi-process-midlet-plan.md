# Multi-process MIDlet implementation plan

## Scope and invariants

This plan covers the full-emulator flavor. The standalone `midlet` flavor keeps its current
single-process launcher. Phase 1 changes documentation only.

The design preserves these identities:

- `appId`: durable Library identity of the installed application and the identity fence used by
  preset/config authority.
- `sessionId`: durable identity of one user-created runtime instance. It survives process death and
  can be started again; it is never inferred from a PID or task ID.
- `storageKey`: existing filesystem identity of the installed application. It remains distinct from
  `appId` and is not repurposed as a session identifier.
- `dataNamespaceId`: stable identity of one session's writable RMS/private/cache namespace. The
  legacy single-instance path uses the installed `storageKey`; additional sessions receive a
  distinct namespace ID.

Process names are a finite manifest resource. They cannot be generated from `sessionId`. Writable
RMS/private/cache data must never be shared by two live runtimes, and the existing OS file-lock
contract remains mandatory.

## Current launch and runtime map

### Launch path

1. Library actions in `AppsListFragment`, post-install actions in `InstallerDialog`, and
   `ConfigActivity` call `Config.startApp(name, appPath, appId)`.
2. `Config.startApp()` validates configuration/reconversion and starts `MicroActivity` with the
   installed path and `KEY_LIBRARY_APP_ID`.
3. The manifest places `MicroActivity`, `MidletKeepAliveService`,
   `MemoryTargetBridgeService`, and Nokia notification UI in the single `:midlet` process.
4. `MicroActivity` asks the main-process `PresetAuthorityProvider` to prepare and identity-fence
   configuration. It either reattaches the one process-local `MidletThread`, or uses
   `RuntimeReplacementActivity` to stop the existing runtime and wait for Binder death before
   launching a different one.
5. `MicroLoader` loads the prepared config, clears a workdir-global cache, initializes process-wide
   Java ME state, acquires `RuntimeStorageLease` for the installed directory, repeats the `appId`
   authority check, creates a `MidletSessionJournal`, writes the singleton `MidletSessionStore`,
   starts `MidletThread`, and starts the keep-alive foreground service.
6. `MidletThread` owns MIDP lifecycle and terminal classification. Intentional exit or fatal failure
   finalizes the journal, clears the singleton route, stops the foreground service, detaches the
   host, and kills its runtime process.
7. `LauncherActivity` reads the singleton route, probes the installed-directory lease, and opens
   either the live `MicroActivity` or `MainActivity`.

### Process and state ownership

| Process | Current owners | Multi-instance implication |
| --- | --- | --- |
| Main/default | Library Room DB, `MainActivity`, launch/config flows, `PresetAuthorityProvider`, replacement and shutdown coordination | Must become the sole authoritative session/slot coordinator. Dashboard observes this owner rather than runtime statics. |
| `:midlet` | One `MicroActivity`, `MidletThread`, `MicroLoader`, `Display`, `AppClassLoader`, `ContextHolder`, RMS manager, renderer/input/audio/timing state, target memory bridge, foreground service | Static/singleton density makes one runtime per process the safe compatibility boundary. |
| `:memory_engine` | Memory editor UI and native/managed engine service | It currently assumes one target component. Multi-session target selection must be explicit and fenced, or memory editing must remain limited to the focused session until that work is complete. |

Important process-local singletons include `EmulatorApplication.instance`, `ContextHolder`,
`MidletThread.instance`, `Display.instance`, `AppClassLoader` data/resource state, `MidletSystem`
properties, `RecordStore`'s manager, graphics/rendering singletons, `SkinLayer`, timing/audio state,
and memory-discovery state. Separate Android processes isolate these without changing Java ME code.

### Storage and IPC

- RMS is stored under `workdir/data/<installed-storage-key>` through
  `AppClassLoader.getDataDir()` and `ContextHolder`. File-connection private/cache properties point
  into the same installed-app data tree. This is safe for one runtime but cannot support concurrent
  instances of the same app.
- `ContextHolder.getCacheDir()` currently resolves to the shared `workdir/cache` and `MicroLoader`
  clears it during launch. This must become session-scoped before concurrent launch.
- `RuntimeStorageLease` locks a digest of the installed directory. It currently prevents two
  runtimes of the same app; multi-instance requires a lease over the session storage identity while
  retaining a separate `appId` check against replacement/reinstall.
- Preset/config ownership is correctly centralized by synchronous ContentProvider IPC. Runtimes
  may read prepared snapshots and publish supported runtime changes only through this authority.
- `MidletSessionStore` is one atomic routing record. It cannot represent a session set.
- `MidletSessionJournal` already has a UUID, PID, process name, stage, outcome, workdir and storage
  fields. It remains diagnostic/play-stat evidence, not the dashboard's mutable source of truth.

## Architecture options

### Option 1: fixed process slots with a main-process coordinator

Declare a bounded set of concrete runtime components assigned to fixed process names. Each slot
has a runtime Activity, control endpoint, target memory
bridge, and keep-alive service in the same process. A main-process coordinator durably maps a
`sessionId` to one slot while running and communicates through Binder. Each runtime process still
hosts exactly one Java ME heap.

Advantages: preserves process-local emulator assumptions, gives real PID/crash isolation, allows
stable explicit Activity components/tasks, and makes capacity/background cost bounded. The main
cost is a small amount of generated-looking slot plumbing and explicit recovery logic.

### Option 2: one runtime host process containing multiple in-process runtime containers

Run several class-loader/thread containers in one Android process and make every static Java ME,
renderer, media, input, RMS, timing, and lifecycle owner session-indexed.

This avoids manifest slot duplication but fails the required process isolation and turns pervasive
global state into shared mutable state. A fatal native/VM failure would still take down all
instances. It is substantially more complex and is rejected.

### Selected architecture

Use Option 1 with two initially declared slots, `:midlet0` and `:midlet1`, for the MVP. The design
keeps the slot table extensible, but adding more slots requires manifest components and measured
memory evidence. Slot 0 is also the compatibility path for existing `Config.startApp()` launches. When no
multi-instance session exists, its data path and user flow remain the current legacy path.

## Proposed session model

`RuntimeSessionRecord` is stored by the main process in an app-private atomic registry guarded by
an OS file lock. Room is unnecessary for a small bounded runtime set and would couple runtime
availability to the workdir Library database lifecycle.

Required fields:

- `sessionId`, `appId`, installed app path, installed `storageKey`, `dataNamespaceId`, title and
  selected MIDlet class;
- desired state (`STOPPED` or `RUNNING`) and observed state (`STARTING`, `RUNNING`, `BACKGROUND`,
  `STOPPING`, `CRASHED`, `STOPPED`);
- assigned slot, launch generation/token, PID, process name, last heartbeat/state timestamp, and
  optional terminal reason;
- legacy-storage flag, created/updated timestamps, and whether the session may be user-restarted.

Only the coordinator allocates/releases slots and mutates authoritative records. Runtime reports
carry `sessionId + slot + generation`; stale reports are rejected. Binder death changes a matching
live record to `CRASHED`/`STOPPED` and releases its slot. Startup reconciliation clears assignments
whose control Binder/lease cannot be proven live. A PID is observation only.

## Runtime component and task design

- Add concrete `RuntimeSlot0Activity` ... `RuntimeSlot3Activity` subclasses of `MicroActivity` and
  matching slot services. Each manifest Activity has a fixed process name and fixed task affinity.
  Explicit component intents select the process; no activity alias is relied on to choose a process.
- Each slot Activity validates that intent `sessionId`, slot and launch generation match the
  coordinator assignment before loading guest code.
- Each slot owns one stable Android task. Open/Focus launches the assigned component with task
  reordering flags; it never starts a different slot or reconstructs identity from the latest app.
- The runtime binds to a narrow coordinator service and registers one control Binder. Stop targets
  that Binder only. Death recipients provide process-death detection without polling.
- `MicroActivity` and `MidletThread` keep Java ME lifecycle ownership. Session coordination is added
  around launch/termination; the dashboard never calls guest lifecycle methods directly.

## Storage isolation

The installed converted payload and prepared config remain shared read-mostly inputs fenced by
`appId`. Writable paths are selected before any guest static initialization:

- Legacy slot-0 session: `workdir/data/<installed-storage-key>` for backward compatibility.
- Additional/persistent sessions: `workdir/data/.sessions/<dataNamespaceId>` where the namespace ID
  is an allocator-produced stable opaque key recorded in the session registry.
- Session cache/dex optimization/temp paths: app-private or workdir cache directories containing
  the same `dataNamespaceId`; one session never clears another session's directory.

`AppClassLoader` receives an explicit runtime data directory rather than deriving it from the
installed directory. File Connection properties use the same directory. The runtime lease is held
for that session data directory until process death. Installation identity is independently
rechecked through `PresetAuthority` before guest writes start. Deleting/reinstalling an app cannot
retarget an old session because the stored `appId` must still resolve to the recorded installed
path; stale sessions become non-startable without deleting their private data.

Atomic RMS behavior remains unchanged inside one process. Independent directories plus independent
processes prevent cross-session corruption. No file lock is removed or bypassed.

## Lifecycle and background policy

- Start is a user-initiated coordinator command. The coordinator reserves a slot and persists
  `STARTING` before launching the explicit Activity.
- A slot reports `RUNNING` only after lease acquisition, identity revalidation and `MidletThread`
  startup. Open/Focus only changes Android presentation; it does not create a second runtime.
- Home/background keeps the runtime alive best-effort with that slot's foreground service and a
  session-specific notification/PendingIntent. Notification IDs and request codes are slot/session
  distinct.
- Android 12+ foreground-service start restrictions are respected: process recovery in the
  background records a stopped/crashed session and posts actionable UI/notification state; it does
  not silently restart a runtime when the OS disallows it.
- Stop finalizes only the addressed session, stops only its service/task, and lets that slot process
  die. It does not invoke whole-emulator shutdown.
- Explicit whole-emulator exit remains separate and enumerates every declared runtime/auxiliary
  process before main exits. Current `EmulatorShutdownService` and tests assume exactly `:midlet`
  and must be generalized.
- Recents removal policy must be made session-specific. Removing one runtime task stops that
  session, not all emulator processes. Removing the Library task does not implicitly stop sessions.

## Dashboard ownership

Add a Compose Material 3 session surface backed by coordinator snapshots/Flow in the main process.
It shows installed title, instance label, status and last failure, with Start, Stop and Open/Focus
commands. The UI owns no mutable runtime state and optimistically displays only coordinator-issued
transitions. Library app actions retain the existing one-tap legacy launch; an additional action
creates or opens managed instances.

## Implementation phases and files

### Phase 2: core coordinator and allocator

Create under `io.github.h3nb.jlmodplus.runtime.sessions`: session record/state codecs, atomic
registry, two-slot allocator, coordinator service/client contract, slot descriptors and recovery.
Add slot components and manifest declarations. Add JVM tests for deterministic allocation,
capacity, release, generation fencing, stale records and simulated Binder/process death.

Likely modified files: `AndroidManifest.xml`, `Constants.java`, `EmulatorApplication.java`,
`EmulatorShutdownService.kt`, crash process-role classification, and shutdown tests.

### Phase 3: runtime integration and storage

Modify `Config.startApp`, launch callers, `MicroActivity`, `MicroLoader`, `MidletThread`,
`AppClassLoader`, `ContextHolder`, `MidletKeepAliveService`, `RuntimeStorageLease`,
`MidletSessionStore` (replace singleton routing use), and memory-target binding. Add concrete slot
Activities/services and session-aware launch/control intents.

Add tests for `appId`/generation fencing, unique storage paths, lock ownership, independent RMS
round trips, same-app concurrent launch, reattach/open, stop isolation and crash isolation.

### Phase 4: dashboard

Add a session ViewModel/store and Compose screen integrated with the existing Library host and
localized resources. Add UI/controller tests for status projection and command routing; add selected
screenshot coverage only after interaction behavior is correct.

### Phase 5: background and optimization

Make notifications and task-removal behavior session-aware, validate FGS failure paths, reconcile
process death, and measure per-slot PSS/RSS on a representative low-memory emulator/device. Do not
optimize until measurements identify a bottleneck.

### Phase 6: validation

Run focused JVM tests, then `:app:testEmulatorDebugUnitTest` and
`:app:assembleEmulatorDebug`. Run connected tests for two same-app slots, PID separation, RMS
persistence, stop/crash isolation, task focus, process death, notification actions and legacy
single launch. Update the external shutdown smoke script for multiple runtime processes.

## Checkpoints and acceptance evidence

1. Allocator: two unique concurrent assignments for MVP; stale release cannot free a newer generation.
2. Launch: two sessions for one `appId` report different declared process names and PIDs.
3. Storage: each writes and reloads distinct RMS values after stop/start; leases cover distinct
   session paths and remain exclusive per path.
4. Isolation: stopping or crashing slot A leaves slot B's Binder, PID, FGS and RMS usable.
5. Routing: dashboard and notifications open the exact assigned Activity/task after backgrounding.
6. Recovery: coordinator restart and runtime process death converge to accurate states without an
   automatic background launch.
7. Compatibility: legacy Library launch, preset preparation, Java ME lifecycle/UI/input, config
   editing, memory tooling for the focused runtime, and standalone `midlet` flavor remain valid.

## Remaining risks

- Additional runtime processes can exceed low-memory device budgets; capacity above the two-slot
  MVP requires measurement and may need explicit memory-pressure UX.
- Android may kill background slots despite FGS, and notification permission denial reduces user
  visibility. State must reflect death rather than promise indefinite background execution.
- Current memory-engine IPC names a single target component. Session-aware target selection and
  death fencing need focused design/testing; until complete, only the focused session should expose
  the editor.
- Crash and process-exit code classifies only `:midlet`; all slot process names must map to the same
  semantic role while retaining the concrete process name/session correlation.
- Legacy workdir-global cache clearing, screenshot naming, shared soundbank/config reads and any
  native static resource paths require audit during Phase 3. Writable uses must become session
  scoped; intentionally shared read-only inputs may remain shared.
- Multiple Android tasks change existing "return to Library" and Recents semantics. Device tests are
  required across API 23 and current target behavior; JVM tests cannot prove task/FGS behavior.

