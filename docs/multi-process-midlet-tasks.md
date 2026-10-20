# Multi-process MIDlet task plan

Status legend: `[ ]` not started, `[~]` in progress, `[x]` complete, `[!]` blocked.
Execution markers: **SEQ** is on the critical path; **PAR** may run in parallel after its listed
dependencies. Production work must not start until this plan is reviewed.

## Architecture decision record

The selected design is a main-process session coordinator with two statically declared runtime
slots for the MVP: `:midlet0` and `:midlet1`. Each slot runs exactly one Java ME heap and owns a
fixed Activity, control endpoint, keep-alive service, memory target bridge, task, and process-local
static state. The coordinator is the only mutable session/slot authority.

Identity rules:

- `appId` is the durable installed-app identity and preset/config fence.
- `storageKey` remains the installed filesystem identity defined by the repository contract.
- `sessionId` is the durable user-visible runtime-instance identity.
- `dataNamespaceId` identifies session-private RMS/private/cache/dex-temp storage. The legacy
  instance maps to the existing `storageKey`; additional instances use opaque stable namespaces.
- PID, Android task ID, process slot and launch generation are observations/leases, never durable
  session identity.

The session registry is app-private, atomic, small, and main-process owned. Runtime processes use
narrow Binder IPC and generation fencing. Preset writes continue through `PresetAuthorityProvider`.
The dashboard consumes coordinator snapshots and never owns runtime state.

## MVP milestone

MVP is complete when two sessions of the same installed MIDlet can be started from a minimal
developer-facing entry point, run in `:midlet0` and `:midlet1` with different PIDs, write different
RMS values, stop/restart with their own values intact, and stop/crash independently. It includes
coordinator state inspection and Open/Focus plumbing, but not the polished dashboard, complete
notification UX, memory-editor multi-target support, or capacity above two slots.

MVP critical path: MP-001 -> MP-004 -> MP-005 -> MP-006 -> MP-007 -> MP-101 -> MP-102 -> MP-103
-> MP-104 -> MP-105.

## Architecture experiments

### [ ] MP-001 - Validate slot Activity, task and process behavior (**SEQ**, Phase 2)

**Goal:** Prove the manifest/task model before production component proliferation.

**Dependencies:** Plan approval.

**Files/classes:** Debug-only manifest and fixture Activities under `app/src/debug/`; focused
instrumentation test under `app/src/androidTest/`; no main-source behavior change.

**Implementation:** Declare two debug fixture Activities in different fixed processes and task
affinities. Launch, reorder, recreate, background and remove each task. Record process name/PID and
verify an explicit component always reaches the intended slot. Check API 23 and a current API where
available. Decide `launchMode`, `FLAG_ACTIVITY_NEW_TASK`, `REORDER_TO_FRONT`, and task-removal policy
from evidence.

**Acceptance:** Two fixtures coexist as distinct tasks/PIDs; Open/Focus targets the correct task;
recreation never migrates a session to another process.

**Tests:** Connected instrumentation for launch/focus/recreation/task removal; manifest contract
test for fixed process names and non-exported components.

**Risk/rollback:** OEM task behavior may differ. Keep the experiment debug-only and delete it after
capturing the chosen manifest contract and tests.

### [ ] MP-002 - Validate writable-path and dex-cache isolation (**PAR**, Phase 2)

**Goal:** Identify every shared writable path that blocks concurrent same-app launch.

**Dependencies:** Plan approval; may run with MP-001 and MP-003.

**Files/classes:** Investigation/tests around `MicroLoader`, `AppClassLoader`, `ContextHolder`,
`AndroidRecordStoreManager`, `FileCacheDataSource`, NES/SNES MIDlets and code-cache helpers.

**Implementation:** Build a path inventory from launch through class loading and MMAPI. Prototype a
pure `RuntimeStorageLayout` mapper. Reproduce concurrent access to the current workdir cache and
`code_cache/dex_opt`, which `MicroLoader` currently clears globally. Verify that distinct RMS and
FileConnection roots work without changing guest code. Determine whether optimized dex may be
shared read-only or must be per namespace/process.

**Acceptance:** A reviewed path table labels each path read-only shared, main-authority writable, or
session-private; no unknown launch-time writable path remains for MVP.

