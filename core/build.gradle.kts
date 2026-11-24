plugins {
    alias(libs.plugins.kotlin.multiplatform)
}

import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

kotlin {
    // JVM target lets us compile + unit-test commonMain on Windows/Linux CI
    // without a Mac. iOS targets are compiled on macOS (local Mac or CI).
    jvm()

    val xcframeworkName = "Core"
    val xcf = XCFramework(xcframeworkName)

    listOf(
        iosArm64(),
        iosSimulatorArm64(),
        iosX64(),
    ).forEach {
        it.binaries.framework {
            baseName = xcframeworkName
            // shortcut: single framework name, upgrade to bundleId when the Xcode shell needs it.
            xcf.add(this)
            isStatic = true
        }
    }

    sourceSets {
        commonMain {
            dependencies {
            }
        }
        commonTest {
            dependencies {
                implementation(kotlin("test"))
            }
        }
    }
}
