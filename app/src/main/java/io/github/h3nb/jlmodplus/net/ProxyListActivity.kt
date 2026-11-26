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
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
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
    var addMenuOpen by remember { mutableStateOf(false) }
    var addMode by remember { mutableStateOf<AddProxyMode?>(null) }
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
            Column(horizontalAlignment = Alignment.End) {
                DropdownMenu(
                    expanded = addMenuOpen,
                    onDismissRequest = { addMenuOpen = false },
                ) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.proxy_add_one)) },
                        onClick = {
                            addMenuOpen = false
                            addMode = AddProxyMode.One
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.proxy_paste)) },
                        onClick = {
                            addMenuOpen = false
                            addMode = AddProxyMode.Paste
                        },
                    )
                }
                FloatingActionButton(onClick = { addMenuOpen = true }) {
                    Icon(
                        painter = painterResource(R.drawable.ic_add),
                        contentDescription = stringResource(R.string.proxy_add),
                    )
                }
            }
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(bottom = 88.dp),
        ) {
            item(key = "test-all") {
                val alive = probes.values.count { it.alive }
                val dead = probes.size - alive
                val status = when {
                    testing -> stringResource(R.string.proxy_testing)
                    probes.isNotEmpty() -> stringResource(R.string.proxy_test_summary, alive, dead)
                    else -> stringResource(R.string.proxy_test_hint)
                }
                Card(
                    onClick = ::testAll,
                    enabled = !testing && entries.isNotEmpty(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                        contentColor = MaterialTheme.colorScheme.onTertiaryContainer,
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                text = stringResource(R.string.proxy_test_all),
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(text = status, style = MaterialTheme.typography.bodyMedium)
                        }
                        if (testing) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                color = MaterialTheme.colorScheme.onTertiaryContainer,
                                strokeWidth = 2.dp,
                            )
                        } else {
                            Icon(
                                painter = painterResource(R.drawable.ic_refresh),
                                contentDescription = null,
                            )
                        }
                    }
                }
            }
            if (entries.isEmpty()) {
                item(key = "empty") {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 24.dp, vertical = 32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = stringResource(R.string.proxy_empty_title),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Spacer(Modifier.size(8.dp))
                        Text(
                            text = stringResource(R.string.proxy_empty_detail),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
            items(entries, key = { it.id }) { entry ->
                ProxyRow(
                    entry = entry,
                    probe = probes[entry.id],
                    onLongPress = { pendingDelete = entry },
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
            item(key = "plaintext-warning") {
                Text(
                    text = stringResource(R.string.proxy_plaintext_warning),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 16.dp),
                )
            }
        }
    }

    when (addMode) {
        AddProxyMode.One -> AddOneProxyDialog(
            store = store,
            onDismiss = { addMode = null },
            onChanged = ::reload,
        )

        AddProxyMode.Paste -> PasteProxiesDialog(
            store = store,
            onDismiss = { addMode = null },
            onChanged = ::reload,
        )

        null -> Unit
    }

    pendingDelete?.let { entry ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text(stringResource(R.string.proxy_delete_title)) },
            text = {
                Text(stringResource(R.string.proxy_delete_message, "${entry.host}:${entry.port}"))
            },
            confirmButton = {
                TextButton(onClick = {
                    pendingDelete = null
                    store.remove(entry.id)
                    reload()
                }) {
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
    onLongPress: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = {},
                onLongClickLabel = stringResource(R.string.proxy_delete_title),
                onLongClick = onLongPress,
            )
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                text = "${entry.host}:${entry.port}",
                style = MaterialTheme.typography.bodyLarge,
            )
            Text(
                text = if (entry.user.isEmpty()) {
                    stringResource(R.string.proxy_row_no_login)
                } else {
                    stringResource(R.string.proxy_row_user, entry.user)
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (probe != null) {
                Text(
                    text = probe.verdict,
                    style = MaterialTheme.typography.labelMedium,
                    color = if (probe.alive) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.error
                    },
                )
            }
        }
    }
}

@Composable
private fun AddOneProxyDialog(
    store: ProxyStore,
    onDismiss: () -> Unit,
    onChanged: () -> Unit,
) {
    var host by remember { mutableStateOf("") }
    var port by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.proxy_add_one)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = host,
                    onValueChange = { host = it },
                    label = { Text(stringResource(R.string.proxy_field_address)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                )
                OutlinedTextField(
                    value = port,
                    onValueChange = { port = it.filter(Char::isDigit) },
                    label = { Text(stringResource(R.string.proxy_field_port)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                OutlinedTextField(
                    value = user,
                    onValueChange = { user = it },
                    label = { Text(stringResource(R.string.proxy_field_username)) },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = pass,
                    onValueChange = { pass = it },
                    label = { Text(stringResource(R.string.proxy_field_password)) },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                )
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
            TextButton(onClick = {
                // Port 0 lets ProxyStore report its own range error for missing or invalid input.
                val addError = store.add(host.trim(), port.toIntOrNull() ?: 0, user.trim(), pass)
                if (addError == null) {
                    onChanged()
                    onDismiss()
                } else {
                    error = addError
                }
            }) {
                Text(stringResource(R.string.proxy_add_action))
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
private fun PasteProxiesDialog(
    store: ProxyStore,
    onDismiss: () -> Unit,
    onChanged: () -> Unit,
) {
    var text by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.proxy_paste)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
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
            TextButton(onClick = {
                val result = store.importText(text)
                if (result.added > 0) onChanged()
                if (result.error != null) {
                    error = result.error
                } else if (result.added > 0) {
                    onDismiss()
                }
            }) {
                Text(stringResource(R.string.proxy_import_action))
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