**Tests:** JVM path-mapping/traversal tests; connected two-process probe for RMS and dex load races.

**Risk/rollback:** External-storage path rules may vary by API. If shared optimized dex cannot be
proven safe, use per-slot app-private directories for MVP and revisit deduplication only after
measurement.

### [ ] MP-003 - Validate coordinator IPC and process-death semantics (**PAR**, Phase 2)

**Goal:** Choose the smallest reliable IPC boundary for registration, commands and snapshots.

**Dependencies:** Plan approval; may run with MP-001 and MP-002.

**Files/classes:** Debug fixture service/client; comparison with `PresetAuthorityProvider`,
`RuntimeReplacementActivity`, and existing AIDL memory services.

**Implementation:** Prototype a main-process bound service with runtime registration Binder,
death-recipient tracking and one-way state reports. Verify coordinator restart, runtime death,
client rebinding and stale-generation rejection. Compare with ContentProvider calls; retain Binder
because commands and death ownership are stateful, while preset authority remains unchanged.

**Acceptance:** Runtime death is observed without polling; a stale Binder/report cannot mutate a
new assignment; coordinator restart converges without auto-starting a guest.

**Tests:** Connected kill/rebind test plus JVM generation-fencing tests.

**Risk/rollback:** Binder callbacks can race service teardown. Persist assignment before launch and
make every callback idempotent; discard the debug fixture after the contract is fixed.

## Phase 2 - Core session and slot coordination

### [ ] MP-004 - Define immutable session model and storage layout contract (**SEQ**)

**Goal:** Establish the data model used by all later phases.

**Dependencies:** MP-002 and MP-003 decisions.

**Files/classes:** New `runtime/sessions/RuntimeSessionRecord`, `RuntimeSessionState`,
`RuntimeSlot`, `RuntimeLaunchIdentity`, `RuntimeStorageLayout`; `Constants` intent keys.

**Implementation:** Define schema/versioning, legal state transitions, installed identity fields,
`dataNamespaceId`, desired/observed state, slot/generation/PID observations and terminal reason.
Define canonical path validation and the legacy namespace mapping. Keep Android types out of the
core model where practical.

**Acceptance:** Invalid IDs, unsafe paths, illegal transitions and stale generations fail closed;
model serialization round-trips deterministically.

**Tests:** JVM tests for validation, equality, transition table, schema compatibility, path escape
rejection and legacy mapping.

**Risk/rollback:** Schema churn can strand records. Start at version 1 with explicit decode failure
and atomic backup; no migration framework is added until a real second schema exists.

### [ ] MP-005 - Implement atomic registry and two-slot allocator (**SEQ**)

**Goal:** Make the main process the single durable allocator and session-state authority.

**Dependencies:** MP-004.

**Files/classes:** New `RuntimeSessionRegistry`, `RuntimeSessionCodec`, `RuntimeSlotAllocator`, lock
helper; tests under `app/src/test/.../runtime/sessions/`.

**Implementation:** Store records in app-private `files/runtime/sessions/` using `AtomicFile` and an
OS-backed registry lock. Allocate the lowest free slot, persist `STARTING` before returning a launch
permit, release only on matching generation, and reconcile incomplete writes conservatively.

**Acceptance:** Two allocations succeed, the third reports capacity, duplicate start is
idempotent, stale release cannot free a reused slot, and interrupted writes recover to the last
committed snapshot.

**Tests:** JVM allocator matrix, stale generation, duplicate command, corrupt/partial file,
concurrent thread access and restart reconstruction tests.

**Risk/rollback:** Registry corruption could hide sessions. Preserve last committed AtomicFile
backup and expose a fail-closed reset path that does not delete session data.

### [ ] MP-006 - Implement coordinator Binder contract and service (**SEQ**)

**Goal:** Own session commands, runtime registration and observable snapshots in the main process.

**Dependencies:** MP-003 and MP-005.

**Files/classes:** New coordinator service/client, Binder/AIDL contract if required, command/result
models, observer registry; main manifest declaration.

**Implementation:** Add create/start/stop/open queries, runtime register/report/unregister calls,
generation validation, Binder death handling and snapshot subscription. Serialize registry writes
on one coordinator executor. Do not invoke MIDP callbacks from the coordinator.

