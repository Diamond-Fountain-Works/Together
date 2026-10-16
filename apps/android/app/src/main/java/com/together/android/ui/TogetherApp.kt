package com.together.android.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.together.android.R
import com.together.android.data.TogetherRepository
import com.together.domain.*
import com.together.protocol.*
import kotlinx.coroutines.*

@Composable private fun TogetherTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val colors = if (dark) darkColorScheme(primary = Color(0xFFE6A1B1), onPrimary = Color(0xFF451F2B), secondary = Color(0xFFD1A4B0), secondaryContainer = Color(0xFF51343D), onSecondaryContainer = Color(0xFFFFDBE5), background = Color(0xFF1B181A), surface = Color(0xFF242024), surfaceContainerLow = Color(0xFF241F22), surfaceContainer = Color(0xFF2A2428), surfaceContainerHigh = Color(0xFF342B30), surfaceContainerHighest = Color(0xFF3E343B))
        else lightColorScheme(primary = Color(0xFFAD4F65), secondary = Color(0xFF855562), secondaryContainer = Color(0xFFF3DFE3), onSecondaryContainer = Color(0xFF44232C), background = Color(0xFFFBF7F0), surface = Color(0xFFFFFBF6), surfaceContainerLow = Color(0xFFFFF9F4), surfaceContainer = Color(0xFFF6EFE8), surfaceContainerHigh = Color(0xFFF0E8E0), surfaceContainerHighest = Color(0xFFE9E0DC))
    MaterialTheme(colorScheme = colors, shapes = Shapes(medium = RoundedCornerShape(16.dp), small = RoundedCornerShape(12.dp)), content = content)
}
private enum class Page(val label: Int) { Home(R.string.nav_home), Plans(R.string.nav_plans), Connection(R.string.nav_connection), Settings(R.string.nav_settings) }
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun TogetherApp(repository: TogetherRepository) = TogetherTheme {
    val state by repository.state.collectAsStateWithLifecycle(); var page by rememberSaveable { mutableStateOf(Page.Home) }
    var editor by remember { mutableStateOf<ProjectedEntity?>(null) }; var editing by rememberSaveable { mutableStateOf(false) }
    var history by rememberSaveable { mutableStateOf(false) }; var enrolling by rememberSaveable { mutableStateOf(false) }
    var localError by remember { mutableStateOf<String?>(null) }; val scope = rememberCoroutineScope()
    fun perform(block: suspend () -> Unit) { scope.launch { try { block() } catch (e: Exception) { if (e is CancellationException) throw e; localError = (e as? ProtocolException)?.code ?: "LOCAL_OPERATION_FAILED" } } }
    val error = localError ?: state.error
    Surface(color = MaterialTheme.colorScheme.background) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val wide = maxWidth >= 600.dp
            Scaffold(topBar = { TopAppBar(title = { Text(if (page == Page.Home) stringResource(R.string.app_name) else stringResource(page.label)) },
                actions = { if (page == Page.Plans) IconButton(onClick = { editor = null; editing = true }, enabled = state.canWrite, modifier = Modifier.testTag("task.new")) { Icon(Icons.Outlined.Add, stringResource(R.string.action_new_task)) } }) },
                bottomBar = { if (!wide) NavigationBar { Page.entries.forEach { p -> NavigationBarItem(selected = page == p, onClick = { page = p }, icon = { Icon(pageIcon(p), null) }, label = { Text(stringResource(p.label)) }, modifier = Modifier.testTag("nav.${p.name.lowercase()}")) } } }) { inset ->
                Row(Modifier.fillMaxSize().padding(inset)) {
                    if (wide) NavigationRail { Page.entries.forEach { p -> NavigationRailItem(selected = page == p, onClick = { page = p }, icon = { Icon(pageIcon(p), null) }, label = { Text(stringResource(p.label)) }, modifier = Modifier.testTag("nav.${p.name.lowercase()}")) } }
                    Box(Modifier.weight(1f).fillMaxHeight().widthIn(max = 920.dp)) {
                        if (!state.loaded) CircularProgressIndicator(Modifier.align(Alignment.Center))
                        else when (page) {
                            Page.Home -> Column(Modifier.verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                                state.descriptor?.let { state.snapshot.entities[it.userId]?.fields?.text("displayName") }?.let { Text(it, style = MaterialTheme.typography.headlineMedium) }
                                ConnectionStatus(state)
                                if (state.historyReady) ElevatedCard(onClick = { page = Page.Plans }, modifier = Modifier.fillMaxWidth().testTag("home.plans")) {
                                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Text(stringResource(R.string.label_pending_tasks), style = MaterialTheme.typography.titleMedium)
                                        Text(state.snapshot.of("task").count { it.deletedAt == null && it.fields.text("status") != "completed" }.toString(), style = MaterialTheme.typography.headlineLarge)
                                        Text(stringResource(R.string.action_view_plans), color = MaterialTheme.colorScheme.primary)
                                    }
                                }
                                TextButton(onClick = { history = true }, modifier = Modifier.testTag("changes.open")) { Text(stringResource(R.string.action_changes)) }
                            }
                            Page.Plans -> TaskList(state, onEdit = { editor = it; editing = true }, onComplete = { perform { repository.completeTask(it) } }, onDelete = { perform { repository.deleteTask(it.id) } }, onCreate = { editor = null; editing = true })
                            Page.Connection -> DevicePage(state, onEnroll = { enrolling = true }, onRevoke = { perform { repository.revoke(it) } })
                            Page.Settings -> Column(Modifier.verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                                Text(stringResource(R.string.label_my_device), style = MaterialTheme.typography.titleLarge)
                                state.descriptor?.let { d -> IdentityDetails(d) }
                                Text(stringResource(R.string.label_version), style = MaterialTheme.typography.labelMedium)
                                Text(com.together.android.BuildConfig.VERSION_NAME)
                                TextButton(onClick = { history = true }) { Text(stringResource(R.string.action_changes)) }
                            }
                        }
                    }
                }
            }
        }
    }
    if (editing) TaskEditor(editor, onDismiss = { editing = false }, onSave = { title, notes -> repository.saveTask(editor?.id, title, notes); editing = false }, onError = { localError = it })
    if (history) ModalBottomSheet(onDismissRequest = { history = false }, modifier = Modifier.testTag("changes.sheet")) {
        ChangeHistory(state, onClose = { history = false }, onReview = { perform { repository.markReviewed(state.snapshot.changes.map { it.operationId }.toSet()) } })
    }
    if (enrolling) EnrollmentSheet(state, repository, onDismiss = { enrolling = false }, onError = { localError = it })
    if (error != null) AlertDialog(onDismissRequest = { localError = null; repository.clearError() }, text = { Text(stringResource(errorCopy(error))) }, confirmButton = {
        TextButton(onClick = { localError = null; repository.clearError() }) { Text(stringResource(R.string.action_close)) }
    })
}
private fun pageIcon(page: Page) = when (page) { Page.Home -> Icons.Outlined.Home; Page.Plans -> Icons.Outlined.CheckCircle; Page.Connection -> Icons.Outlined.Share; Page.Settings -> Icons.Outlined.Settings }
@Composable private fun ConnectionStatus(s: TogetherRepository.State) {
    val copy = if (s.descriptor == null) R.string.error_identity else if (s.authorization?.devices?.get(s.descriptor.deviceId)?.active == false) R.string.status_revoked else if (s.authorization == null) R.string.status_local else if (!s.historyReady) R.string.status_restoring_history else when (s.connection) {
        "connecting" -> R.string.status_connecting; "waiting" -> R.string.status_waiting; "syncing" -> R.string.status_syncing; "connected" -> R.string.status_connected; else -> R.string.status_offline
    }
    Text(stringResource(copy), color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("connection.status"))
}
@Composable private fun TaskList(state: TogetherRepository.State, onEdit: (ProjectedEntity) -> Unit, onComplete: (ProjectedEntity) -> Unit, onDelete: (ProjectedEntity) -> Unit, onCreate: () -> Unit) {
    if (!state.historyReady) { Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { ConnectionStatus(state); LinearProgressIndicator(Modifier.fillMaxWidth()) }; return }
    var completed by rememberSaveable { mutableStateOf(false) }
    val tasks = state.snapshot.of("task").filter { it.deletedAt == null && (it.fields.text("status") == "completed") == completed }
        .sortedWith(if (completed) compareByDescending { it.fields.date("completedAt") ?: 0 } else compareBy { it.base })
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
            listOf(false, true).forEachIndexed { index, v -> SegmentedButton(selected = completed == v, onClick = { completed = v }, shape = SegmentedButtonDefaults.itemShape(index, 2), modifier = Modifier.testTag(if (v) "tasks.completed" else "tasks.pending")) { Text(stringResource(if (v) R.string.filter_completed else R.string.filter_pending)) } }
        }
        if (tasks.isEmpty()) Column(Modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.empty_tasks), color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("tasks.empty"))
            // The toolbar remains the single create entry; no duplicate empty-state create button.
        }
        LazyColumn(Modifier.testTag("tasks.list"), verticalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(bottom = 24.dp)) {
            items(tasks, key = { it.id }) { task ->
                OutlinedCard(Modifier.fillMaxWidth()) {
                    Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        val completionLabel = stringResource(if (completed) R.string.action_reopen else R.string.action_complete)
                        Checkbox(checked = completed, enabled = state.canWrite, onCheckedChange = { onComplete(task) }, modifier = Modifier.testTag("task.complete.${task.id}").semantics { contentDescription = completionLabel })
                        Column(Modifier.weight(1f).clickable(enabled = state.canWrite) { onEdit(task) }.padding(vertical = 12.dp)) {
                            Text(task.fields.text("title").orEmpty(), style = MaterialTheme.typography.titleMedium)
                            task.fields.text("notes")?.takeIf { it.isNotEmpty() }?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        }
                        IconButton(onClick = { onDelete(task) }, enabled = state.canWrite, modifier = Modifier.testTag("task.delete.${task.id}")) { Icon(Icons.Outlined.Delete, stringResource(R.string.action_delete)) }
                    }
                }
            }
        }
    }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun TaskEditor(task: ProjectedEntity?, onDismiss: () -> Unit, onSave: suspend (String, String) -> Unit, onError: (String) -> Unit) {
    var title by rememberSaveable(task?.id) { mutableStateOf(task?.fields?.text("title").orEmpty()) }
    var notes by rememberSaveable(task?.id) { mutableStateOf(task?.fields?.text("notes").orEmpty()) }
    var busy by remember { mutableStateOf(false) }; val scope = rememberCoroutineScope()
    ModalBottomSheet(onDismissRequest = onDismiss, modifier = Modifier.testTag("task.editor")) {
        Column(Modifier.imePadding().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(stringResource(if (task == null) R.string.action_new_task else R.string.action_edit), style = MaterialTheme.typography.headlineSmall)
            OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text(stringResource(R.string.label_title)) }, modifier = Modifier.fillMaxWidth().testTag("task.title"), singleLine = false, maxLines = 4, isError = title.graphemeCount() > 200)
            OutlinedTextField(value = notes, onValueChange = { notes = it }, label = { Text(stringResource(R.string.label_notes)) }, modifier = Modifier.fillMaxWidth().testTag("task.notes"), minLines = 3, maxLines = 8)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) }
                Button(onClick = {
                    if (!busy) { busy = true; scope.launch {
                        try { onSave(title, notes) } catch (e: Exception) { if (e is CancellationException) throw e; onError((e as? ProtocolException)?.code ?: "LOCAL_OPERATION_FAILED") } finally { busy = false }
                    } }
                }, enabled = !busy && title.isNotBlank() && title.graphemeCount() <= 200 && notes.graphemeCount() <= 10000, modifier = Modifier.testTag("task.save")) { Text(stringResource(R.string.action_save)) }
            }
        }
    }
}
@Composable private fun IdentityDetails(d: DeviceDescriptor) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(d.displayName, style = MaterialTheme.typography.titleMedium)
        Text(stringResource(R.string.label_user), style = MaterialTheme.typography.labelMedium); Text(d.userId, style = MaterialTheme.typography.bodySmall)
        Text(stringResource(R.string.label_device), style = MaterialTheme.typography.labelMedium); Text(d.deviceId, style = MaterialTheme.typography.bodySmall)
        Text(stringResource(R.string.label_fingerprint), style = MaterialTheme.typography.labelMedium); Text(d.fingerprint, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
    }
}
@Composable private fun DevicePage(state: TogetherRepository.State, onEnroll: () -> Unit, onRevoke: (String) -> Unit) {
    var revoke by remember { mutableStateOf<String?>(null) }
    Column(Modifier.verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        ConnectionStatus(state)
        if (state.authorization == null) {
            Text(stringResource(R.string.guidance_add_device), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = onEnroll, enabled = state.descriptor != null, modifier = Modifier.testTag("device.add")) { Text(stringResource(R.string.action_add_my_device)) }
            state.descriptor?.let { IdentityDetails(it) }
        } else {
            Text(stringResource(R.string.label_devices), style = MaterialTheme.typography.titleLarge)
            state.authorization.devices.values.sortedBy { it.descriptor.deviceId }.forEach { d -> OutlinedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(d.descriptor.displayName, style = MaterialTheme.typography.titleMedium)
                    Text(stringResource(if (d.active) R.string.status_active else R.string.status_revoked), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(d.descriptor.fingerprint, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
                    val local = state.descriptor
                    if (d.active && local != null && state.authorization.root(local.userId)?.deviceId == local.deviceId && d.descriptor.userId == local.userId && d.descriptor.deviceId != local.deviceId) TextButton(onClick = { revoke = d.descriptor.deviceId }) { Text(stringResource(R.string.action_revoke)) }
                }
            } }
            Text(stringResource(R.string.guidance_root_required), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(stringResource(R.string.guidance_offline), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (revoke != null) AlertDialog(onDismissRequest = { revoke = null }, text = { Text(stringResource(R.string.confirm_revoke)) }, confirmButton = { TextButton(onClick = { onRevoke(revoke!!); revoke = null }) { Text(stringResource(R.string.action_revoke)) } }, dismissButton = { TextButton(onClick = { revoke = null }) { Text(stringResource(R.string.action_cancel)) } })
}
@Composable private fun ChangeHistory(state: TogetherRepository.State, onClose: () -> Unit, onReview: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(stringResource(R.string.action_changes), style = MaterialTheme.typography.headlineSmall)
        if (state.snapshot.changes.isEmpty()) Text(stringResource(R.string.empty_changes))
        LazyColumn(Modifier.weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            items(state.snapshot.changes.asReversed(), key = { it.operationId }) { event ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(when (event.entityType) { "task", "recurrenceRule" -> R.string.label_task; "profile" -> R.string.label_profile; "wishGrant", "wishItem", "grantAdjustment" -> R.string.label_wish; "loveGift" -> R.string.label_gift; else -> R.string.label_finance }), style = MaterialTheme.typography.titleMedium)
                    Text(stringResource(if (event.actorId == state.descriptor?.userId) { if (event.deviceId == state.descriptor.deviceId) R.string.label_you else R.string.label_other_device } else R.string.label_partner), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    ChangeValues(event, state)
                    Text(stringResource(if (event.resolution == "superseded") R.string.status_superseded else if (event.resolution == "partiallySuperseded") R.string.status_partially_superseded else if (event.operationId in state.reviewed) R.string.status_reviewed else when (event.action) { "create" -> R.string.status_created; "delete" -> R.string.status_deleted; else -> R.string.status_modified }), style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            if (state.snapshot.changes.any { it.operationId !in state.reviewed }) TextButton(onClick = onReview) { Text(stringResource(R.string.action_review)) }
            TextButton(onClick = onClose, modifier = Modifier.testTag("changes.close")) { Text(stringResource(R.string.action_close)) }
        }
    }
}
@Composable private fun ChangeValues(event: ChangeEvent, state: TogetherRepository.State) {
    if (event.entityType == "loveGift") return // Sealed content is never constructed here.
    val labels = mapOf("title" to R.string.label_title, "displayName" to R.string.label_profile, "notes" to R.string.label_notes,
        "description" to R.string.label_details, "amount" to R.string.label_amount, "payment" to R.string.label_payment,
        "quantity" to R.string.label_quantity, "delta" to R.string.label_quantity, "status" to R.string.label_status,
        "date" to R.string.label_date, "dueAt" to R.string.label_date, "grantedOn" to R.string.label_date)
    for ((key, label) in labels) {
        val old = event.before[key]; val new = event.after[key]
        if (old == new) continue
        val before = changeValue(key, old, state); val after = changeValue(key, new, state)
        if (before == null && after == null) continue
        Text(stringResource(label), style = MaterialTheme.typography.labelMedium)
        if (before != null) { Text(stringResource(R.string.label_before), style = MaterialTheme.typography.labelSmall); Text(before) }
        if (after != null) { Text(stringResource(R.string.label_after), style = MaterialTheme.typography.labelSmall); Text(after) }
    }
}
@Composable private fun changeValue(key: String, value: kotlinx.serialization.json.JsonObject?, state: TogetherRepository.State): String? {
    if (value == null || value == LogValue.nil) return null
    val raw = LogValue.string(value)
    if (key == "status") return stringResource(when (raw) {
        "pending" -> R.string.filter_pending; "completed" -> R.string.filter_completed; "open" -> R.string.status_wish_open
        "completionRequested" -> R.string.status_wish_requested; "fulfilled" -> R.string.status_wish_fulfilled; "conflict" -> R.string.status_conflict
        "provisional" -> R.string.status_provisional; "reconciled" -> R.string.status_reconciled; "skipped" -> R.string.status_skipped
        else -> R.string.label_status
    })
    if (raw != null) return raw
    LogValue.long(value)?.let { return it.toString() }
    LogValue.long(value, "date")?.let { return java.time.format.DateTimeFormatter.ofLocalizedDateTime(java.time.format.FormatStyle.MEDIUM).withZone(java.time.ZoneId.systemDefault()).format(java.time.Instant.ofEpochMilli(it)) }
    val bytes = LogValue.bytes(value) ?: return null
    val parsed = runCatching { Canonical.parse(bytes, 16384) }.getOrNull() ?: return null
    return when (key) {
        "amount" -> runCatching { Amount.from(parsed) }.getOrNull()?.let { "¥" + Money.string(it.finalCNYMinor) + if (it.currencyCode == "CNY") "" else " / " + Money.string(it.originalMinor, it.currencyCode) + " " + it.currencyCode }
        "payment" -> {
            val payment = runCatching { Payment.from(parsed) }.getOrNull() ?: return null
            if (payment.kind == "reserves") stringResource(R.string.label_shared_reserves)
            else payment.userIds.map { user -> state.snapshot.entities[user]?.fields?.text("displayName") ?: stringResource(if (user == state.descriptor?.userId) R.string.label_you else R.string.label_partner) }.joinToString(" / ")
        }
        "date" -> runCatching { CivilDate.from(parsed).iso }.getOrNull()
        else -> null
    }
}
private fun errorCopy(code: String) = when (code) {
    "OFFER_EXPIRED" -> R.string.error_offer_expired
    "EXISTING_LOCAL_DATA" -> R.string.error_existing_data
    "IDENTITY_FILE_UNAVAILABLE", "IDENTITY_KEY_UNAVAILABLE", "IDENTITY_MISMATCH" -> R.string.error_identity
    "CONNECTION_FAILED", "SERVICE_UNAVAILABLE" -> R.string.error_network
    "INVALID_COMPLETION", "INVALID_OFFER", "INVALID_ENROLLMENT_REQUEST", "INVALID_GENESIS_SIGNATURES", "INVALID_JSON" -> R.string.error_invalid_file
    else -> R.string.error_generic
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun EnrollmentSheet(state: TogetherRepository.State, repository: TogetherRepository, onDismiss: () -> Unit, onError: (String) -> Unit) {
    val context = LocalContext.current; val scope = rememberCoroutineScope()
    var offer by remember { mutableStateOf(state.offer) }; var rawOffer by remember { mutableStateOf<ByteArray?>(state.offer?.let { Canonical.encode(it) }) }
    var confirmed by rememberSaveable { mutableStateOf(false) }; var name by rememberSaveable { mutableStateOf(android.os.Build.MODEL.take(80)) }
    var request by remember { mutableStateOf<ByteArray?>(state.request?.let { Canonical.encode(it) }) }; var busy by remember { mutableStateOf(false) }
    fun fail(e: Exception) { if (e is CancellationException) throw e; onError((e as? ProtocolException)?.code ?: "INVALID_FILE") }
    suspend fun read(uri: Uri): ByteArray = withContext(Dispatchers.IO) {
        val input = context.contentResolver.openInputStream(uri) ?: throw ProtocolException("INVALID_FILE")
        input.use { stream ->
            val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
            while (true) { val n = stream.read(buffer); if (n < 0) break; requireProtocol(out.size() + n <= 524_288, "FILE_BOUNDS"); out.write(buffer, 0, n) }
            out.toByteArray()
        }
    }
    val requestFilename = stringResource(R.string.filename_device_request)
    val saveRequest = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri -> if (uri != null && request != null) scope.launch(Dispatchers.IO) {
        try { context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(request!!) } ?: throw ProtocolException("FILE_WRITE_FAILED") } catch (e: Exception) { withContext(Dispatchers.Main) { fail(e) } }
    } }
    val importOffer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) scope.launch {
        try { val bytes = read(uri); val value = Canonical.parse(bytes).model<EnrollmentOffer>(); withContext(Dispatchers.IO) { value.verify(System.currentTimeMillis(), com.together.android.BuildConfig.DEBUG) }; rawOffer = bytes; offer = value; confirmed = false } catch (e: Exception) { fail(e) }
    } }
    val importCompletion = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) scope.launch {
        busy = true
        try { repository.completeEnrollment(read(uri), confirmed); onDismiss() } catch (e: Exception) { fail(e) } finally { busy = false }
    } }
    ModalBottomSheet(onDismissRequest = onDismiss, modifier = Modifier.testTag("device.enrollment")) {
        Column(Modifier.imePadding().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(stringResource(R.string.action_add_my_device), style = MaterialTheme.typography.headlineSmall)
            if (offer == null) {
                Text(stringResource(R.string.guidance_add_device))
                Button(onClick = { importOffer.launch(arrayOf("application/json", "application/octet-stream")) }, modifier = Modifier.testTag("device.importOffer")) { Text(stringResource(R.string.action_import_offer)) }
            } else {
                Text(stringResource(R.string.label_verification_code), style = MaterialTheme.typography.labelMedium)
                Text(offer!!.code, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.titleMedium)
                offer!!.body.archive.genesis.body.roots.firstOrNull { it.deviceId == offer!!.body.issuerDeviceId }?.let { Text(it.fingerprint, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = confirmed, onCheckedChange = { confirmed = it }, modifier = Modifier.testTag("device.confirmCode"))
                    Text(stringResource(R.string.confirm_identity), modifier = Modifier.weight(1f))
                }
                if (request == null) {
                    OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.label_display_name)) }, modifier = Modifier.fillMaxWidth())
                    Button(enabled = confirmed && name.isNotBlank() && !busy, onClick = { scope.launch {
                        busy = true
                        try { request = repository.stageOffer(rawOffer!!, name, confirmed) } catch (e: Exception) { fail(e) } finally { busy = false }
                    } }) { Text(stringResource(R.string.action_create_request)) }
                } else {
                    Text(stringResource(R.string.guidance_request))
                    val req = remember(request) { Canonical.parse(request!!).model<EnrollmentRequest>() }
                    Text(req.code, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.titleMedium)
                    Text(req.body.device.fingerprint, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
                    OutlinedButton(onClick = { saveRequest.launch(requestFilename) }, enabled = !busy, modifier = Modifier.testTag("device.exportRequest")) { Text(stringResource(R.string.action_export_request)) }
                    Button(onClick = { importCompletion.launch(arrayOf("application/json", "application/octet-stream")) }, enabled = confirmed && !busy, modifier = Modifier.testTag("device.importCompletion")) { Text(stringResource(R.string.action_import_completion)) }
                }
            }
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_close)) }
        }
    }
}
