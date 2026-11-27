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

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.h3nb.jlmodplus.R
import io.github.h3nb.jlmodplus.ui.AdaptiveAlertDialog as AlertDialog
import io.github.h3nb.jlmodplus.ui.AppPageTransitions
import io.github.h3nb.jlmodplus.ui.JLModPlusTheme
import io.github.h3nb.jlmodplus.util.EdgeToEdgeCompat
import kotlinx.coroutines.launch

/** Saved SOCKS5 proxies and their liveness; assignments stay in [ProxyStore]. */
class ProxyListActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppPageTransitions.install(this)
        EdgeToEdgeCompat.enableForComposeSurface(this)
        val view = ComposeView(this)
        view.setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
        view.setContent {
            JLModPlusTheme {
                ProxyListScreen(onBack = ::finish)
            }
        }
        setContentView(view)
    }
}

private enum class AddProxyMode { One, Paste }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProxyListScreen(onBack: () -> Unit) {
    val store = remember { ProxyStore.forApp() }
    val scope = rememberCoroutineScope()
    var entries by remember { mutableStateOf(store.list()) }
    var probes by remember { mutableStateOf(emptyMap<String, ProxyStore.TestResult>()) }
    var testing by remember { mutableStateOf(false) }
    var addDialogOpen by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<ProxyStore.Entry?>(null) }

    fun reload() {
        entries = store.list()
        val retainedIds = entries.mapTo(HashSet()) { it.id }
        probes = probes.filterKeys { it in retainedIds }
    }

    fun testAll() {
        if (testing) return
        val targets = entries
        probes = emptyMap()
        testing = true
        scope.launch {
            try {
                probeProxies(targets, PROBE_CONCURRENCY, probe = store::test) { id, result ->
                    probes = probes + (id to result)
                }
            } finally {
                testing = false
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.proxy_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            painter = painterResource(R.drawable.ic_arrow_back),
                            contentDescription = stringResource(R.string.action_back),
                        )
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { addDialogOpen = true }) {
                Icon(
                    painter = painterResource(R.drawable.ic_add),
                    contentDescription = stringResource(R.string.proxy_add),
                )
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            LazyColumn(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .widthIn(max = 720.dp),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 88.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (entries.isNotEmpty()) {
                    item(key = "test-all") {
                        val alive = probes.values.count { it.alive }
                        val dead = probes.size - alive
                        val status = when {
                            testing -> stringResource(R.string.proxy_testing)
                            probes.isNotEmpty() -> stringResource(R.string.proxy_test_summary, alive, dead)
                            else -> stringResource(R.string.proxy_test_hint)
                        }
                        Surface(
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            shape = MaterialTheme.shapes.large,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 14.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Column(
                                    modifier = Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(2.dp),
                                ) {
                                    Text(
                                        text = stringResource(R.string.proxy_saved_count, entries.size),
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                    Text(
                                        text = status,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                FilledTonalButton(
                                    onClick = ::testAll,
                                    enabled = !testing,
                                ) {
                                    if (testing) {
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(16.dp),
                                            strokeWidth = 2.dp,
                                        )
                                    } else {
                                        Icon(
                                            painter = painterResource(R.drawable.ic_refresh),
                                            contentDescription = null,
                                            modifier = Modifier.size(18.dp),
                                        )
                                    }
                                    Spacer(Modifier.size(6.dp))
                                    Text(stringResource(R.string.proxy_test_all))
                                }
                            }
                        }
                    }
                }
                if (entries.isEmpty()) {
                    item(key = "empty") {
                        Surface(
                            color = MaterialTheme.colorScheme.surfaceContainerLow,
                            shape = MaterialTheme.shapes.extraLarge,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 12.dp),
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 24.dp, vertical = 28.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Box(
                                    contentAlignment = Alignment.Center,
                                    modifier = Modifier
                                        .size(48.dp)
                                        .background(
                                            MaterialTheme.colorScheme.primaryContainer,
                                            MaterialTheme.shapes.large,
                                        ),
                                ) {
                                    Icon(
                                        painter = painterResource(R.drawable.ic_swap_horiz),
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                                        modifier = Modifier.size(24.dp),
                                    )
                                }
                                Text(
                                    text = stringResource(R.string.proxy_empty_title),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(
                                    text = stringResource(R.string.proxy_empty_detail),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    textAlign = TextAlign.Center,
                                )
                                Button(
                                    onClick = { addDialogOpen = true },
                                    modifier = Modifier.padding(top = 4.dp),
                                ) {
                                    Icon(
                                        painter = painterResource(R.drawable.ic_add),
                                        contentDescription = null,
                                        modifier = Modifier.size(18.dp),
                                    )
                                    Spacer(Modifier.size(6.dp))
                                    Text(stringResource(R.string.proxy_add))
                                }
                            }
                        }
                    }
                }
                items(entries, key = { it.id }) { entry ->
                    ProxyRow(
                        entry = entry,
                        probe = probes[entry.id],
                        onDelete = { pendingDelete = entry },
                    )
                }
                item(key = "plaintext-warning") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 4.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            painter = painterResource(R.drawable.ic_info),
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(16.dp),
                        )
                        Text(
                            text = stringResource(R.string.proxy_plaintext_warning),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }

    if (addDialogOpen) {
        AddProxyDialog(
            store = store,
            onDismiss = { addDialogOpen = false },
            onChanged = ::reload,
        )
    }

    pendingDelete?.let { entry ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            icon = {
                Icon(
                    painter = painterResource(R.drawable.ic_delete),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error,
                )
            },
            title = { Text(stringResource(R.string.proxy_delete_title)) },
            text = {
                Text(stringResource(R.string.proxy_delete_message, "${entry.host}:${entry.port}"))
            },
            confirmButton = {
                Button(
                    onClick = {
                        pendingDelete = null
                        store.remove(entry.id)
                        reload()
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    ),
                ) {
                    Text(stringResource(R.string.action_context_delete))
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) {
                    Text(stringResource(android.R.string.cancel))
                }
            },
        )
    }
}

