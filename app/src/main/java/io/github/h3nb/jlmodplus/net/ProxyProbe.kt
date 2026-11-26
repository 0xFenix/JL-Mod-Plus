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

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

/**
 * Probes [entries] with at most [concurrency] sockets in flight and reports each
 * verdict as it lands. [onResult] runs on the caller's coroutine context.
 */
internal suspend fun probeProxies(
    entries: List<ProxyStore.Entry>,
    concurrency: Int,
    probe: (ProxyStore.Entry) -> ProxyStore.TestResult,
    onResult: (id: String, result: ProxyStore.TestResult) -> Unit,
) {
    require(concurrency > 0)
    coroutineScope {
        val permits = Semaphore(concurrency)
        for (entry in entries) {
            launch {
                val result = withContext(Dispatchers.IO) { permits.withPermit { probe(entry) } }
                onResult(entry.id, result)
            }
        }
    }
}
