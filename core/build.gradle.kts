plugins {
    alias(libs.plugins.kotlin.multiplatform)
}

kotlin {
    // JVM target lets us compile + unit-test commonMain on Windows/Linux CI
    // without a Mac. iOS targets are compiled on macOS (local Mac or CI).
    jvm()

    iosArm64()
    iosSimulatorArm64()

    targets.withType<org.jetbrains.kotlin.gradle.plugin.mpp.KotlinNativeTarget> {
        binaries.framework {
            baseName = "Core"
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
