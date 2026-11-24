# iosApp — iOS shell (created on a Mac)

P0 keeps this folder as Swift sources only. The `.xcodeproj` is generated
on a Mac with Xcode 16+ (see below) and is intentionally not committed
until P0 step 4 is done on real hardware.

## Create the Xcode project (on a Mac)

1. Open Xcode → File → New → Project → iOS → App.
   - Product Name: `JLModPlus`, Interface: SwiftUI, Language: Swift.
   - Save the project inside this `iosApp/` folder.
2. Select the app target → Build Phases → + → New Run Script Phase:
   ```sh
   cd "$SRCROOT/.."
   ./gradlew :core:embedAndSignAppleFrameworkForXcode
   ```
   (Requires the `kotlin.cocoapods`-free `embedAndSignAppleFrameworkForXcode`
   task wiring; if missing, add the standard KMP Xcode integration block
   to `core/build.gradle.kts` on the Mac and re-sync.)
3. Select your personal team in Signing & Capabilities, connect an iPhone,
   build & run. Re-sign every 7 days via AltServer running on the same Mac.

## What lives here

- `JLModPlusApp.swift` — `@main` App entry, shows the spike placeholder view.
- `ContentView.swift` — placeholder screen; replaced by the real Library UI in P4.