**Acceptance:** Every mutation passes through the coordinator; death of slot A changes only A;
observers receive ordered immutable snapshots; stale callbacks are ignored.

**Tests:** JVM reducer/command tests; connected Binder registration/death/rebind test from MP-003.

**Risk/rollback:** A started coordinator service may conflict with background restrictions. Prefer
a bound/main-process service and explicit user-initiated Activity launch; persist enough state that
service recreation is harmless.

### [ ] MP-007 - Add two concrete runtime slot component families (**SEQ**)

**Goal:** Materialize fixed process slots without dynamic process assumptions.

**Dependencies:** MP-001 and MP-006.

**Files/classes:** `RuntimeSlot0Activity`, `RuntimeSlot1Activity`; slot keep-alive/control and memory
target service subclasses or shared bases; `AndroidManifest.xml`; `app/src/midlet/AndroidManifest.xml`.

**Implementation:** Refactor final runtime services only as needed to permit thin slot subclasses.
Declare each family in its fixed process/task affinity. Preserve standalone flavor removal/merging.
Add a slot descriptor mapping component names to slot IDs and process names.

**Acceptance:** Manifest merge produces exactly two full-emulator runtime slots; standalone MIDlet
flavor retains its existing in-process `MicroActivity`; no component is externally exported.

**Tests:** Manifest instrumentation test, flavor assembly, slot descriptor JVM test.

**Risk/rollback:** Component duplication can drift. Keep subclasses behavior-free and centralize
the descriptor table; revert to one declared slot if MP-001 disproves stable task behavior.

### [ ] MP-008 - Generalize diagnostics and whole-emulator shutdown (**PAR**, Phase 2)

**Goal:** Recognize slot processes without losing session correlation or shutdown ordering.

**Dependencies:** MP-004 and MP-007; may run alongside MP-101 preparation.

**Files/classes:** `CrashReporter`, `ProcessExitStore`, `ProcessStateSummary`,
`EmulatorShutdownService`, related unit/instrumentation tests and shutdown smoke script later.

**Implementation:** Classify `:midlet0`/`:midlet1` as semantic role `midlet` while retaining the
concrete process name. Order auxiliary processes, all runtime slots, then main on whole-emulator
exit. Never use whole-emulator shutdown for per-session Stop.

**Acceptance:** Slot crashes appear as MIDlet incidents correlated by `sessionId`; shutdown order
includes both slots and remains deterministic.

**Tests:** Extend process-role, exit-store and `EmulatorShutdownOrderTest` cases.

**Risk/rollback:** Broad prefix matching could misclassify future helpers. Match the declared slot
descriptor set, not arbitrary `:midlet*` names.

## Phase 3 - Runtime integration and MVP

### [ ] MP-101 - Add fenced launch envelope and slot registration (**SEQ**)

**Goal:** Start a runtime only when the intent matches a live coordinator permit.

**Dependencies:** MP-006 and MP-007.

**Files/classes:** `MicroActivity`, slot Activities, new runtime coordinator client, intent parser,
`MicroLoader`, `MidletSessionJournal` metadata handoff.

**Implementation:** Parse `sessionId`, slot, launch generation, `appId`, installed `storageKey`,
`dataNamespaceId`, path and requested MIDlet class before guest initialization. Bind/register with
the coordinator, reject mismatches, and report PID/process/state. Reattach only to the same
process-local `MidletThread` and launch identity.

**Acceptance:** Forged, stale or cross-slot intents fail before RMS/class loading; a valid intent
registers exactly once; reopening the same session reuses its heap.

**Tests:** JVM launch-envelope validation; connected stale-generation, wrong-slot, recreation and
reattach tests.

**Risk/rollback:** Binding during Activity creation can stall presentation. Bound the handshake and
show a host-owned failure surface; never fall back to an unfenced launch.

### [ ] MP-102 - Isolate RMS, private/cache and dex paths (**SEQ**)

**Goal:** Guarantee independent writable storage for concurrent same-app sessions.

**Dependencies:** MP-002, MP-004 and MP-101.

**Files/classes:** `MicroLoader`, `AppClassLoader`, `ContextHolder`, `RuntimeStorageLease`, path
helpers, `MicroLoaderFileConnectionRootTest`, lease tests and Android RMS fixture.

