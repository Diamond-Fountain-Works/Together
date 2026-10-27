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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.together.android.R
import com.together.android.data.TogetherRepository
import com.together.android.localization.AppLanguage
import com.together.domain.*
import com.together.protocol.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

@Composable
private fun TogetherTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val colors =
        if (dark)
            darkColorScheme(
                primary = Color(0xFFE6A1B1),
                onPrimary = Color(0xFF451F2B),
                secondary = Color(0xFFD1A4B0),
                secondaryContainer = Color(0xFF51343D),
                onSecondaryContainer = Color(0xFFFFDBE5),
                background = Color(0xFF1B181A),
                surface = Color(0xFF242024),
                surfaceContainerLow = Color(0xFF241F22),
                surfaceContainer = Color(0xFF2A2428),
                surfaceContainerHigh = Color(0xFF342B30),
                surfaceContainerHighest = Color(0xFF3E343B),
            )
        else
            lightColorScheme(
                primary = Color(0xFFAD4F65),
                secondary = Color(0xFF855562),
                secondaryContainer = Color(0xFFF3DFE3),
                onSecondaryContainer = Color(0xFF44232C),
                background = Color(0xFFFBF7F0),
                surface = Color(0xFFFFFBF6),
                surfaceContainerLow = Color(0xFFFFF9F4),
                surfaceContainer = Color(0xFFF6EFE8),
                surfaceContainerHigh = Color(0xFFF0E8E0),
                surfaceContainerHighest = Color(0xFFE9E0DC),
            )
    MaterialTheme(
        colorScheme = colors,
        shapes = Shapes(medium = RoundedCornerShape(16.dp), small = RoundedCornerShape(12.dp)),
        content = content,
    )
}

