/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package io.github.h3nb.jlmodplus.net

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

class ProxyProbeTest {

    @Test
    fun probesEveryEntryWithinConcurrencyLimit() = runBlocking {
        val entries = (1..10).map { ProxyStore.Entry("host$it", 1000 + it, "user$it", "") }
        val inFlight = AtomicInteger()
        val maxInFlight = AtomicInteger()
        val results = ConcurrentHashMap<String, ProxyStore.TestResult>()

        probeProxies(
            entries = entries,
            concurrency = 4,
            probe = { entry ->
                maxInFlight.accumulateAndGet(inFlight.incrementAndGet()) { current, next -> maxOf(current, next) }
                try {
                    Thread.sleep(10)
                    val alive = entry.port % 2 == 0
                    ProxyStore.TestResult(alive, if (alive) "Alive" else "Unreachable")
                } finally {
                    inFlight.decrementAndGet()
                }
            },
            onResult = { id, result -> results[id] = result },
        )

        assertEquals(entries.map { it.id }.toSet(), results.keys)
        assertTrue(maxInFlight.get() <= 4, "in-flight probes must stay within the limit")
        assertTrue(results.getValue("host2:1002:user2").alive)
        assertFalse(results.getValue("host1:1001:user1").alive)
    }
}
