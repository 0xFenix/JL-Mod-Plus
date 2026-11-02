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

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.h3nb.jlmodplus.R
import io.github.h3nb.jlmodplus.ui.JLModPlusTheme

/** Host actions for the multi-MIDlet tab strip. Actual tab launching stays in [MicroActivity]. */
interface MidletTabActions {
    /** Opens another tab running the game of the selected tab. */
    fun onAddTab()
    fun onOpenSuitePicker()
    fun onPickSuite(suite: MidletTabSuite)
    fun onSelectTab(tabId: Int)
    fun onCloseTab(tabId: Int)
}

/** Library game offered by the new-tab picker. */
data class MidletTabSuite(val title: String, val appPath: String, val expectedAppId: Long)

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
    private var suitePicker by mutableStateOf<List<MidletTabSuite>?>(null)
    private var closeConfirmId by mutableStateOf<Int?>(null)

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
                    onCloseSelectedTab = { closeConfirmId = selectedId },
                    onAddTab = actions::onAddTab,
                    onOpenSuitePicker = actions::onOpenSuitePicker,
                )
                closeConfirmId?.let { tabId ->
                    CloseTabConfirmDialog(
                        tabNumber = tabs.indexOfFirst { it.id == tabId } + 1,
                        onConfirm = {
                            closeConfirmId = null
                            actions.onCloseTab(tabId)
                        },
                        onDismiss = { closeConfirmId = null },
                    )
                }
                suitePicker?.let { suites ->
                    MidletSuitePickerDialog(
                        suites = suites,
                        onPick = {
                            suitePicker = null
                            actions.onPickSuite(it)
                        },
                        onDismiss = { suitePicker = null },
                    )
                }
            }
        }
        refresh()
    }

    /** Re-reads the registry snapshot into Compose state. */
    fun refresh() {
        tabs = registry.snapshot()
        selectedId = registry.selectedId()
    }

    fun showSuitePicker(suites: List<MidletTabSuite>) {
        suitePicker = suites
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
    onOpenSuitePicker: () -> Unit,
) {
    val addDescription = stringResource(R.string.midlet_tab_add_description)
    val pickDescription = stringResource(R.string.midlet_tab_pick_description)
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        contentColor = MaterialTheme.colorScheme.onSurface,
        tonalElevation = 2.dp,
        modifier = Modifier.fillMaxWidth(),
    ) {
        CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 0.dp) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .horizontalScroll(rememberScrollState())
                        .testTag("midlet_tab_bar"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    tabs.forEachIndexed { index, tab ->
                        val isSelected = tab.id == selectedId
                        Surface(
                            selected = isSelected,
                            onClick = { onSelectTab(tab.id) },
                            shape = MaterialTheme.shapes.small,
                            color = if (isSelected) {
                                MaterialTheme.colorScheme.primaryContainer
                            } else {
                                MaterialTheme.colorScheme.surfaceContainerLow
                            },
                            contentColor = if (isSelected) {
                                MaterialTheme.colorScheme.onPrimaryContainer
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                            modifier = Modifier
                                .defaultMinSize(minWidth = 44.dp, minHeight = 36.dp)
                                .semantics {
                                    role = Role.Tab
                                    selected = isSelected
                                }
                                .testTag("midlet_tab_${tab.id}"),
                        ) {
                            Box(
                                contentAlignment = Alignment.Center,
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp),
                            ) {
                                Text(
                                    text = (index + 1).toString(),
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                                )
                            }
                        }
                    }
                }
                IconButton(
                    onClick = onCloseSelectedTab,
                    enabled = canClose,
                    modifier = Modifier
                        .size(36.dp)
                        .semantics { contentDescription = closeDescription }
                        .testTag("midlet_tab_close"),
                ) {
                    Icon(
                        painter = painterResource(R.drawable.ic_close),
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                    )
                }
                IconButton(
                    onClick = onAddTab,
                    enabled = canAdd,
                    modifier = Modifier
                        .size(36.dp)
                        .semantics { contentDescription = addDescription }
                        .testTag("midlet_tab_add"),
                ) {
                    Icon(
                        painter = painterResource(R.drawable.ic_add),
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                    )
                }
                IconButton(
                    onClick = onOpenSuitePicker,
                    enabled = canAdd,
                    modifier = Modifier
                        .size(36.dp)
                        .semantics { contentDescription = pickDescription }
                        .testTag("midlet_tab_pick"),
                ) {
                    Icon(
                        painter = painterResource(R.drawable.ic_more_vert),
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun CloseTabConfirmDialog(
    tabNumber: Int,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.midlet_tab_close_confirm_title, tabNumber)) },
        text = { Text(stringResource(R.string.midlet_tab_close_confirm_message)) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.midlet_tab_close_confirm_action))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(android.R.string.cancel))
            }
        },
    )
}

@Composable
private fun MidletSuitePickerDialog(
    suites: List<MidletTabSuite>,
    onPick: (MidletTabSuite) -> Unit,
    onDismiss: () -> Unit,
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            tonalElevation = 6.dp,
            modifier = Modifier
                .fillMaxWidth(0.92f)
                .widthIn(max = 480.dp),
        ) {
            Column(modifier = Modifier.padding(vertical = 24.dp)) {
                Text(
                    text = stringResource(R.string.midlet_tab_pick_suite),
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(horizontal = 24.dp),
                )
                Spacer(Modifier.height(16.dp))
                LazyColumn(
                    modifier = Modifier.weight(1f, fill = false),
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(suites, key = { it.appPath }) { suite ->
                        Surface(
                            onClick = { onPick(suite) },
                            shape = MaterialTheme.shapes.large,
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Box(
                                    contentAlignment = Alignment.Center,
                                    modifier = Modifier
                                        .size(40.dp)
                                        .background(
                                            MaterialTheme.colorScheme.primaryContainer,
                                            MaterialTheme.shapes.medium,
                                        ),
                                ) {
                                    Icon(
                                        painter = painterResource(R.drawable.ic_default_midlet),
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                                        modifier = Modifier.size(24.dp),
                                    )
                                }
                                Text(
                                    text = suite.title,
                                    style = MaterialTheme.typography.titleMedium,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp, start = 16.dp, end = 16.dp),
                    horizontalArrangement = Arrangement.End,
                ) {
                    TextButton(onClick = onDismiss) {
                        Text(stringResource(android.R.string.cancel))
                    }
                }
            }
        }
    }
}