**Implementation:** Inject explicit data/cache/dex-temp directories before Java ME statics use
them. Keep legacy data at `data/<storageKey>`; place additional sessions under
`data/.sessions/<dataNamespaceId>`. Acquire the lifetime lock on the chosen writable namespace and
separately repeat `PresetAuthority.prepareRuntime(appPath, appId)`. Stop clearing shared workdir or
code-cache roots. Point FileConnection cache/private properties to the same namespace.

**Acceptance:** Two same-app processes concurrently open/write identical RMS store names without
sharing bytes; restart restores each value; cache/dex initialization has no cross-session delete;
an occupied namespace cannot be launched twice.

**Tests:** JVM path/lease/FileConnection tests; connected two-slot RMS persistence and concurrent
dex load test; retain existing installer lease tests with installed-identity semantics reviewed.

**Risk/rollback:** Changing `AppClassLoader` static path setup can break legacy guests. Preserve the
old constructor behavior behind the legacy layout and add an explicit overload for managed
sessions; rollback affects only managed-session creation, not legacy data.

### [ ] MP-103 - Implement per-session lifecycle control and death reconciliation (**SEQ**)

**Goal:** Make Start/Stop/Open and runtime termination target one session only.

**Dependencies:** MP-101 and MP-102.

**Files/classes:** `MidletThread`, `MicroActivity`, coordinator runtime client/control Binder,
`MidletSessionStore` compatibility layer, slot task helper.

**Implementation:** Report `STARTING/RUNNING/BACKGROUND/STOPPING/STOPPED/CRASHED` with generation
fencing. Route Stop to the matching runtime Binder and preserve existing MIDP destruction/watchdog
behavior. On terminal cleanup, clear only that session assignment, release only its namespace and
kill only its slot process. Open/Focus starts/reorders only the assigned slot Activity.

**Acceptance:** Stop A leaves B running and controllable; crash A releases its slot without
changing B; Open B cannot focus A; stale terminal cleanup cannot clear a replacement generation.

**Tests:** JVM lifecycle reducer tests; connected stop/crash/open isolation tests based on existing
`CrashRuntimeIsolationTest` fixtures.

**Risk/rollback:** Current `MidletSessionStore` is deeply referenced by tests and launcher paths.
Keep a temporary legacy adapter for slot 0, migrate callers incrementally, then remove only after
all routes use coordinator snapshots.

### [ ] MP-104 - Preserve legacy single-launch behavior (**SEQ**)

**Goal:** Keep existing Library/config/installer launch semantics while routing through slot 0.

**Dependencies:** MP-103.

**Files/classes:** `Config.startApp`, `AppsListFragment`, `InstallerDialog`, `ConfigActivity`,
`AutoReconversionDialog`, `LauncherActivity`, shortcut creation and launch tests.

**Implementation:** Translate an existing one-tap launch into “open existing legacy session or
create/start legacy session”. Keep current config review/reconversion and `appId` authority checks.
Use the installed `storageKey` namespace. Replace “different MIDlet kills current runtime” only for
managed full-emulator flow; standalone flavor remains unchanged.

**Acceptance:** Existing launch entry points require no new user decision, existing RMS remains
visible, same live runtime reopens, config/reconversion still gates launch, and standalone flavor
behavior is unchanged.

**Tests:** Unit tests for launch decision policy; existing config/installer tests; connected legacy
launch/reopen/settings/shortcut smoke.

**Risk/rollback:** Legacy users may have ambiguous active sessions after upgrade. Reserve exactly
one legacy session record and never migrate/copy existing RMS automatically.

### [ ] MP-105 - Deliver and verify the two-session MVP (**SEQ**, milestone gate)

**Goal:** Prove the core acceptance scenario before dashboard work.

**Dependencies:** MP-008 and MP-104.

**Files/classes:** Debug/instrumentation lifecycle MIDlet fixture, coordinator probe UI or test-only
control Activity, new `MultiProcessMidletRuntimeTest`.

**Implementation:** Install one fixture app, create legacy and additional sessions, launch both,
capture PID/process identity, write distinct RMS markers, background/focus each, stop/restart each,
and inject a fatal failure into one slot.

**Acceptance:** Two different PIDs; independent persistent RMS; Stop A and crash A do not stop B;
both sessions can be reopened; legacy one-tap launch remains functional.

