# Installer DEX progress implementation plan

## Goal and scope

Show live class-conversion progress while `AppInstaller.install()` calls DX, for both
single and bulk installation. The converting state should show the localized
`converting_wait` label, a percentage, and a count such as `534/5908`. Make the
single-installer progress bar determinate once the total is known. In a bulk
install, show this as progress for the current MIDlet separately from the existing
completed-MIDlets/total-MIDlets bar.

The denominator is the number of `.class` entries DX discovered in the input
JAR, not all archive entries. The numerator is classes handled: successfully
converted plus deliberately skipped unreadable classes. Call it processed class
progress in code; do not imply that every counted class was converted. The
percentage is `floor(100 * completed / total)` for `total > 0`, clamped to
`0..100`. This is progress through the class phase, not an estimate of overall
installation time. Before DX knows the total, retain the current indeterminate
converting state. After DX returns, show the existing saving state until the
filesystem and Library commit finish; only the existing success state means the
install succeeded. Error and cancellation behavior must remain unchanged.

## DX progress source

- In `dexlib/src/main/java/com/android/dx/command/dexer/Main.java`, add a small
  optional `ProgressListener` contract accepting `(completed, total)`. Add
  `convert(String[], ProgressListener)` and `runWithResult(Arguments,
  ProgressListener)` overloads; keep the existing signatures delegating with no
  listener so automatic reconversion and other callers do not change.
- After `ClassPathOpener` has populated `classesToProcess`, report `(0,
  totalClasses)` if the total is positive. The list size is the authoritative
  total; do not separately rescan the JAR or count resource entries.
- Report a handled class after `ClassDefItemConsumer` adds it to the DEX and
  increments `classesConverted`, and after the `UNREADABLE_SOURCE` branch of
  `processClass` increments `classesSkipped`. Use the sum of those counters.
  Fatal class errors are not counted as successfully handled; the existing
  diagnostic/error path remains authoritative.
- Conversion and skip notifications can originate on different DX threads.
  Serialize listener delivery and only emit when the integer percentage
  advances, plus the initial and final state. This bounds normal UI updates to
  about 101 per JAR, ensures monotonic counts, and leaves the DX result and
  output ordering unchanged. Do not publish `100%` for a failed conversion
  unless all classes were actually handled before the later failure.

## Installer and UI wiring

- Extend the package-local `AppInstaller.Progress` callback to carry `Stage`,
  `completed`, and `total`. Stage transitions send no determinate count;
  `install()` passes the DX listener to `Main.convert` and forwards positive
  totals as `CONVERTING` updates. Keep `SingleEmitter<Integer>` for terminal
  results only. Do not alter generation leases, staging, cancellation, or
  success publication.
- In `InstallerDialog`, post callbacks to the main thread and retain the existing
  active-installer/operation guard. Preserve the `Converting` screen's MIDlet
  details while updating its numeric progress; the current stage callback calls
  `showLoading` and would otherwise replace that screen. Extend
  `InstallerUiState.Converting` and the controller with optional typed
  `completed/total` values. Render a determinate `LinearProgressIndicator` and
  a separate numeric label (`percent% (completed/total)`) alongside the existing
  localized `converting_wait` text. Keep indeterminate presentation when no
  total is known and restore ordinary loading presentation at `SAVING`.
- In `BulkInstallViewModel.State.Running`, add nullable current-JAR progress
  fields. Forward `AppInstaller` callbacks to the current item, clearing those
  fields when the stage leaves `CONVERTING` or the active item changes. In
  `BulkInstallerDialog`, keep the existing batch bar unchanged; show the
  current-JAR count, percentage and determinate bar below its stage label only
  while a total is available. Guard against stale callbacks from a previous
  installer/item.
- Reuse the translated `converting_wait` label. Render counts and `%` as a
  separate numeric notation rather than constructing an untranslated sentence;
  give the progress indicator a meaningful combined accessibility description.
  Do not alter the existing success/error copy or unrelated locales.

## Tests and acceptance

- Extend `dexlib` conversion tests with an archive containing class and
  non-class entries: assert initial `(0, total)`, monotonic bounded updates,
  final `(total, total)` on success, and no resource entries in the total. Cover
  one unreadable skipped class and retain the current structured diagnostics.
  Verify an existing no-listener conversion call still works.
- Extend installer Compose/instrumentation tests for unknown total, a known
  sample such as `534/5908` (9%), determinate progress semantics, transition to
  saving, and the existing success/cancel paths. Test bulk current-JAR progress
  separately from the batch item counter and reset between items.
- Run focused `dexlib` JVM tests and installer UI tests, then
  `:dexlib:testDebugUnitTest`, `:app:testEmulatorDebugUnitTest`,
  `:app:assembleEmulatorDebug`, and `git diff --check`. On a connected device
  or emulator, install a large JAR and verify that progress advances without
  flooding/freeze, that saving follows class completion, and that success only
  appears after publication. Report unavailable connected checks rather than
  treating an APK build as a device test.

## Boundaries

This change does not add an overall install-time percentage, count JAR
resources, change DX conversion semantics, add a dependency, or change the
automatic reconversion UI. Preserve any unrelated work already present in the
checkout.