private enum class Page(val label: Int) {
    Home(R.string.nav_home),
    Plans(R.string.nav_plans),
    Wishes(R.string.nav_wishes),
    Finances(R.string.nav_finances),
    Connection(R.string.nav_connection),
    Settings(R.string.nav_settings),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TogetherApp(
    repository: TogetherRepository,
    language: AppLanguage? = null,
    onLanguageChange: ((AppLanguage) -> Unit)? = null,
) = TogetherTheme {
    val state by repository.state.collectAsStateWithLifecycle()
    var page by rememberSaveable { mutableStateOf(Page.Home) }
    var filter by rememberSaveable { mutableStateOf("pending") }
    LaunchedEffect(filter) {
        // Restore old Activity state into the unified task workspace.
        if (filter != "pending" && filter != "completed") filter = "pending"
    }
    var financeTab by rememberSaveable { mutableIntStateOf(0) }
    var modal by rememberSaveable { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<ProjectedEntity?>(null) }
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var financeKind by rememberSaveable { mutableStateOf("expense") }
    var reply by rememberSaveable { mutableStateOf<String?>(null) }
    var automatic by remember { mutableStateOf(false) }
    var revealQueue by remember { mutableStateOf<List<String>>(emptyList()) }
    var actions by remember { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    val context = LocalContext.current
    val currentContext by rememberUpdatedState(context)
    var localError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val drawer = rememberDrawerState(DrawerValue.Closed)
    fun perform(block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                localError = (e as? ProtocolException)?.code ?: "LOCAL_OPERATION_FAILED"
            }
        }
    }
    fun show(name: String) {
        repository.noteInteraction()
        modal = name
    }
    fun navigate(p: Page) {
        repository.noteInteraction()
        page = p
        scope.launch { drawer.close() }
    }
    fun editFinance(kind: String, entity: ProjectedEntity?) {
        financeKind = kind
        selected = entity
        show("finance")
    }
    fun openGift(id: String, auto: Boolean = false) {
        val g = state.snapshot.gifts[id] ?: return
        if (!g.effective || g.entity.deletedAt != null) {
            modal = null
            return
        }
        if (
            !giftAssets(g).all {
                state.snapshot.entities[it]
                    ?.let(Asset::from)
                    ?.let(repository.mediaFiles::verified) == true
            }
        ) {
            localError = "MEDIA_PENDING"
            return
        }
        selectedId = id
        automatic = auto
        modal = "reveal"
    }
    LaunchedEffect(state.autoGifts, modal) {
        if (!state.requiresInitialSetup && modal == null && state.autoGifts.isNotEmpty() && repository.canPresentAutomatically()) {
            revealQueue = state.autoGifts
            openGift(revealQueue.first(), true)
        }
    }
    LaunchedEffect(state.snapshot.gifts, modal, selectedId) {
        if (
            modal == "reveal" &&
                state.snapshot.gifts[selectedId]?.let {
                    it.effective && it.entity.deletedAt == null
                } != true
        ) {
            revealQueue = emptyList()
            modal = null
        }
    }
    LaunchedEffect(Unit) {
        repository.state
            .map { s ->
                s.snapshot.changes
                    .filter {
                        it.deviceId != s.descriptor?.deviceId &&
                            it.resolution == "effective" &&
                            it.operationId !in s.notified &&
                            it.operationId !in s.reviewed
                    }
                    .take(32)
                    .map { it.operationId }
            }
            .filter { it.isNotEmpty() }
            .distinctUntilChanged()
            .collect { ids ->
                val message = currentContext.getString(R.string.notice_synced_changes, ids.size)
                val display = async {
                    snackbar.showSnackbar(
                        message,
                        currentContext.getString(R.string.action_changes),
                        duration = SnackbarDuration.Long,
                    )
                }
                snapshotFlow { snackbar.currentSnackbarData }.first { it != null }
                runCatching { repository.markNotified(ids.toSet()) }
                    .onFailure { localError = "LOCAL_OPERATION_FAILED" }
                if (display.await() == SnackbarResult.ActionPerformed) show("changes")
            }
    }
    val error = localError ?: state.error
    Surface(color = MaterialTheme.colorScheme.background) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val wide = maxWidth >= 600.dp
            @Composable
            fun workspace() {
                Scaffold(
                    snackbarHost = { SnackbarHost(snackbar) },
                    topBar = {
                        TopAppBar(
                            title = {
                                Text(
                                    if (page == Page.Home) stringResource(R.string.app_name)
                                    else stringResource(page.label)
                                )
                            },
                            navigationIcon = {
                                if (!wide)
                                    IconButton(
                                        onClick = {
                                            repository.noteInteraction()
                                            scope.launch { drawer.open() }
                                        },
                                        modifier = Modifier.testTag("navigation.open"),
                                    ) {
                                        Icon(
                                            Icons.Outlined.Menu,
                                            stringResource(R.string.action_navigation),
                                        )
                                    }
                            },
                            actions = {
                                val create =
                                    state.loaded &&
                                        state.canWrite &&
                                        (page == Page.Plans && filter == "pending" ||
                                            page == Page.Wishes && members(state).size == 2 ||
                                            page == Page.Finances)
                                if (create)
                                    IconButton(
                                        onClick = {
                                            when (page) {
                                                Page.Plans -> {
                                                    selected = null
                                                    show("task")
                                                }
                                                Page.Wishes -> show("grant")
                                                Page.Finances ->
                                                    editFinance(
                                                        listOf(
                                                            "reserveEntry",
                                                            "expense",
                                                            "recurringBill",
                                                        )[financeTab],
                                                        null,
                                                    )
                                                else -> Unit
                                            }
                                        },
                                        modifier =
                                            Modifier.testTag(
                                                if (page == Page.Plans) "task.new"
                                                else if (page == Page.Wishes) "grant.new"
                                                else "finance.new"
                                            ),
                                    ) {
                                        Icon(
                                            Icons.Outlined.Add,
                                            stringResource(
                                                when (page) {
                                                    Page.Plans -> R.string.action_new_task
                                                    Page.Wishes -> R.string.action_add_wishes
                                                    else -> R.string.action_add_record
                                                }
                                            ),
                                        )
                                    }
                                Box {
                                    IconButton(
                                        onClick = {
                                            repository.noteInteraction()
                                            actions = true
                                        },
                                        modifier = Modifier.testTag("app.actions"),
                                    ) {
                                        Icon(
                                            Icons.Outlined.MoreVert,
                                            stringResource(R.string.action_more),
                                        )
                                    }
                                    DropdownMenu(
                                        expanded = actions,
                                        onDismissRequest = { actions = false },
                                    ) {
                                        listOf(
                                                "gift" to R.string.action_send_gift,
                                                "gifts" to R.string.action_gift_history,
                                                "changes" to R.string.action_changes,
                                            )
                                            .forEach { (name, key) ->
                                                DropdownMenuItem(
                                                    text = { Text(stringResource(key)) },
                                                    onClick = {
                                                        actions = false
                                                        reply = null
                                                        show(name)
                                                    },
                                                    enabled = state.loaded && state.historyReady &&
                                                        state.descriptor != null && !state.requiresInitialSetup &&
                                                        (name != "gift" || state.canWrite),
                                                    modifier = Modifier.testTag("menu.$name"),
                                                )
                                            }
                                    }
                                }
                                if (page == Page.Settings && language != null && onLanguageChange != null) {
                                    LanguageMenu(language, onLanguageChange)
                                }
                            },
                        )
                    },
                ) { inset ->
                    Row(Modifier.fillMaxSize().padding(inset)) {
                        if (wide)
                            NavigationRail {
                                Page.entries.forEach { p ->
                                    NavigationRailItem(
                                        selected = page == p,
                                        onClick = { navigate(p) },
                                        icon = { Icon(pageIcon(p), null) },
                                        label = { Text(stringResource(p.label)) },
                                        modifier = Modifier.testTag("nav.${p.name.lowercase()}"),
                                    )
                                }
                            }
                        Box(Modifier.weight(1f).fillMaxHeight().widthIn(max = 1040.dp)) {
                            if (!state.loaded)
                                CircularProgressIndicator(Modifier.align(Alignment.Center))
                            else if (!state.historyReady && !(page == Page.Connection && state.native != null)) {
                                Column(Modifier.padding(24.dp)) {
                                    if (state.descriptor == null) {
                                        Text(stringResource(R.string.error_identity))
                                        Text(stringResource(R.string.guidance_identity_recovery),
                                            style = MaterialTheme.typography.bodySmall)
                                    } else {
                                        ConnectionStatus(state)
                                        LinearProgressIndicator(Modifier.fillMaxWidth())
                                    }
                                }
                            } else
                                when (page) {
                                    Page.Home ->
                                        Column(
                                            Modifier.verticalScroll(rememberScrollState())
                                                .padding(24.dp),
                                            verticalArrangement = Arrangement.spacedBy(20.dp),
                                        ) {
                                            Row(
                                                horizontalArrangement = Arrangement.spacedBy(24.dp)
                                            ) {
                                                members(state).forEach { user ->
                                                    Column(
                                                        modifier = Modifier.weight(1f),
                                                        horizontalAlignment =
                                                            Alignment.CenterHorizontally,
                                                    ) {
                                                        ProfileAvatar(user, state, repository)
                                                        Text(
                                                            memberName(state, user),
                                                            maxLines = 2,
                                                            overflow =
                                                                androidx.compose.ui.text.style
                                                                    .TextOverflow
                                                                    .Ellipsis,
                                                            style =
                                                                MaterialTheme.typography
                                                                    .titleMedium,
                                                        )
                                                    }
                                                }
                                            }
                                            ConnectionStatus(state)
                                            val incoming =
                                                state.snapshot.gifts.values.count {
                                                    it.effective &&
                                                        it.entity.deletedAt == null &&
                                                        it.entity.fields.id("recipientId") ==
                                                            state.descriptor?.userId &&
                                                        state.presentations[it.id]?.openedAt == null
                                                }
                                            if (incoming > 0)
                                                TextButton(
                                                    onClick = { show("gifts") },
                                                    modifier = Modifier.testTag("gift.unread"),
                                                ) {
                                                    Text(
                                                        stringResource(
                                                            R.string.gift_unread_count,
                                                            incoming,
                                                        )
                                                    )
                                                }
                                            OutlinedCard(
                                                onClick = {
                                                    filter = "pending"
                                                    navigate(Page.Plans)
                                                },
                                                modifier =
                                                    Modifier.fillMaxWidth().testTag("home.plans"),
                                            ) {
                                                Column(Modifier.padding(20.dp)) {
                                                    Text(
                                                        stringResource(R.string.label_pending_tasks)
                                                    )
                                                    Text(
                                                        BusinessQueries.tasks(
                                                                state.snapshot,
                                                                "pending",
                                                                state.now,
                                                            )
                                                            .size
                                                            .toString(),
                                                        style =
                                                            MaterialTheme.typography.headlineLarge,
                                                    )
                                                }
                                            }
                                            if (
                                                BusinessQueries.tasks(
                                                        state.snapshot,
                                                        "upcoming",
                                                        state.now,
                                                    )
                                                    .isNotEmpty()
                                            )
                                                OutlinedCard(
                                                    onClick = {
                                                        filter = "pending"
                                                        navigate(Page.Plans)
                                                    },
                                                    modifier = Modifier.fillMaxWidth(),
                                                ) {
                                                    Column(Modifier.padding(20.dp)) {
                                                        Text(
                                                            stringResource(R.string.filter_upcoming)
                                                        )
                                                        Text(
                                                            BusinessQueries.tasks(
                                                                    state.snapshot,
                                                                    "upcoming",
                                                                    state.now,
                                                                )
                                                                .size
                                                                .toString()
                                                        )
                                                    }
                                                }
                                            if (state.snapshot.grantTotals.isNotEmpty())
                                                OutlinedCard(
                                                    onClick = { navigate(Page.Wishes) },
                                                    modifier = Modifier.fillMaxWidth(),
                                                ) {
                                                    Column(Modifier.padding(20.dp)) {
                                                        Text(stringResource(R.string.nav_wishes))
                                                        Text(
                                                            stringResource(
                                                                R.string.grant_remaining,
                                                                state.snapshot.grantTotals.keys
                                                                    .sumOf {
                                                                        state.snapshot.remaining(it)
                                                                    },
                                                            )
                                                        )
                                                    }
                                                }
                                            TextButton(
                                                onClick = { show("changes") },
                                                modifier = Modifier.testTag("changes.open"),
                                            ) {
                                                Text(stringResource(R.string.action_changes))
                                            }
                                        }
                                    Page.Plans ->
                                        TasksPage(
                                            state,
                                            filter,
                                            {
                                                filter = it
                                                repository.noteInteraction()
                                            },
                                            {
                                                selected = it
                                                show("task")
                                            },
                                            { task ->
                                                if (
                                                    task.fields.text("status") != "completed" &&
                                                        state.snapshot.entities[
                                                                task.fields.id("recurrenceRuleId")]
                                                            ?.fields
                                                            ?.text("mode") == "flexible"
                                                ) {
                                                    selected = task
                                                    show("completeFlexible")
                                                } else perform { repository.completeTask(task) }
                                            },
                                            { task -> perform { repository.deleteTask(task.id) } },
                                        )
                                    Page.Wishes ->
                                        WishesPage(
                                            state,
                                            {
                                                selectedId = it.id
                                                show("grantDetail")
                                            },
                                            { navigate(Page.Connection) },
                                        )
                                    Page.Finances ->
                                        FinancesPage(
                                            state,
                                            financeTab,
                                            {
                                                financeTab = it
                                                repository.noteInteraction()
                                            },
                                            ::editFinance,
                                            { show("financeSettings") },
                                            { show("changes") },
                                            ::perform,
                                            repository,
                                        )
                                    Page.Connection ->
                                        Column(Modifier.verticalScroll(rememberScrollState())) {
                                            if (state.native != null) NativePartnerPanel(
                                                state.native!!,
                                                state.authorization != null,
                                                { perform { repository.createPartnerInvitation() } },
                                                { code -> perform { repository.joinPartnerInvitation(code) } },
                                                { verified -> perform { repository.confirmPartner(verified) } },
                                                { value -> perform { repository.nativeOffline(value) } },
                                                { perform { repository.cancelNativeInvitation() } },
                                            )
                                            else if (state.authorization == null) PartnerPairingPanel(
                                                state.partnerPairing,
                                                { perform { repository.createPartnerInvitation() } },
                                                { code -> perform { repository.joinPartnerInvitation(code) } },
                                                { verified -> perform { repository.confirmPartner(verified) } },
                                            )
                                            DevicePage(
                                                state,
                                                { show("enrollment") },
                                                { perform { repository.revoke(it) } },
                                            )
                                            state.transfers.values.forEach { t ->
                                                Column(Modifier.padding(20.dp)) {
                                                    Text(
                                                        stringResource(
                                                            if (t.status == "failed")
                                                                R.string.status_media_failed
                                                            else if (t.status == "verified")
                                                                R.string.status_media_verified
                                                            else R.string.status_media_pending
                                                        )
                                                    )
                                                    LinearProgressIndicator(
                                                        progress = {
                                                            if (t.total > 0)
                                                                (t.done.toDouble() / t.total)
                                                                    .toFloat()
                                                            else 0f
                                                        },
                                                        modifier = Modifier.fillMaxWidth(),
                                                    )
                                                }
                                            }
                                            state.connectionError?.let { code ->
                                                Text(
                                                    stringResource(errorCopy(code)),
                                                    Modifier.padding(horizontal = 24.dp),
                                                    color =
                                                        MaterialTheme.colorScheme.onSurfaceVariant,
                                                )
                                                TextButton(
                                                    onClick = { repository.reconnect() },
                                                    modifier =
                                                        Modifier.padding(horizontal = 12.dp)
                                                            .testTag("connection.retry"),
                                                ) {
                                                    Text(stringResource(R.string.action_retry))
                                                }
                                            }
                                            if (
                                                state.transfers.values.any { it.status == "failed" }
                                            )
                                                TextButton(
                                                    onClick = {
                                                        perform { repository.retryMedia() }
                                                    }
                                                ) {
                                                    Text(stringResource(R.string.action_retry))
                                                }
                                        }
                                    Page.Settings ->
                                        Column(
                                            Modifier.verticalScroll(rememberScrollState())
                                                .padding(24.dp),
                                            verticalArrangement = Arrangement.spacedBy(20.dp),
                                        ) {
                                            TextButton(
                                                onClick = { show("profile") },
                                                modifier = Modifier.testTag("profile.open"),
                                            ) {
                                                Text(stringResource(R.string.label_profile))
                                            }
                                            state.descriptor?.let { IdentityDetails(it) }
                                            Text(stringResource(R.string.label_version))
                                            Text(com.together.android.BuildConfig.VERSION_NAME)
                                            Text(
                                                stringResource(R.string.guidance_identity_recovery),
                                                style = MaterialTheme.typography.bodySmall,
                                            )
                                        }
                                }
                        }
                    }
                }
            }
            if (wide) workspace()
            else
                ModalNavigationDrawer(
                    drawerState = drawer,
                    drawerContent = {
                        ModalDrawerSheet {
                            Page.entries.forEach { p ->
                                NavigationDrawerItem(
                                    selected = page == p,
                                    onClick = { navigate(p) },
                                    label = { Text(stringResource(p.label)) },
                                    icon = { Icon(pageIcon(p), null) },
                                    modifier =
                                        Modifier.padding(horizontal = 12.dp)
                                            .testTag("nav.${p.name.lowercase()}"),
                                )
                            }
                        }
                    },
                ) {
                    workspace()
                }
        }
    }
    when (if (state.requiresInitialSetup && state.error == null) "initialSetup" else modal) {
        "initialSetup" -> ProfileForm(state, repository, {}, { localError = it }, initialSetup = true)
        "task" ->
            TaskForm(
                selected,
                state,
                repository,
                { modal = null },
                { localError = it },
                onNext = { show("next") },
            )
        "next",
        "completeFlexible" ->
            selected?.let {
                NextTimeForm(
                    it,
                    repository,
                    { modal = null },
                    { localError = it },
                    modal == "completeFlexible",
                )
            }
        "grant" -> GrantForm(state, repository, { modal = null }, { localError = it })
        "grantDetail" ->
            selectedId?.let {
                GrantDetail(it, state, repository, { modal = null }, { localError = it }, ::perform)
            }
        "finance" ->
            if (financeKind == "events")
                DateEventsSheet(state, { modal = null }, { editFinance("dateEvent", it) })
            else
                FinanceForm(
                    financeKind,
                    selected,
                    state,
                    repository,
                    { modal = null },
                    { localError = it },
                    ::perform,
                    { editFinance("forecast", selected) },
                )
        "financeSettings" ->
            FinanceSettings(
                state,
                repository,
                { modal = null },
                { localError = it },
                { show("cards") },
            )
        "cards" -> CardsSheet(state, repository, { modal = null }, { localError = it }, ::perform)
        "profile" -> ProfileForm(state, repository, { modal = null }, { localError = it })
        "enrollment" -> EnrollmentSheet(state, repository, { modal = null }, { localError = it })
        "gift" -> GiftEditor(state, repository, { modal = null }, { localError = it }, reply)
        "gifts" ->
            GiftHistory(
                state,
                { modal = null },
                {
                    repository.noteInteraction()
                    openGift(it)
                },
                { id -> perform { repository.execute { listOf(delete(id)) } } },
            )
        "reveal" ->
            selectedId?.let {
                GiftReveal(
                    it,
                    automatic,
                    state,
                    repository,
                    {
                        if (revealQueue.size > 1) {
                            revealQueue = revealQueue.drop(1)
                            openGift(revealQueue.first(), true)
                        } else {
                            revealQueue = emptyList()
                            modal = null
                        }
                    },
                    { id ->
                        reply = id
                        revealQueue = emptyList()
                        show("gift")
                    },
                    { localError = it },
                )
            }
        "changes" ->
            ModalBottomSheet(
                onDismissRequest = { modal = null },
                modifier = Modifier.testTag("changes.sheet"),
            ) {
                ChangeHistory(
                    state,
                    { modal = null },
                    {
                        perform {
                            repository.markReviewed(
                                state.snapshot.changes.map { it.operationId }.toSet()
                            )
                        }
                    },
                    onView = { event ->
                        when (event.entityType) {
                            "task",
                            "recurrenceRule" -> {
                                selected =
                                    if (event.entityType == "task")
                                        state.snapshot.entities[event.entityId]
                                    else
                                        state.snapshot.of("task").firstOrNull {
                                            it.fields.id("recurrenceRuleId") == event.entityId &&
                                                it.deletedAt == null
                                        }
                                if (selected != null && selected?.deletedAt == null) show("task")
                                else {
                                    modal = null
                                    navigate(Page.Plans)
                                }
                            }
                            "wishGrant",
                            "wishItem",
                            "grantAdjustment" -> {
                                selectedId =
                                    state.snapshot.wishes[event.entityId]?.grantId
                                        ?: state.snapshot.entities[event.entityId]
                                            ?.fields
                                            ?.id("grantId")
                                        ?: event.entityId
                                show("grantDetail")
                            }
                            "profile" -> {
                                if (event.actorId == state.descriptor?.userId) show("profile")
                                else {
                                    modal = null
                                    navigate(Page.Home)
                                }
                            }
                            "loveGift" -> {
                                repository.noteInteraction()
                                openGift(event.entityId)
                            }
                            else -> {
                                val entity = state.snapshot.entities[event.entityId]
                                if (
                                    entity?.deletedAt == null &&
                                        entity?.base?.entityType in
                                            setOf(
                                                "reserveEntry",
                                                "expense",
                                                "dateEvent",
                                                "recurringBill",
                                            )
                                )
                                    editFinance(entity!!.base.entityType, entity)
                                else {
                                    modal = null
                                    navigate(Page.Finances)
                                }
                            }
                        }
                    },
                    repository = repository,
                )
            }
    }
    if (error != null)
        AlertDialog(
            onDismissRequest = {
                localError = null
                repository.clearError()
            },
            text = { Text(stringResource(errorCopy(error))) },
            confirmButton = {
                TextButton(
                    onClick = {
                        localError = null
                        repository.clearError()
                    }
                ) {
                    Text(stringResource(R.string.action_close))
                }
            },
        )
}

