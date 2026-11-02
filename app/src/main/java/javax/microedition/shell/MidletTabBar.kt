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

package javax.microedition.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.h3nb.jlmodplus.R
import io.github.h3nb.jlmodplus.ui.JLModPlusTheme

/** Host actions for the multi-MIDlet tab strip. Actual tab launching stays in [MicroActivity]. */
interface MidletTabActions {
    fun onAddTab()
    fun onSelectTab(tabId: Int)
    fun onCloseTab(tabId: Int)
}

/**
 * Interop owner for the always-visible multi-MIDlet tab strip below the runtime
 * toolbar. Rendering follows the app Material 3 theme; tab bookkeeping lives in
 * [AmsRegistry] so the policy stays unit-testable without Android.
 */
class MidletTabBarController(
    private val composeView: ComposeView,
    private val registry: AmsRegistry,
    private val actions: MidletTabActions,
) {
    private var tabs by mutableStateOf(listOf<AmsRegistry.Tab>())
    private var selectedId by mutableIntStateOf(-1)

    init {
        composeView.setViewCompositionStrategy(
            ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed,
        )
        composeView.setContent {
            JLModPlusTheme {
                val selectedIndex = tabs.indexOfFirst { it.id == selectedId }
                    .takeIf { it >= 0 } ?: 0
                MidletTabBar(
                    tabs = tabs,
                    selectedId = selectedId,
                    canAdd = tabs.size < AmsRegistry.MAX_TABS,
                    canClose = tabs.size > 1,
                    closeDescription = composeView.context.getString(
                        R.string.midlet_tab_close_description, selectedIndex + 1),
                    onSelectTab = actions::onSelectTab,
                    onCloseSelectedTab = { actions.onCloseTab(selectedId) },
                    onAddTab = actions::onAddTab,
                )
            }
        }
        refresh()
    }

    /** Re-reads the registry snapshot into Compose state. */
    fun refresh() {
        tabs = registry.snapshot()
        selectedId = registry.selectedId()
    }
}

@Composable
private fun MidletTabBar(
    tabs: List<AmsRegistry.Tab>,
    selectedId: Int,
    canAdd: Boolean,
    canClose: Boolean,
    closeDescription: String,
    onSelectTab: (Int) -> Unit,
    onCloseSelectedTab: () -> Unit,
    onAddTab: () -> Unit,
) {
    val selectedIndex = tabs.indexOfFirst { it.id == selectedId }.takeIf { it >= 0 } ?: 0
    Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(modifier = Modifier.weight(1f)) {
                ScrollableTabRow(
                    selectedTabIndex = selectedIndex,
                    edgePadding = 0.dp,
                    modifier = Modifier.testTag("midlet_tab_bar"),
                ) {
                    tabs.forEachIndexed { index, tab ->
                        Tab(
                            selected = tab.id == selectedId,
                            onClick = { onSelectTab(tab.id) },
                            modifier = Modifier.testTag("midlet_tab_${tab.id}"),
                            text = { Text(text = (index + 1).toString()) },
                        )
                    }
                }
            }
            TextButton(
                onClick = onCloseSelectedTab,
                enabled = canClose,
                modifier = Modifier
                    .semantics { contentDescription = closeDescription }
                    .testTag("midlet_tab_close"),
            ) {
                Text(text = stringResource(R.string.midlet_tab_remove))
            }
            TextButton(
                onClick = onAddTab,
                enabled = canAdd,
                modifier = Modifier.testTag("midlet_tab_add"),
            ) {
                Text(text = stringResource(R.string.midlet_tab_add))
            }
        }
    }
}
