// SPDX-License-Identifier: Apache-2.0
package io.github.h3nb.jlmodplus.runtime.slots

import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.github.h3nb.jlmodplus.runtime.slots.debug.RuntimeSlotProbeLauncher
import io.github.h3nb.jlmodplus.runtime.slots.debug.RuntimeSlotProbeSnapshot
import io.github.h3nb.jlmodplus.runtime.slots.debug.RuntimeSlotProbeStore
import java.io.IOException
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RuntimeSlotActivityExperimentTest {
    private val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before fun setUp() { finishProbeTasks(); RuntimeSlotProbeStore.clear(context) }
    @After fun tearDown() { finishProbeTasks() }

    @Test
    fun manifestDeclaresFixedPrivateProcessesAndTaskContracts() {
        for (slot in 0..1) {
            val info = context.packageManager.getActivityInfo(
                ComponentName(context, RuntimeSlotProbeLauncher.activityClass(slot)), 0,
            )
            assertEquals(context.packageName + ":midlet$slot", info.processName)
            assertEquals(context.packageName + ".runtime.slot$slot", info.taskAffinity)
            assertEquals(ActivityInfo.LAUNCH_SINGLE_TASK, info.launchMode)
            assertFalse(info.exported)
        }
        assertEquals(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            RuntimeSlotProbeLauncher.OPEN_FLAGS,
        )
    }

    @Test
    fun twoSlotsCoexistInDifferentProcessesAndOpenFocusReusesEachTask() {
        RuntimeSlotProbeLauncher.open(context, 0)
        val firstA = awaitLifecycle(0, "RESUMED")
        RuntimeSlotProbeLauncher.open(context, 1)
        val firstB = awaitLifecycle(1, "RESUMED")
        assertNotEquals(firstA.pid, firstB.pid)
        assertNotEquals(firstA.processName, firstB.processName)
        assertNotEquals(firstA.taskId, firstB.taskId)
        assertTrue(processIsRunning(firstA.processName, firstA.pid))
        assertTrue(processIsRunning(firstB.processName, firstB.pid))

        RuntimeSlotProbeLauncher.open(context, 0)
        val focusedA = awaitNewIntent(0, firstA.newIntentCount + 1)
        assertEquals(firstA.pid, focusedA.pid)
        assertEquals(firstA.taskId, focusedA.taskId)
        assertEquals(firstA.instanceId, focusedA.instanceId)
        awaitLifecycle(0, "RESUMED")

        RuntimeSlotProbeLauncher.open(context, 1)
        val focusedB = awaitNewIntent(1, firstB.newIntentCount + 1)
        assertEquals(firstB.pid, focusedB.pid)
        assertEquals(firstB.taskId, focusedB.taskId)
        assertEquals(firstB.instanceId, focusedB.instanceId)
        awaitLifecycle(1, "RESUMED")
    }

    @Test
    fun homeReturnAndClosingOneTaskLeaveTheOtherSlotAlive() {
        RuntimeSlotProbeLauncher.open(context, 0)
        val firstA = awaitLifecycle(0, "RESUMED")
        RuntimeSlotProbeLauncher.open(context, 1)
        val firstB = awaitLifecycle(1, "RESUMED")
        sendHome()
        awaitLifecycle(1, "STOPPED")

        RuntimeSlotProbeLauncher.open(context, 0)
        val returnedA = awaitNewIntent(0, firstA.newIntentCount + 1)
        assertEquals(firstA.pid, returnedA.pid)
        assertEquals(firstA.taskId, returnedA.taskId)
        assertEquals(firstA.instanceId, returnedA.instanceId)
        awaitLifecycle(0, "RESUMED")

        RuntimeSlotProbeLauncher.finish(context, 0)
        awaitLifecycle(0, "DESTROYED")
        assertTrue(processIsRunning(firstB.processName, firstB.pid))
        assertTrue(taskExists(firstB.taskId))
        assertFalse(taskExists(firstA.taskId))
    }

    @Test
    fun killingOneSlotProcessDoesNotKillTheOtherAndRelaunchGetsNewPid() {
        RuntimeSlotProbeLauncher.open(context, 0)
        val firstA = awaitLifecycle(0, "RESUMED")
        RuntimeSlotProbeLauncher.open(context, 1)
        val firstB = awaitLifecycle(1, "RESUMED")
        RuntimeSlotProbeLauncher.killProcess(context, 0)
        awaitProcessGone(firstA.processName, firstA.pid)
        assertTrue(processIsRunning(firstB.processName, firstB.pid))

        RuntimeSlotProbeLauncher.open(context, 0)
        val restartedA = awaitSnapshot(0) { it.lifecycle == "RESUMED" && it.pid != firstA.pid }
        assertNotEquals(firstA.pid, restartedA.pid)
        assertNotEquals(firstA.instanceId, restartedA.instanceId)
        assertEquals(firstB.pid, currentPid(firstB.processName))
    }

    private fun awaitLifecycle(slot: Int, lifecycle: String) =
        awaitSnapshot(slot) { it.lifecycle == lifecycle }

    private fun awaitNewIntent(slot: Int, minimumCount: Int) =
        awaitSnapshot(slot) { it.newIntentCount >= minimumCount }

    private fun awaitSnapshot(slot: Int, predicate: (RuntimeSlotProbeSnapshot) -> Boolean): RuntimeSlotProbeSnapshot {
        val deadline = SystemClock.uptimeMillis() + TIMEOUT_MILLIS
        do {
            RuntimeSlotProbeStore.read(context, slot)?.let { if (predicate(it)) return it }
            SystemClock.sleep(100L)
        } while (SystemClock.uptimeMillis() < deadline)
        throw AssertionError("Runtime slot $slot did not reach the expected state")
    }

    private fun awaitProcessGone(processName: String, pid: Int) {
        val deadline = SystemClock.uptimeMillis() + TIMEOUT_MILLIS
        do {
            if (!processIsRunning(processName, pid)) return
            SystemClock.sleep(100L)
        } while (SystemClock.uptimeMillis() < deadline)
        throw AssertionError("Process $processName/$pid is still running")
    }

    private fun processIsRunning(processName: String, pid: Int) = currentPid(processName) == pid

    private fun currentPid(processName: String): Int {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return manager.runningAppProcesses?.firstOrNull { it.processName == processName }?.pid ?: 0
    }

    private fun taskExists(taskId: Int): Boolean {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return manager.appTasks.any { it.taskInfo?.taskId == taskId }
    }

    private fun finishProbeTasks() {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val components = (0..1).map {
            ComponentName(context, RuntimeSlotProbeLauncher.activityClass(it))
        }.toSet()
        manager.appTasks.forEach { task ->
            val info = task.taskInfo ?: return@forEach
            if (info.baseActivity in components || info.topActivity in components) task.finishAndRemoveTask()
        }
        SystemClock.sleep(250L)
    }

    @Throws(IOException::class)
    private fun sendHome() {
        val result = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(
            "am start -W -a android.intent.action.MAIN -c android.intent.category.HOME",
        )
        ParcelFileDescriptor.AutoCloseInputStream(result).use { input ->
            val buffer = ByteArray(1024)
            while (input.read(buffer) != -1) Unit
        }
    }

    companion object { private const val TIMEOUT_MILLIS = 10_000L }
}