private fun pageIcon(page: Page) =
    when (page) {
        Page.Home -> Icons.Outlined.Home
        Page.Plans -> Icons.Outlined.CheckCircle
        Page.Wishes -> Icons.Outlined.Favorite
        Page.Finances -> Icons.Outlined.AccountBox
        Page.Connection -> Icons.Outlined.Share
        Page.Settings -> Icons.Outlined.Settings
    }

@Composable
private fun ConnectionStatus(s: TogetherRepository.State) {
    val copy =
        if (s.descriptor == null) R.string.error_identity
        else if (s.authorization?.devices?.get(s.descriptor.deviceId)?.active == false)
            R.string.status_revoked
        else if (!s.historyReady && s.native != null) R.string.status_restoring_history
        else if (s.authorization == null) when (s.native?.stage) {
            "creating", "connecting", "authenticating" -> R.string.status_connecting
            "waiting", "verifying" -> R.string.status_waiting
            "confirming", "syncing" -> R.string.status_syncing
            else -> R.string.status_local
        }
        else if (!s.historyReady) R.string.status_restoring_history
        else
            when (s.connection) {
                "connecting" -> R.string.status_connecting
                "waiting" -> R.string.status_waiting
                "syncing" -> R.string.status_syncing
                "connected" -> R.string.status_connected
                else -> R.string.status_offline
            }
    Text(
        stringResource(copy),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.testTag("connection.status"),
    )
}

