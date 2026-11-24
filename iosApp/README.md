# iosApp — iOS shell

`JLModPlus.xcodeproj` is committed on `feature/ios-port` (Xcode 27, iOS 17+,
Swift 5). Target `JLModPlus` builds the `JLModPlusApp` / `ContentView`
placeholder; Swift does not import `Core` yet (P4).

## Build

Simulator (no signing needed, verifies the project + Kotlin sync wiring):

```sh
export JAVA_HOME=<jdk-21+> ANDROID_HOME=~/Library/Android/sdk
xcodebuild -project iosApp/JLModPlus.xcodeproj -scheme JLModPlus \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Xcode wiring

- First build phase is `Sync Kotlin Core framework` (always runs):
  ```sh
  cd "$SRCROOT/.."
  ./gradlew :core:embedAndSignAppleFrameworkForXcode
  ```
  The `embedAndSignAppleFrameworkForXcode` task is auto-created by the KMP
  plugin — no extra wiring in `core/build.gradle.kts` was needed.
- `FRAMEWORK_SEARCH_PATHS` includes `$(SRCROOT)/../core/build/xcode-frameworks`
  for when Swift starts importing `Core`.
- GUI Xcode builds need the same env: launch Xcode from a shell with
  `JAVA_HOME`/`ANDROID_HOME` exported, or `launchctl setenv` them.

## Still pending (needs your iPhone)

1. Open the project in Xcode → select your personal team in Signing &
   Capabilities → connect an iPhone → build & run.
2. Confirm AltServer re-sign works (7-day cycle).
3. Report back; only then is P0 step 4 fully closed.

## What lives here

- `JLModPlusApp.swift` — `@main` App entry, spike placeholder view.
- `ContentView.swift` — placeholder screen; replaced by the real Library UI in P4.