@Composable
private fun ProxyRow(
    entry: ProxyStore.Entry,
    probe: ProxyStore.TestResult?,
    onDelete: () -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    val badgeColor = when {
        probe == null -> colors.surfaceContainerHigh
        probe.alive -> colors.primaryContainer
        else -> colors.errorContainer
    }
    val badgeContentColor = when {
        probe == null -> colors.onSurfaceVariant
        probe.alive -> colors.onPrimaryContainer
        else -> colors.onErrorContainer
    }
    val badgeIcon = when {
        probe == null -> R.drawable.ic_swap_horiz
        probe.alive -> R.drawable.ic_check_circle
        else -> R.drawable.ic_warning
    }
    Surface(
        color = colors.surfaceContainerLow,
        shape = MaterialTheme.shapes.large,
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = {},
                onLongClickLabel = stringResource(R.string.proxy_delete_title),
                onLongClick = onDelete,
            ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 12.dp, end = 6.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(36.dp)
                    .background(badgeColor, MaterialTheme.shapes.medium),
            ) {
                Icon(
                    painter = painterResource(badgeIcon),
                    contentDescription = null,
                    tint = badgeContentColor,
                    modifier = Modifier.size(20.dp),
                )
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = "${entry.host}:${entry.port}",
                    style = MaterialTheme.typography.bodyLarge.copy(
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.SemiBold,
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = if (entry.user.isEmpty()) {
                        stringResource(R.string.proxy_row_no_login)
                    } else {
                        stringResource(R.string.proxy_row_user, entry.user)
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (probe != null) {
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = if (probe.alive) colors.primaryContainer else colors.errorContainer,
                        contentColor = if (probe.alive) colors.onPrimaryContainer else colors.onErrorContainer,
                        modifier = Modifier.padding(top = 2.dp),
                    ) {
                        Text(
                            text = probe.verdict,
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Medium,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        )
                    }
                }
            }
            IconButton(onClick = onDelete) {
                Icon(
                    painter = painterResource(R.drawable.ic_delete),
                    contentDescription = stringResource(R.string.action_context_delete),
                    tint = colors.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

@Composable
private fun AddProxyDialog(
    store: ProxyStore,
    onDismiss: () -> Unit,
    onChanged: () -> Unit,
) {
    var mode by remember { mutableStateOf(AddProxyMode.One) }
    var host by remember { mutableStateOf("") }
    var port by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var pasteText by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.proxy_add)) },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .selectableGroup(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    listOf(
                        AddProxyMode.One to R.string.proxy_add_one,
                        AddProxyMode.Paste to R.string.proxy_paste,
                    ).forEach { (itemMode, labelRes) ->
                        val selected = mode == itemMode
                        Surface(
                            modifier = Modifier
                                .weight(1f)
                                .heightIn(min = 40.dp)
                                .selectable(
                                    selected = selected,
                                    role = Role.Tab,
                                    onClick = {
                                        mode = itemMode
                                        error = null
                                    },
                                ),
                            shape = MaterialTheme.shapes.medium,
                            color = if (selected) {
                                MaterialTheme.colorScheme.primaryContainer
                            } else {
                                MaterialTheme.colorScheme.surfaceContainerLow
                            },
                            contentColor = if (selected) {
                                MaterialTheme.colorScheme.onPrimaryContainer
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        ) {
                            Box(
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    text = stringResource(labelRes),
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                }
                when (mode) {
                    AddProxyMode.One -> {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            OutlinedTextField(
                                value = host,
                                onValueChange = { host = it },
                                label = { Text(stringResource(R.string.proxy_field_address)) },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                                modifier = Modifier.weight(1.7f),
                            )
                            OutlinedTextField(
                                value = port,
                                onValueChange = { port = it.filter(Char::isDigit) },
                                label = { Text(stringResource(R.string.proxy_field_port)) },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                modifier = Modifier.weight(1f),
                            )
                        }
                        OutlinedTextField(
                            value = user,
                            onValueChange = { user = it },
                            label = { Text(stringResource(R.string.proxy_field_username)) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        OutlinedTextField(
                            value = pass,
                            onValueChange = { pass = it },
                            label = { Text(stringResource(R.string.proxy_field_password)) },
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    AddProxyMode.Paste -> {
                        OutlinedTextField(
                            value = pasteText,
                            onValueChange = { pasteText = it },
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 140.dp),
                            textStyle = MaterialTheme.typography.bodyMedium.copy(
                                fontFamily = FontFamily.Monospace,
                            ),
                            placeholder = { Text(stringResource(R.string.proxy_paste_placeholder)) },
                            minLines = 5,
                            supportingText = { Text(stringResource(R.string.proxy_paste_helper)) },
                        )
                    }
                }
                error?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        confirmButton = {
            Button(onClick = {
                when (mode) {
                    AddProxyMode.One -> {
                        // Port 0 lets ProxyStore report its own range error for missing or invalid input.
                        val addError = store.add(host.trim(), port.toIntOrNull() ?: 0, user.trim(), pass)
                        if (addError == null) {
                            onChanged()
                            onDismiss()
                        } else {
                            error = addError
                        }
                    }
                    AddProxyMode.Paste -> {
                        val result = store.importText(pasteText)
                        if (result.added > 0) onChanged()
                        if (result.error != null) {
                            error = result.error
                        } else if (result.added > 0) {
                            onDismiss()
                        }
                    }
                }
            }) {
                Text(
                    stringResource(
                        if (mode == AddProxyMode.One) R.string.proxy_add_action
                        else R.string.proxy_import_action,
                    ),
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(android.R.string.cancel))
            }
        },
    )
}

private const val PROBE_CONCURRENCY = 4