@Composable
internal fun IdentityDetails(d: DeviceDescriptor) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(d.displayName, style = MaterialTheme.typography.titleMedium)
        Text(stringResource(R.string.label_user), style = MaterialTheme.typography.labelMedium)
        Text(d.userId, style = MaterialTheme.typography.bodySmall)
        Text(stringResource(R.string.label_device), style = MaterialTheme.typography.labelMedium)
        Text(d.deviceId, style = MaterialTheme.typography.bodySmall)
        Text(
            stringResource(R.string.label_fingerprint),
            style = MaterialTheme.typography.labelMedium,
        )
        Text(
            d.fingerprint,
            fontFamily = FontFamily.Monospace,
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
internal fun DevicePage(
    state: TogetherRepository.State,
    onEnroll: () -> Unit,
    onRevoke: (String) -> Unit,
) {
    var revoke by remember { mutableStateOf<String?>(null) }
    Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        ConnectionStatus(state)
        if (state.authorization == null && state.native == null) {
            Text(
                stringResource(R.string.guidance_add_device),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            TextButton(
                onClick = onEnroll,
                enabled = state.descriptor != null,
                modifier = Modifier.testTag("device.add"),
            ) {
                Text(stringResource(R.string.action_add_my_device))
            }
            state.descriptor?.let { IdentityDetails(it) }
        } else if (state.authorization != null) {
            Text(
                stringResource(R.string.label_devices),
                style = MaterialTheme.typography.titleLarge,
            )
            state.authorization.devices.values
                .sortedBy { it.descriptor.deviceId }
                .forEach { d ->
                    OutlinedCard(Modifier.fillMaxWidth()) {
                        Column(
                            Modifier.padding(20.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                d.descriptor.displayName,
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Text(
                                stringResource(
                                    if (d.active) R.string.status_active
                                    else R.string.status_revoked
                                ),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                d.descriptor.fingerprint,
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace,
                            )
                            val local = state.descriptor
                            if (
                                state.native == null && d.active &&
                                    local != null &&
                                    state.authorization.root(local.userId)?.deviceId ==
                                        local.deviceId &&
                                    d.descriptor.userId == local.userId &&
                                    d.descriptor.deviceId != local.deviceId
                            )
                                TextButton(onClick = { revoke = d.descriptor.deviceId }) {
                                    Text(stringResource(R.string.action_revoke))
                                }
                        }
                    }
                }
            if (state.native == null) Text(
                stringResource(R.string.guidance_root_required),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    if (revoke != null)
        AlertDialog(
            onDismissRequest = { revoke = null },
            text = { Text(stringResource(R.string.confirm_revoke)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        onRevoke(revoke!!)
                        revoke = null
                    }
                ) {
                    Text(stringResource(R.string.action_revoke))
                }
            },
            dismissButton = {
                TextButton(onClick = { revoke = null }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
}

@Composable
internal fun ChangeHistory(
    state: TogetherRepository.State,
    onClose: () -> Unit,
    onReview: () -> Unit,
    onView: (ChangeEvent) -> Unit,
    repository: TogetherRepository,
) {
    var domain by rememberSaveable { mutableStateOf("all") }
    val matching =
        state.snapshot.changes.filter {
            domain == "all" || ChangeReview.domain(it.entityType) == domain
        }
    var page by rememberSaveable(domain) { mutableIntStateOf(0) }
    var events by remember { mutableStateOf<List<ChangeEvent>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(domain, page, state.snapshot.changes) {
        loading = true
        try {
            events = repository.reviewPage(domain, page)
        } finally {
            loading = false
        }
    }
    Column(
        Modifier.fillMaxWidth().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            stringResource(R.string.action_changes),
            style = MaterialTheme.typography.headlineSmall,
        )
        Choice(
            R.string.label_domain,
            domain,
            listOf(
                "all" to stringResource(R.string.filter_all),
                "task" to stringResource(R.string.nav_plans),
                "wish" to stringResource(R.string.nav_wishes),
                "finance" to stringResource(R.string.nav_finances),
                "profile" to stringResource(R.string.label_profile),
                "gift" to stringResource(R.string.label_gift),
            ),
            { domain = it },
        )
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        else if (events.isEmpty()) Text(stringResource(R.string.empty_changes))
        LazyColumn(
            Modifier.heightIn(max = 420.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            items(events, key = { it.operationId }) { event ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        stringResource(
                            when (event.entityType) {
                                "task",
                                "recurrenceRule" -> R.string.label_task
                                "profile" -> R.string.label_profile
                                "wishGrant",
                                "wishItem",
                                "grantAdjustment" -> R.string.label_wish
                                "loveGift" -> R.string.label_gift
                                else -> R.string.label_finance
                            }
                        ),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        memberName(state, event.actorId) +
                            " · " +
                            stringResource(
                                if (event.actorId == state.descriptor?.userId) {
                                    if (event.deviceId == state.descriptor.deviceId)
                                        R.string.label_you
                                    else R.string.label_other_device
                                } else R.string.label_partner
                            ),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        java.time.Instant.ofEpochMilli(event.createdAt)
                            .atZone(java.time.ZoneId.systemDefault())
                            .toLocalDateTime()
                            .toString(),
                        style = MaterialTheme.typography.labelSmall,
                    )
                    ChangeValues(event, state)
                    Text(
                        stringResource(
                            if (event.resolution == "superseded") R.string.status_superseded
                            else if (event.resolution == "partiallySuperseded")
                                R.string.status_partially_superseded
                            else
                                when (event.action) {
                                    "create" -> R.string.status_created
                                    "delete" -> R.string.status_deleted
                                    else -> R.string.status_modified
                                }
                        )
                    )
                    Text(
                        stringResource(
                            when (state.operationStates[event.operationId]) {
                                "converged" -> R.string.status_converged
                                "remotePersisted" -> R.string.status_remote_persisted
                                "pending" -> R.string.status_pending_sync
                                else -> R.string.status_local_saved
                            }
                        ),
                        style = MaterialTheme.typography.labelMedium,
                    )
                    if (event.operationId in state.reviewed)
                        Text(
                            stringResource(R.string.status_reviewed),
                            style = MaterialTheme.typography.labelMedium,
                        )
                    if (
                        event.action == "confirmFulfillment" &&
                            state.snapshot.wishes[event.entityId]?.status == "fulfilled"
                    )
                        Text(stringResource(R.string.status_domain_confirmed))
                    TextButton(onClick = { onView(event) }) {
                        Text(stringResource(R.string.action_view))
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = { page-- }, enabled = page > 0) {
                Text(stringResource(R.string.action_newer))
            }
            TextButton(
                onClick = { page++ },
                enabled = (page + 1) * ChangeReview.PAGE_SIZE < matching.size,
            ) {
                Text(stringResource(R.string.action_older))
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            if (state.snapshot.changes.any { it.operationId !in state.reviewed })
                TextButton(onClick = onReview) { Text(stringResource(R.string.action_review)) }
            TextButton(onClick = onClose, modifier = Modifier.testTag("changes.close")) {
                Text(stringResource(R.string.action_close))
            }
        }
    }
}

@Composable
private fun ChangeValues(event: ChangeEvent, state: TogetherRepository.State) {
    if (event.entityType == "loveGift") return // Sealed content is never constructed here.
    if (
        event.entityType == "profile" &&
            listOf("avatarAssetId", "avatarData", "avatarCrop").any {
                event.before[it] != event.after[it]
            }
    )
        Text(stringResource(R.string.status_avatar_changed))
    val labels =
        mapOf(
            "title" to R.string.label_title,
            "displayName" to R.string.label_profile,
            "notes" to R.string.label_notes,
            "description" to R.string.label_details,
            "amount" to R.string.label_amount,
            "payment" to R.string.label_payment,
            "quantity" to R.string.label_quantity,
            "delta" to R.string.label_quantity,
            "status" to R.string.label_status,
            "date" to R.string.label_date,
            "dueAt" to R.string.label_date,
            "grantedOn" to R.string.label_date,
            "relationshipLabel" to R.string.label_relationship,
            "assignedTo" to R.string.label_assignee,
            "category" to R.string.label_category,
            "mode" to R.string.label_recurrence,
            "unit" to R.string.label_unit,
            "interval" to R.string.label_every_n,
            "timeZoneIdentifier" to R.string.label_time_zone,
            "zone" to R.string.label_time_zone,
            "day" to R.string.label_month_day,
            "salaryDay" to R.string.label_salary_day,
            "depositDay" to R.string.label_planned_deposit,
        )
    for ((key, label) in labels) {
        val old = event.before[key]
        val new = event.after[key]
        if (old == new) continue
        val before = changeValue(key, old, state)
        val after = changeValue(key, new, state)
        if (before == null && after == null) continue
        Text(stringResource(label), style = MaterialTheme.typography.labelMedium)
        if (before != null) {
            Text(stringResource(R.string.label_before), style = MaterialTheme.typography.labelSmall)
            Text(before)
        }
        if (after != null) {
            Text(stringResource(R.string.label_after), style = MaterialTheme.typography.labelSmall)
            Text(after)
        }
    }
}

@Composable
private fun changeValue(
    key: String,
    value: kotlinx.serialization.json.JsonObject?,
    state: TogetherRepository.State,
): String? {
    if (value == null || value == LogValue.nil) return null
    val raw = LogValue.string(value)
    if (key == "assignedTo" && raw != null) return memberName(state, raw)
    if (key == "relationshipLabel")
        return stringResource(
            when (Relationship.parse(raw)) {
                Relationship.BOYFRIEND -> R.string.role_boyfriend
                Relationship.GIRLFRIEND -> R.string.role_girlfriend
                else -> R.string.role_unknown
            }
        )
    if (key == "mode")
        return stringResource(
            if (raw == "flexible") R.string.label_flexible else R.string.label_regular
        )
    if (key == "unit")
        return stringResource(
            when (raw) {
                "week" -> R.string.label_weekly
                "month" -> R.string.label_monthly
                else -> R.string.label_daily
            }
        )
    if (key == "status")
        return stringResource(
            when (raw) {
                "pending" -> R.string.filter_pending
                "completed" -> R.string.filter_completed
                "open" -> R.string.status_wish_open
                "completionRequested" -> R.string.status_wish_requested
                "fulfilled" -> R.string.status_wish_fulfilled
                "conflict" -> R.string.status_conflict
                "provisional" -> R.string.status_provisional
                "reconciled" -> R.string.status_reconciled
                "skipped" -> R.string.status_skipped
                else -> R.string.label_status
            }
        )
    if (raw != null) return raw
    LogValue.long(value)?.let {
        return it.toString()
    }
    LogValue.long(value, "date")?.let {
        return java.time.format.DateTimeFormatter.ofLocalizedDateTime(
                java.time.format.FormatStyle.MEDIUM
            )
            .withLocale(androidx.compose.ui.platform.LocalConfiguration.current.locales[0])
            .withZone(java.time.ZoneId.systemDefault())
            .format(java.time.Instant.ofEpochMilli(it))
    }
    val bytes = LogValue.bytes(value) ?: return null
    val parsed = runCatching { Canonical.parse(bytes, 16384) }.getOrNull() ?: return null
    return when (key) {
        "amount" ->
            runCatching { Amount.from(parsed) }
                .getOrNull()
                ?.let {
                    "¥" +
                        Money.string(it.finalCNYMinor) +
                        if (it.currencyCode == "CNY") ""
                        else
                            " / " +
                                Money.string(it.originalMinor, it.currencyCode) +
                                " " +
                                it.currencyCode
                }
        "payment" -> {
            val payment = runCatching { Payment.from(parsed) }.getOrNull() ?: return null
            if (payment.kind == "reserves") stringResource(R.string.label_shared_reserves)
            else
                payment.userIds
                    .map { user ->
                        state.snapshot.entities[user]?.fields?.text("displayName")
                            ?: stringResource(
                                if (user == state.descriptor?.userId) R.string.label_you
                                else R.string.label_partner
                            )
                    }
                    .joinToString(" / ")
        }
        "date" -> runCatching { CivilDate.from(parsed).iso }.getOrNull()
        else -> null
    }
}

internal fun errorCopy(code: String) =
    when (code) {
        "INVALID_AMOUNT",
        "INVALID_RATE",
        "INVALID_CURRENCY",
        "MISSING_SETTLEMENT",
        "MISSING_RATE",
        "SETTLEMENT_MISMATCH",
        "AMOUNT_BOUNDS" -> R.string.error_amount
        "GIFT_QUOTA_USED" -> R.string.error_quota
        "CLOCK_MOVED_BACK" -> R.string.error_clock_back
        "NO_WISH_QUOTA" -> R.string.error_no_quota
        "RECORD_CHANGED" -> R.string.error_record_changed
        "MICROPHONE_DENIED",
        "MICROPHONE_UNAVAILABLE" -> R.string.error_mic
        "EXPORT_FORMAT_MISMATCH" -> R.string.error_export
        "MEDIA_STORAGE_FULL" -> R.string.error_media_storage
        "MEDIA_PENDING",
        "MEDIA_IO_ERROR",
        "UNSUPPORTED_MEDIA",
        "UNVERIFIED_MEDIA",
        "MEDIA_HASH_MISMATCH",
        "EMPTY_MEDIA" -> R.string.error_media
        "OFFER_EXPIRED" -> R.string.error_offer_expired
        "EXISTING_LOCAL_DATA" -> R.string.error_existing_data
        "IDENTITY_FILE_UNAVAILABLE",
        "IDENTITY_KEY_UNAVAILABLE",
        "IDENTITY_MISMATCH" -> R.string.error_identity
        "CONNECTION_FAILED",
        "P2P_CONNECT_TIMEOUT",
        "SERVICE_UNAVAILABLE" -> R.string.error_network
        "PARTNER_SERVICE_UPGRADE_REQUIRED" -> R.string.partner_service_upgrade
        "INVALID_INVITATION", "INVITATION_UNAVAILABLE" -> R.string.partner_invalid_invitation
        "PAIRING_FINISHING" -> R.string.partner_finishing
        "IDENTITY_CONFIRMATION_REQUIRED" -> R.string.partner_verify
        "INVALID_COMPLETION",
        "INVALID_OFFER",
        "INVALID_ENROLLMENT_REQUEST",
        "INVALID_GENESIS_SIGNATURES",
        "INVALID_JSON" -> R.string.error_invalid_file
        else -> R.string.error_generic
    }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun EnrollmentSheet(
    state: TogetherRepository.State,
    repository: TogetherRepository,
    onDismiss: () -> Unit,
    onError: (String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var offer by remember { mutableStateOf(state.offer) }
    var rawOffer by remember {
        mutableStateOf<ByteArray?>(state.offer?.let { Canonical.encode(it) })
    }
    var confirmed by rememberSaveable { mutableStateOf(false) }
    var name by rememberSaveable { mutableStateOf(android.os.Build.MODEL.take(80)) }
    var request by remember {
        mutableStateOf<ByteArray?>(state.request?.let { Canonical.encode(it) })
    }
    var busy by remember { mutableStateOf(false) }
    fun fail(e: Exception) {
        if (e is CancellationException) throw e
        onError((e as? ProtocolException)?.code ?: "INVALID_FILE")
    }
    suspend fun read(uri: Uri): ByteArray =
        withContext(Dispatchers.IO) {
            val input =
                context.contentResolver.openInputStream(uri)
                    ?: throw ProtocolException("INVALID_FILE")
            input.use { stream ->
                val out = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val n = stream.read(buffer)
                    if (n < 0) break
                    requireProtocol(out.size() + n <= 524_288, "FILE_BOUNDS")
                    out.write(buffer, 0, n)
                }
                out.toByteArray()
            }
        }
    val requestFilename = stringResource(R.string.filename_device_request)
    val saveRequest =
        rememberLauncherForActivityResult(
            ActivityResultContracts.CreateDocument("application/json")
        ) { uri ->
            if (uri != null && request != null)
                scope.launch(Dispatchers.IO) {
                    try {
                        context.contentResolver.openOutputStream(uri, "wt")?.use {
                            it.write(request!!)
                        } ?: throw ProtocolException("FILE_WRITE_FAILED")
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { fail(e) }
                    }
                }
        }
    val importOffer =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null)
                scope.launch {
                    try {
                        val bytes = read(uri)
                        val value = Canonical.parse(bytes).model<EnrollmentOffer>()
                        withContext(Dispatchers.IO) {
                            value.verify(
                                System.currentTimeMillis(),
                                com.together.android.BuildConfig.DEBUG,
                            )
                        }
                        rawOffer = bytes
                        offer = value
                        confirmed = false
                    } catch (e: Exception) {
                        fail(e)
                    }
                }
        }
    val importCompletion =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null)
                scope.launch {
                    busy = true
                    try {
                        repository.completeEnrollment(read(uri), confirmed)
                        onDismiss()
                    } catch (e: Exception) {
                        fail(e)
                    } finally {
                        busy = false
                    }
                }
        }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        modifier = Modifier.testTag("device.enrollment"),
    ) {
        Column(
            Modifier.imePadding().verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                stringResource(R.string.action_add_my_device),
                style = MaterialTheme.typography.headlineSmall,
            )
            if (offer == null) {
                Button(
                    onClick = {
                        importOffer.launch(arrayOf("application/json", "application/octet-stream"))
                    },
                    modifier = Modifier.testTag("device.importOffer"),
                ) {
                    Text(stringResource(R.string.action_import_offer))
                }
            } else {
                Text(
                    stringResource(R.string.label_verification_code),
                    style = MaterialTheme.typography.labelMedium,
                )
                Text(
                    offer!!.code,
                    fontFamily = FontFamily.Monospace,
                    style = MaterialTheme.typography.titleMedium,
                )
                offer!!
                    .body
                    .archive
                    .genesis
                    .body
                    .roots
                    .firstOrNull { it.deviceId == offer!!.body.issuerDeviceId }
                    ?.let {
                        Text(
                            it.fingerprint,
                            fontFamily = FontFamily.Monospace,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(
                        checked = confirmed,
                        onCheckedChange = { confirmed = it },
                        modifier = Modifier.testTag("device.confirmCode"),
                    )
                    Text(stringResource(R.string.confirm_identity), modifier = Modifier.weight(1f))
                }
                if (request == null) {
                    OutlinedTextField(
                        name,
                        { name = it },
                        label = { Text(stringResource(R.string.label_display_name)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Button(
                        enabled = confirmed && name.isNotBlank() && !busy,
                        onClick = {
                            scope.launch {
                                busy = true
                                try {
                                    request = repository.stageOffer(rawOffer!!, name, confirmed)
                                } catch (e: Exception) {
                                    fail(e)
                                } finally {
                                    busy = false
                                }
                            }
                        },
                    ) {
                        Text(stringResource(R.string.action_create_request))
                    }
                } else {
                    Text(stringResource(R.string.guidance_request))
                    val req =
                        remember(request) { Canonical.parse(request!!).model<EnrollmentRequest>() }
                    Text(
                        req.code,
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        req.body.device.fingerprint,
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                    )
                    OutlinedButton(
                        onClick = { saveRequest.launch(requestFilename) },
                        enabled = !busy,
                        modifier = Modifier.testTag("device.exportRequest"),
                    ) {
                        Text(stringResource(R.string.action_export_request))
                    }
                    Button(
                        onClick = {
                            importCompletion.launch(
                                arrayOf("application/json", "application/octet-stream")
                            )
                        },
                        enabled = confirmed && !busy,
                        modifier = Modifier.testTag("device.importCompletion"),
                    ) {
                        Text(stringResource(R.string.action_import_completion))
                    }
                }
            }
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_close)) }
        }
    }
}


/** Settings-only locale control; the navigation drawer and rail stay unchanged. */
@Composable
private fun LanguageMenu(
    language: AppLanguage,
    onChange: (AppLanguage) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    Box(modifier) {
        IconButton(onClick = { expanded = true }, modifier = Modifier.testTag("settings.language")) {
            Icon(
                painter = androidx.compose.ui.res.painterResource(R.drawable.ic_language),
                contentDescription = stringResource(R.string.label_language),
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            AppLanguage.entries.forEach { candidate ->
                DropdownMenuItem(
                    text = { Text(stringResource(if (candidate == AppLanguage.CHINESE)
                        R.string.language_chinese else R.string.language_english)) },
                    trailingIcon = {
                        if (candidate == language) Icon(Icons.Outlined.Check, contentDescription = null)
                    },
                    onClick = { expanded = false; onChange(candidate) },
                    modifier = Modifier.testTag("language.${candidate.tag}"),
                )
            }
        }
    }
}
