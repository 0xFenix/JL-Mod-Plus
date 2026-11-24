package io.github.h3nb.jlmodplus.core.spi

/**
 * Minimal platform contracts for the iOS port.
 *
 * commonMain must stay free of `android.*`, `java.*` (JVM-only) and
 * Darwin/ObjC imports. Every platform capability the VM/LCDUI layers need
 * goes through one of these interfaces; `androidMain`/`iosMain` provide the
 * implementations later (P2-P3).
 */

/** Destination for guest framebuffer pixels (ARGB_8888, row-major). */
interface DisplaySurface {
    val width: Int
    val height: Int
    fun present(pixels: IntArray, width: Int, height: Int)
}

/** PCM audio output. No-op until P3 wires AVAudioEngine (iOS) / Oboe (Android). */
interface AudioSink {
    fun writePcm(samples: ShortArray, sampleRateHz: Int, channels: Int)
    fun flush()
}

/** Persistent per-suite storage backing for RMS RecordStores. */
interface RecordStoreBackend {
    fun listStores(suiteId: String): List<String>
    fun readRecord(suiteId: String, storeName: String, recordId: Int): ByteArray?
    fun writeRecord(suiteId: String, storeName: String, recordId: Int, data: ByteArray): Int
    fun deleteStore(suiteId: String, storeName: String)
}

/** Monotonic + wall clock. Lets the VM avoid platform clock APIs directly. */
interface PlatformClock {
    fun currentTimeMillis(): Long
    fun nanoTime(): Long
}

/** Key/pointer events from the host shell into the guest. */
interface KeySource {
    fun pollEvents(): List<KeyEvent>
}

data class KeyEvent(
    val code: Int,
    val pressed: Boolean,
)

/** Minimal HTTP transport for `Connector.open("http://...")`. */
interface HttpTransport {
    fun get(url: String): ByteArray
}

/** Logging that routes to Logcat on Android, os_log on iOS. */
interface PlatformLogger {
    fun d(tag: String, message: String)
    fun w(tag: String, message: String, throwable: Throwable? = null)
    fun e(tag: String, message: String, throwable: Throwable? = null)
}
