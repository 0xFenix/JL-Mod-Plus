// SPDX-License-Identifier: Apache-2.0
package io.github.h3nb.jlmodplus.runtime.slots.debug

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.AtomicFile
import android.view.Gravity
import android.widget.TextView
import java.io.File
import java.util.Properties
import java.util.UUID

object RuntimeSlotProbeLauncher {
    const val ACTION_OPEN = "io.github.h3nb.jlmodplus.debug.runtime.OPEN"
    const val ACTION_FINISH = "io.github.h3nb.jlmodplus.debug.runtime.FINISH"
    const val ACTION_KILL_PROCESS = "io.github.h3nb.jlmodplus.debug.runtime.KILL_PROCESS"
    const val OPEN_FLAGS = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT

    @JvmStatic fun open(context: Context, slot: Int) =
        context.startActivity(intent(context, slot, ACTION_OPEN))

    @JvmStatic fun finish(context: Context, slot: Int) =
        context.startActivity(intent(context, slot, ACTION_FINISH))

    @JvmStatic fun killProcess(context: Context, slot: Int) =
        context.startActivity(intent(context, slot, ACTION_KILL_PROCESS))

    @JvmStatic
    fun activityClass(slot: Int): Class<out Activity> = when (slot) {
        0 -> RuntimeSlot0ProbeActivity::class.java
        1 -> RuntimeSlot1ProbeActivity::class.java
        else -> throw IllegalArgumentException("Unknown runtime slot: $slot")
    }

    private fun intent(context: Context, slot: Int, action: String) =
        Intent(context, activityClass(slot)).setAction(action).addFlags(OPEN_FLAGS)
}

data class RuntimeSlotProbeSnapshot(
    val slot: Int,
    val pid: Int,
    val processName: String,
    val taskId: Int,
    val instanceId: String,
    val lifecycle: String,
    val newIntentCount: Int,
    val updatedAtMillis: Long,
)

object RuntimeSlotProbeStore {
    private const val DIRECTORY = "runtime-slot-probe"

    @JvmStatic
    fun read(context: Context, slot: Int): RuntimeSlotProbeSnapshot? {
        val file = stateFile(context, slot)
        if (!file.isFile) return null
        val properties = Properties()
        return try {
            file.inputStream().use(properties::load)
            RuntimeSlotProbeSnapshot(
                properties.requiredInt("slot"),
                properties.requiredInt("pid"),
                properties.getProperty("processName") ?: return null,
                properties.requiredInt("taskId"),
                properties.getProperty("instanceId") ?: return null,
                properties.getProperty("lifecycle") ?: return null,
                properties.requiredInt("newIntentCount"),
                properties.getProperty("updatedAtMillis")?.toLongOrNull() ?: 0L,
            )
        } catch (_: Exception) {
            null
        }
    }

    @JvmStatic
    fun clear(context: Context) {
        for (slot in 0..1) {
            val file = stateFile(context, slot)
            file.delete()
            File(file.path + ".bak").delete()
            File(file.path + ".new").delete()
        }
    }

    internal fun write(context: Context, snapshot: RuntimeSlotProbeSnapshot) {
        val properties = Properties().apply {
            setProperty("slot", snapshot.slot.toString())
            setProperty("pid", snapshot.pid.toString())
            setProperty("processName", snapshot.processName)
            setProperty("taskId", snapshot.taskId.toString())
            setProperty("instanceId", snapshot.instanceId)
            setProperty("lifecycle", snapshot.lifecycle)
            setProperty("newIntentCount", snapshot.newIntentCount.toString())
            setProperty("updatedAtMillis", snapshot.updatedAtMillis.toString())
        }
        val atomicFile = AtomicFile(stateFile(context, snapshot.slot))
        val output = atomicFile.startWrite()
        try {
            properties.store(output, null)
            atomicFile.finishWrite(output)
        } catch (error: Exception) {
            atomicFile.failWrite(output)
            throw error
        }
    }

    private fun stateFile(context: Context, slot: Int): File {
        val directory = File(context.filesDir, DIRECTORY)
        check(directory.isDirectory || directory.mkdirs()) { "Unable to create probe directory" }
        return File(directory, "slot-$slot.properties")
    }

    private fun Properties.requiredInt(key: String): Int =
        getProperty(key)?.toIntOrNull() ?: throw IllegalStateException("Missing $key")
}

abstract class RuntimeSlotProbeActivity : Activity() {
    protected abstract val slot: Int
    private val instanceId = UUID.randomUUID().toString()
    private var newIntentCount = 0
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        status = TextView(this).apply {
            gravity = Gravity.CENTER
            textSize = 18f
            setPadding(32, 32, 32, 32)
        }
        setContentView(status)
        record("CREATED")
        handleCommand(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        newIntentCount++
        record("NEW_INTENT")
        handleCommand(intent)
    }

    override fun onStart() { super.onStart(); record("STARTED") }
    override fun onResume() { super.onResume(); record("RESUMED") }
    override fun onPause() { record("PAUSED"); super.onPause() }
    override fun onStop() { record("STOPPED"); super.onStop() }
    override fun onDestroy() { record("DESTROYED"); super.onDestroy() }

    private fun handleCommand(intent: Intent?) {
        when (intent?.action) {
            RuntimeSlotProbeLauncher.ACTION_FINISH -> finishAndRemoveTask()
            RuntimeSlotProbeLauncher.ACTION_KILL_PROCESS -> Handler(Looper.getMainLooper()).post {
                Process.killProcess(Process.myPid())
            }
        }
    }

    private fun record(lifecycle: String) {
        val snapshot = RuntimeSlotProbeSnapshot(
            slot, Process.myPid(), currentProcessName(), taskId, instanceId, lifecycle,
            newIntentCount, System.currentTimeMillis(),
        )
        RuntimeSlotProbeStore.write(applicationContext, snapshot)
        if (::status.isInitialized) {
            status.text = "Runtime slot $slot\n${snapshot.processName}\nPID ${snapshot.pid}\nTask ${snapshot.taskId}\n$lifecycle"
        }
    }

    private fun currentProcessName(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) return Application.getProcessName()
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return manager.runningAppProcesses?.firstOrNull { it.pid == Process.myPid() }?.processName
            ?: "unknown"
    }
}

class RuntimeSlot0ProbeActivity : RuntimeSlotProbeActivity() { override val slot = 0 }
class RuntimeSlot1ProbeActivity : RuntimeSlotProbeActivity() { override val slot = 1 }