**Tests:** One connected end-to-end suite on API 35 x86_64, plus API 23 smoke if available. Record
which native/ABI paths are and are not exercised.

**Risk/rollback:** This is the no-go gate. Do not begin the full dashboard if isolation, persistence
or process targeting is flaky; revert managed multi-instance entry points while retaining proven
core abstractions only if they do not alter legacy behavior.

## Phase 4 - Dashboard

### [ ] MP-201 - Expose session snapshots to app-owned UI (**SEQ**)

**Goal:** Provide lifecycle-safe, read-only dashboard state and command results.

**Dependencies:** MP-105.

**Files/classes:** New `RuntimeSessionsViewModel`, coordinator repository/client adapter, UI models;
`MainActivity`/Library host integration point.

**Implementation:** Convert coordinator snapshots to stable UI models, observe through StateFlow,
and expose create/start/stop/open commands with explicit pending/error results. Scope state to the
active installed workdir and reject stale Library generations.

**Acceptance:** Process death/configuration change does not duplicate commands; UI state reflects
coordinator truth; changing workdir cannot display/control another root's sessions.

**Tests:** JVM ViewModel/reducer tests for ordering, stale workdir, pending commands and errors.

**Risk/rollback:** Mirroring coordinator state can create two sources of truth. UI models contain no
independent lifecycle state and are fully replaceable by each snapshot.

### [ ] MP-202 - Build the session dashboard and app actions (**SEQ**)

**Goal:** Let users inspect and control sessions with Compose Material 3.

**Dependencies:** MP-201.

**Files/classes:** New dashboard Compose screen/components, Library navigation/action integration,
localized strings and icons.

**Implementation:** Show title/instance/status and Start, Stop, Open/Focus actions. Add an app action
to create another instance while preserving one-tap legacy launch. Use existing adaptive Library
navigation patterns; dashboard never binds directly to runtime services.

**Acceptance:** All actions remain reachable at compact width and 200% text; status/action
availability matches coordinator state; Back/navigation preserve Library state.

**Tests:** Compose interaction tests for commands, loading/error/empty/capacity states and
accessibility semantics.

**Risk/rollback:** Adding a new top-level destination may complicate navigation. Prefer an existing
Library-owned route/pane unless independent history is demonstrated.

### [ ] MP-203 - Add selected visual and navigation coverage (**PAR**, Phase 4)

**Goal:** Protect stable dashboard presentation without overproducing baselines.

**Dependencies:** MP-202; may run with Phase 5 backend work.

**Files/classes:** Screenshot previews/tests and Library navigation instrumentation.

**Implementation:** Cover one compact populated state, one large/adaptive state and one failure or
capacity state. Exercise Back, rotation and state restoration separately from golden screenshots.

**Acceptance:** Selected screenshots are reviewed renderer output; interaction tests prove action
reachability and navigation restoration.

**Tests:** `validateEmulatorDebugScreenshotTest` plus targeted Compose/connected navigation tests.

**Risk/rollback:** Renderer drift is not authorization to replace baselines. Preserve references
until candidate images are inspected under the repository workflow.

## Phase 5 - Background behavior and optimization

### [ ] MP-301 - Make FGS notifications and task removal session-aware (**SEQ**)

**Goal:** Support best-effort background execution without cross-session shutdown.

**Dependencies:** MP-105; may begin in parallel with MP-201.

**Files/classes:** `MidletKeepAliveService` base/slot services, notification helper/channel,
`LauncherActivity` or session-open receiver, runtime task-removal handling, manifest FGS metadata.

**Implementation:** Use distinct notification IDs/PendingIntent request codes and exact
`sessionId` targets. Start FGS only from allowed user-initiated launch paths. On denial, keep the
guest launch valid but report reduced background protection. Removing runtime task A stops A only;
whole-emulator Exit remains explicit.

**Acceptance:** Notifications open the correct session; stopping/dismissing one session does not
cancel another notification or runtime; denied notification/FGS promotion produces accurate state.

**Tests:** JVM notification identity tests; connected notification action, Home, Recents removal and
permission-denied tests on relevant API levels.

**Risk/rollback:** Platform/OEM FGS policy varies. Do not promise persistence; degrade to observable
`BACKGROUND_UNPROTECTED`/stopped state rather than retry loops.

