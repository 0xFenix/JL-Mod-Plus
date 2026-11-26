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

import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.h3nb.jlmodplus.R
import io.github.h3nb.jlmodplus.ui.JLModPlusTheme

/** Host actions for the multi-MIDlet window switcher. Actual tab launching stays in [MicroActivity]. */
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
 * Interop owner for the card-grid window switcher. The runtime toolbar owns the
 * entry point; this ComposeView only hosts the switcher dialogs. Rendering follows the app Material 3 theme;
 * tab bookkeeping lives in [AmsRegistry] and preview bitmaps stay here so
 * [MicroActivity] only has to supply the capture callback.
 */
class MidletTabBarController(
    private val composeView: ComposeView,
    private val registry: AmsRegistry,
    private val actions: MidletTabActions,
    private val capturePreview: (() -> Bitmap?)?,
    private val appTitle: String?,
) {
    private var tabs by mutableStateOf(listOf<AmsRegistry.Tab>())
    private var selectedId by mutableIntStateOf(-1)
    private var suitePicker by mutableStateOf<List<MidletTabSuite>?>(null)
    private var closeConfirmId by mutableStateOf<Int?>(null)
    private var gridOpen by mutableStateOf(false)
    /** Compose-visible copy of [previews]; cleared when the grid closes. */
    private var gridPreviews by mutableStateOf<Map<Int, Bitmap>>(emptyMap())
    private val previews = HashMap<Int, Bitmap>()

    init {
        composeView.setViewCompositionStrategy(
            ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed,
        )
        composeView.setContent {
            JLModPlusTheme {
                if (gridOpen) {
                    MidletWindowGrid(
                        tabs = tabs,
                        selectedId = selectedId,
                        previews = gridPreviews,
                        fallbackTitle = appTitle,
                        onDismiss = ::dismissGrid,
                        onSelectTab = ::selectFromGrid,
                        onCloseTab = { closeConfirmId = it },
                        onAddTab = {
                            dismissGrid()
                            actions.onAddTab()
                        },
                        onOpenSuitePicker = {
                            dismissGrid()
                            actions.onOpenSuitePicker()
                        },
                    )
                }
                closeConfirmId?.let { tabId ->
                    CloseTabConfirmDialog(
                        tabNumber = tabs.indexOfFirst { it.id == tabId } + 1,
                        onConfirm = {
                            closeConfirmId = null
                            dismissGrid()
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
        prunePreviews()
    }

    fun showSuitePicker(suites: List<MidletTabSuite>) {
        suitePicker = suites
    }

    /** Opens the switcher; called from the runtime toolbar. */
    fun openGrid() {
        captureSelectedPreview()
        prunePreviews()
        gridPreviews = HashMap(previews)
        gridOpen = true
    }

    private fun dismissGrid() {
        if (!gridOpen) return
        gridOpen = false
        gridPreviews = emptyMap()
        prunePreviews()
    }

    /** Drops cached previews; they are recaptured the next time the switcher opens. */
    fun clearPreviews() {
        // The grid draws these bitmaps; recycling them mid-draw would crash the sheet.
        if (gridOpen) return
        previews.values.forEach { it.recycle() }
        previews.clear()
        gridPreviews = emptyMap()
    }

    private fun selectFromGrid(tabId: Int) {
        // The outgoing guest is still mounted here, so this is the last frame
        // that can be captured for its card.
        captureSelectedPreview()
        dismissGrid()
        actions.onSelectTab(tabId)
    }

    private fun captureSelectedPreview() {
        val capture = capturePreview ?: return
        if (selectedId < 0) return
        val bitmap = capture() ?: return
        val previous = previews.put(selectedId, bitmap)
        // A replaced preview is still composed while the grid is open; leave it to GC there.
        if (previous != null && !gridOpen) {
            previous.recycle()
        }
    }

    /** Drops previews of tabs that no longer exist. Skipped while the grid draws them. */
    private fun prunePreviews() {
        if (gridOpen) return
        val live = HashSet<Int>(tabs.size)
        for (tab in tabs) {
            live.add(tab.id)
        }
        val iterator = previews.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (!live.contains(entry.key)) {
                iterator.remove()
                entry.value.recycle()
            }
        }
    }
}

@Composable
private fun MidletWindowGrid(
    tabs: List<AmsRegistry.Tab>,
    selectedId: Int,
    previews: Map<Int, Bitmap>,
    fallbackTitle: String?,
    onDismiss: () -> Unit,
    onSelectTab: (Int) -> Unit,
    onCloseTab: (Int) -> Unit,
    onAddTab: () -> Unit,
    onOpenSuitePicker: () -> Unit,
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
        ),
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surface,
            modifier = Modifier.fillMaxSize(),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .windowInsetsPadding(WindowInsets.safeDrawing),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 20.dp, end = 8.dp, top = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = stringResource(R.string.midlet_tab_windows),
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(
                        onClick = onOpenSuitePicker,
                        modifier = Modifier.testTag("midlet_tab_pick"),
                    ) {
                        Icon(
                            painter = painterResource(R.drawable.ic_apps),
                            contentDescription = stringResource(R.string.midlet_tab_pick_description),
                            modifier = Modifier.size(20.dp),
                        )
                    }
                    TextButton(onClick = onDismiss) {
                        Text(stringResource(R.string.midlet_tab_windows_done))
                    }
                }
                BoxWithConstraints(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                ) {
                    val spacing = 12.dp
                    // Two rows exactly fill the viewport; the fifth card scrolls.
                    val cardHeight = ((maxHeight - spacing * 3) / 2).coerceAtLeast(120.dp)
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(2),
                        contentPadding = PaddingValues(spacing),
                        horizontalArrangement = Arrangement.spacedBy(spacing),
                        verticalArrangement = Arrangement.spacedBy(spacing),
                        modifier = Modifier
                            .fillMaxSize()
                            .testTag("midlet_tab_grid"),
                    ) {
                        items(tabs, key = { it.id }) { tab ->
                            val index = tabs.indexOfFirst { it.id == tab.id }
                            WindowCard(
                                tab = tab,
                                title = tab.title ?: fallbackTitle ?: tab.label,
                                preview = previews[tab.id],
                                selected = tab.id == selectedId,
                                canClose = tabs.size > 1,
                                closeDescription = stringResource(
                                    R.string.midlet_tab_close_description, index + 1),
                                cardHeight = cardHeight,
                                onSelect = { onSelectTab(tab.id) },
                                onClose = { onCloseTab(tab.id) },
                            )
                        }
                        item(key = "add") {
                            AddWindowCard(
                                cardHeight = cardHeight,
                                onAdd = onAddTab,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WindowCard(
    tab: AmsRegistry.Tab,
    title: String,
    preview: Bitmap?,
    selected: Boolean,
    canClose: Boolean,
    closeDescription: String,
    cardHeight: Dp,
    onSelect: () -> Unit,
    onClose: () -> Unit,
) {
    Surface(
        selected = selected,
        onClick = onSelect,
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        contentColor = MaterialTheme.colorScheme.onSurface,
        border = if (selected) {
            BorderStroke(2.dp, MaterialTheme.colorScheme.primary)
        } else {
            null
        },
        modifier = Modifier
            .fillMaxWidth()
            .height(cardHeight)
            .testTag("midlet_tab_card_${tab.id}"),
    ) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxWidth().weight(1f)) {
                if (preview != null) {
                    Image(
                        bitmap = preview.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .fillMaxSize()
                            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
                    ) {
                        Text(
                            text = title,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(12.dp),
                        )
                    }
                }
            }
            // The close affordance shares the caption band with the title: over the preview it
            // needed a scrim circle that read as a smudge on bright screenshots.
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 12.dp, end = 4.dp),
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .weight(1f)
                        .padding(vertical = 8.dp),
                )
                if (canClose) {
                    IconButton(
                        onClick = onClose,
                        modifier = Modifier
                            .size(40.dp)
                            .semantics { contentDescription = closeDescription }
                            .testTag("midlet_tab_close"),
                    ) {
                        Icon(
                            painter = painterResource(R.drawable.ic_close),
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AddWindowCard(
    cardHeight: Dp,
    onAdd: () -> Unit,
) {
    Surface(
        onClick = onAdd,
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .height(cardHeight)
            .testTag("midlet_tab_add"),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                painter = painterResource(R.drawable.ic_add),
                contentDescription = stringResource(R.string.midlet_tab_add_description),
                modifier = Modifier.size(36.dp),
            )
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