### [ ] MP-302 - Implement coordinator and process-death recovery (**SEQ**)

**Goal:** Converge durable session state after main/runtime process death and device restart.

**Dependencies:** MP-301 and MP-103.

**Files/classes:** Coordinator reconciliation, registry recovery, runtime registration handshake,
launcher/dashboard recovery presentation, diagnostic correlation.

**Implementation:** On coordinator startup, mark assignments unconfirmed, accept only matching
generation registrations, then classify unmatched records using Binder/lease/process evidence.
Never auto-start guests from background recovery. Preserve stopped session data and expose a user
Start action.

**Acceptance:** Killing main leaves runtime usable and able to re-register; killing one runtime
marks only that session crashed/stopped; reboot leaves sessions restartable but not silently running.

**Tests:** Connected main-process kill, runtime kill, simultaneous death and stale-registration
tests; JVM reconciliation table tests.

**Risk/rollback:** Liveness probes can produce false certainty. Treat unknown as unconfirmed and
require user action; never delete data or reuse a slot until generation ownership is resolved.

### [ ] MP-303 - Route memory editor to an explicit focused session (**PAR**, Phase 5)

**Goal:** Preserve memory tooling without binding the shared engine to an arbitrary slot.

**Dependencies:** MP-103 and MP-003; may run with MP-301/MP-302 after MVP.

**Files/classes:** `MemoryRuntimeSession`, `MemoryTargetBridgeService` slot variants,
`MemoryEngineService`, editor controllers/Activity and memory IPC tests.

**Implementation:** Pass slot component and session/generation identity to the engine. Bind the
target bridge explicitly, reject target switches with active stale operations, and surface the
focused session in editor state. MVP fallback may disable the editor for non-focused sessions until
this task completes, without altering guest execution.

**Acceptance:** Editor operations reach only the selected live session; killing/switching target
invalidates stale tokens; one session ending does not tear down another session's runtime.

**Tests:** Extend `MemoryIpcRuntimeTest` for two targets, stale token, target death and switch.

**Risk/rollback:** Shared engine state may be expensive to multi-tenant. Keep one active editor
target at a time and clear engine state on target switch; do not duplicate the engine process
without memory evidence.

### [ ] MP-304 - Measure memory and decide post-MVP slot capacity (**PAR**, Phase 5)

**Goal:** Set capacity from evidence and optimize only measured bottlenecks.

**Dependencies:** MP-105 and representative native build; may run after MP-301 independently of
dashboard completion.

**Files/classes:** Benchmark notes/results under `docs/`, optional debug-only measurement helper;
manifest only if capacity changes.

**Implementation:** Measure PSS/RSS and startup latency for Library only, one runtime, two runtimes,
and memory editor on representative low/mid devices or emulators. Record API/ABI/assets and idle vs
active states. Inspect duplicated native/audio/renderer memory. Decide whether to remain at two
slots or add statically declared slots.

**Acceptance:** Reproducible measurements and an explicit capacity decision; any optimization names
the measured allocation/startup source and remeasures it.

**Tests:** No synthetic performance threshold in unit tests. Re-run functional MVP after any
optimization or slot-count change.

**Risk/rollback:** Emulator memory is not physical-device evidence. Keep default at two unless
physical or representative evidence supports more; slot expansion is independently revertible.

## Phase 6 - Validation and release readiness

### [ ] MP-401 - Complete focused automated regression coverage (**SEQ**)

**Goal:** Cover contracts introduced by the feature at the lowest effective layer.

**Dependencies:** MP-202, MP-302 and MP-303; MP-304 decision recorded.

**Files/classes:** Session/allocator/storage/launch JVM tests, manifest tests, targeted existing test
updates and instrumentation fixtures.

**Implementation:** Remove obsolete singleton-route assertions only where behavior changed; retain
legacy contract coverage. Consolidate duplicate scenarios. Add identity fencing, storage isolation,
slot death, notification targeting and dashboard command coverage.

**Acceptance:** Focused tests exercise each distinct failure mode and no test relies on timing-only
sleeps when Binder/state synchronization is available.

**Tests:** Run focused classes repeatedly, then `:app:testEmulatorDebugUnitTest`.

**Risk/rollback:** Broad rewrites can hide regressions. Adapt existing tests incrementally and keep
legacy fixtures until replacement coverage proves the same observable contract.

### [ ] MP-402 - Run connected acceptance matrix and shutdown smoke (**SEQ**)

**Goal:** Verify Android process/task/FGS/RMS behavior that JVM tests cannot prove.

**Dependencies:** MP-401.

**Files/classes:** `MultiProcessMidletRuntimeTest`, updated `CrashRuntimeIsolationTest`, runtime
shutdown fixture/script and validation documentation.

**Implementation:** Run two same-app sessions, PID/RMS persistence, Stop A, crash A, Open/Focus,
Home/Recents, main death, notification action, app reinstall identity fence and whole-emulator Exit.
Exercise API 23 and API 35/36 where infrastructure permits; use x86_64 override for emulator.

**Acceptance:** Every repository acceptance criterion has recorded evidence or an explicit gap;
whole-emulator shutdown removes all declared slot and auxiliary processes in order.

**Tests:** `connectedEmulatorDebugAndroidTest` targeted classes and
`scripts/runtime-shutdown-smoke.ps1`, including dispatch-failure mode where relevant.

**Risk/rollback:** Flaky process tests are not acceptable evidence. Replace polling with observable
markers/Binder synchronization; quarantine is not a completion strategy.

### [ ] MP-403 - Run build gates, inspect diff and update contracts (**SEQ**)

**Goal:** Produce final reviewable evidence without overstating completion.

**Dependencies:** MP-402.

**Files/classes:** Documentation updates including `runtime-ui.md`,
`preset-config-contract.md` only if semantics intentionally changed, development/smoke instructions,
and final source diff.

**Implementation:** Run `git diff --check`, focused tests,
`:app:testEmulatorDebugUnitTest`, `:app:assembleEmulatorDebug`, relevant lint and instrumentation APK
assembly. Inspect final diff for unrelated changes, exported components, flavor regressions and
missing localization. Report unavailable SDK/device checks precisely.

**Acceptance:** Required builds pass; contracts describe multi-runtime behavior; standalone flavor
and legacy launch remain valid; unresolved gaps are listed and feature completion is not claimed
without MVP/acceptance evidence.

**Tests:** Commands from `docs/development.md`; screenshot validation only when dashboard references
changed.

**Risk/rollback:** Late cross-cutting failures should roll back the smallest incomplete phase, not
weaken locks, identity checks, CI or compatibility contracts.

## Dependency and parallelism summary

1. MP-001, MP-002 and MP-003 can run in parallel after plan approval.
2. MP-004 -> MP-005 -> MP-006 -> MP-007 is sequential core work.
3. MP-008 can run after MP-007 in parallel with early MP-101 preparation.
4. MP-101 -> MP-102 -> MP-103 -> MP-104 -> MP-105 is the sequential MVP path.
5. After MVP, MP-201 and MP-301 may run in parallel. MP-203 may run alongside MP-302/MP-303.
6. MP-303 and MP-304 are parallel post-MVP investigations/implementation.
7. MP-401 -> MP-402 -> MP-403 is the final sequential validation path.

## Open decisions requiring evidence

- Exact Activity flags/launch mode/task affinity combination: decide from MP-001, not assumption.
- Per-session optimized dex strategy: shared read-only versus per-slot copy, decided by MP-002.
- Coordinator implementation detail: handwritten Binder versus AIDL, decided by contract size and
  MP-003 evidence; no new dependency is needed either way.
- Runtime registry format: properties or compact structured codec. It must remain versioned,
  atomic and dependency-free; decide during MP-004.
- Whether `data/.sessions/` is visible/exportable in app bundles. MVP keeps it runtime-owned and
  excluded from existing installed-app bundle semantics until a product requirement says otherwise.
- Memory editor target switching semantics: one active target is the conservative default pending
  MP-303.
- Capacity above two slots: explicitly deferred to MP-304 measurements.

## First implementation task after review

Start MP-001. Task/process behavior is the highest-risk Android boundary and directly determines
manifest declarations, Open/Focus behavior, Recents semantics and the shape of slot components. In
parallel, MP-002 and MP-003 can be assigned once the plan is approved because they have disjoint
debug/test write scopes.
