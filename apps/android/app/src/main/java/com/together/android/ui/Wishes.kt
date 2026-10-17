package com.together.android.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.together.android.R
import com.together.android.data.TogetherRepository
import com.together.domain.*
import com.together.protocol.*

@Composable
internal fun WishesPage(
    state: TogetherRepository.State,
    onGrant: (ProjectedEntity) -> Unit,
    onConnect: () -> Unit,
) {
    val users = members(state)
    val grants =
        state.snapshot
            .of("wishGrant")
            .sortedWith(
                compareByDescending<ProjectedEntity> { it.fields.text("grantedOn") }
                    .thenByDescending { it.base }
            )
    LazyColumn(
        Modifier.fillMaxSize().padding(horizontal = 20.dp).testTag("wishes.list"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        if (users.size < 2)
            item {
                Text(stringResource(R.string.guidance_partner_needed))
                TextButton(onClick = onConnect) { Text(stringResource(R.string.nav_connection)) }
            }
        if (users.size == 2)
            items(users, key = { "direction:$it" }) { fulfiller ->
                val beneficiary = users.single { it != fulfiller }
                val selected = grants.filter { it.fields.id("fulfillerId") == fulfiller }
                val total = selected.sumOf { state.snapshot.grantTotals[it.id] ?: 0 }
                val fulfilled =
                    state.snapshot.wishes.values.count {
                        it.fulfiller == fulfiller && it.status == "fulfilled"
                    }
                OutlinedCard(Modifier.fillMaxWidth()) {
                    Column(
                        Modifier.padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            memberName(state, fulfiller) + " → " + memberName(state, beneficiary),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(
                            stringResource(
                                R.string.wish_totals,
                                total,
                                fulfilled,
                                total - fulfilled,
                            ),
                            modifier = Modifier.testTag("wishes.stats.$fulfiller"),
                        )
                    }
                }
            }
        if (grants.isEmpty())
            item { Text(stringResource(R.string.empty_grants), Modifier.padding(vertical = 24.dp)) }
        items(grants, key = { it.id }) { g ->
            OutlinedCard(
                onClick = { onGrant(g) },
                modifier = Modifier.fillMaxWidth().testTag("grant.${g.id}"),
            ) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        g.fields.text("grantedOn").orEmpty(),
                        style = MaterialTheme.typography.labelMedium,
                    )
                    Text(
                        memberName(state, g.fields.id("fulfillerId")!!) +
                            " → " +
                            memberName(state, g.fields.id("beneficiaryId")!!),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(stringResource(R.string.grant_added, g.fields.number("quantity") ?: 0))
                    Text(
                        stringResource(
                            R.string.wish_totals,
                            state.snapshot.grantTotals[g.id] ?: 0,
                            state.snapshot.wishes.values.count {
                                it.grantId == g.id && it.status == "fulfilled"
                            },
                            state.snapshot.remaining(g.id),
                        )
                    )
                    g.fields.text("notes")?.takeIf { it.isNotBlank() }?.let { Text(it) }
                }
            }
        }
    }
}

@Composable
internal fun GrantForm(
    state: TogetherRepository.State,
    repository: TogetherRepository,
    onClose: () -> Unit,
    onError: (String) -> Unit,
) {
    val users = members(state)
    var fulfiller by rememberSaveable { mutableStateOf(state.descriptor!!.userId) }
    var count by rememberSaveable { mutableStateOf("") }
    var day by rememberSaveable {
        mutableStateOf(
            dayKey(
                state.now,
                state.authorization?.archive?.genesis?.body?.sharedTimeZoneIdentifier ?: "Etc/UTC",
            )
        )
    }
    var notes by rememberSaveable { mutableStateOf("") }
    FormSheet(
        R.string.action_add_wishes,
        onClose,
        "wish.grant.editor",
        onSave = {
            val beneficiary = users.single { it != fulfiller }
            repository.execute {
                listOf(grant(fulfiller, beneficiary, count.toLong(), CivilDate.parse(day), notes))
            }
        },
        onError = onError,
        enabled = users.size == 2 && count.toLongOrNull() in 1..10000L,
    ) {
        Choice(
            R.string.label_fulfiller,
            fulfiller,
            users.map { it to memberName(state, it) },
            { fulfiller = it },
        )
        Input(count, { count = it }, R.string.label_quantity, "grant.quantity")
        DateField(day, { day = it })
        Input(notes, { notes = it }, R.string.label_notes, lines = 3)
    }
}

@Composable
internal fun GrantDetail(
    grantId: String,
    state: TogetherRepository.State,
    repository: TogetherRepository,
    onClose: () -> Unit,
    onError: (String) -> Unit,
    perform: (suspend () -> Unit) -> Unit,
) {
    val grant = state.snapshot.entities[grantId] ?: return
    val actor = state.descriptor!!.userId
    var mode by rememberSaveable { mutableStateOf("detail") }
    var wishId by rememberSaveable { mutableStateOf<String?>(null) }
    var title by rememberSaveable { mutableStateOf("") }
    var details by rememberSaveable { mutableStateOf("") }
    var delta by rememberSaveable { mutableStateOf("") }
    var baseline by remember { mutableStateOf<Wish?>(null) }
    val save: (suspend () -> Unit)? =
        when (mode) {
            "wish" -> {
                {
                    repository.execute { listOf(wish(grantId, title, details, wishId, baseline)) }
                    mode = "detail"
                }
            }
            "adjust" -> {
                {
                    repository.execute { listOf(adjustment(grantId, delta.toLong(), details)) }
                    mode = "detail"
                }
            }
            else -> null
        }
    // Internal editor replaces detail content, never stacks another business modal.
    FormSheet(
        if (mode == "wish") R.string.action_new_wish
        else if (mode == "adjust") R.string.action_adjust_quota else R.string.label_grant_history,
        onClose,
        "wish.detail",
        onSave = save?.let { action -> { action() } },
        onError = onError,
        enabled = state.canWrite,
    ) {
        if (mode == "wish") {
            Input(title, { title = it }, R.string.label_title, "wish.title")
            Input(details, { details = it }, R.string.label_details, lines = 3)
        } else if (mode == "adjust") {
            Input(delta, { delta = it }, R.string.label_adjustment)
            Input(details, { details = it }, R.string.label_reason, lines = 3)
        } else {
            Text(grant.fields.text("grantedOn").orEmpty())
            Text(stringResource(R.string.grant_remaining, state.snapshot.remaining(grantId)))
            if (grant.fields.id("beneficiaryId") == actor)
                Button(
                    onClick = {
                        mode = "wish"
                        wishId = null
                        baseline = null
                        title = ""
                        details = ""
                    },
                    enabled = state.canWrite,
                    modifier = Modifier.testTag("wish.new"),
                ) {
                    Text(stringResource(R.string.action_new_wish))
                }
            if (grant.base.actorId == actor)
                TextButton(
                    onClick = {
                        mode = "adjust"
                        delta = ""
                        details = ""
                    },
                    enabled = state.canWrite,
                ) {
                    Text(stringResource(R.string.action_adjust_quota))
                }
            state.snapshot.wishes.values
                .filter { it.grantId == grantId }
                .forEach { wish ->
                    OutlinedCard(Modifier.fillMaxWidth()) {
                        Column(
                            Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(wish.title, style = MaterialTheme.typography.titleMedium)
                            if (wish.description.isNotBlank()) Text(wish.description)
                            Text(
                                stringResource(
                                    when (wish.status) {
                                        "fulfilled" -> R.string.status_wish_fulfilled
                                        "completionRequested" -> R.string.status_wish_requested
                                        "conflict" -> R.string.status_conflict
                                        else -> R.string.status_wish_open
                                    }
                                )
                            )
                            if (wish.status != "conflict" && wish.status != "fulfilled") {
                                if (actor == wish.beneficiary)
                                    TextButton(
                                        onClick = {
                                            mode = "wish"
                                            wishId = wish.id
                                            baseline = wish.copy()
                                            title = wish.title
                                            details = wish.description
                                        }
                                    ) {
                                        Text(stringResource(R.string.action_edit))
                                    }
                                if (actor == wish.fulfiller && wish.status == "open")
                                    Button(
                                        onClick = {
                                            perform {
                                                repository.execute {
                                                    listOf(
                                                        wishAction(wish.id, "requestFulfillment")
                                                    )
                                                }
                                            }
                                        },
                                        modifier = Modifier.testTag("wish.request.${wish.id}"),
                                    ) {
                                        Text(stringResource(R.string.action_request_fulfillment))
                                    }
                                if (
                                    actor == wish.beneficiary &&
                                        wish.status == "completionRequested"
                                )
                                    Row {
                                        Button(
                                            onClick = {
                                                perform {
                                                    repository.execute {
                                                        listOf(
                                                            wishAction(
                                                                wish.id,
                                                                "confirmFulfillment",
                                                            )
                                                        )
                                                    }
                                                }
                                            },
                                            modifier = Modifier.testTag("wish.confirm.${wish.id}"),
                                        ) {
                                            Text(
                                                stringResource(R.string.action_confirm_fulfillment)
                                            )
                                        }
                                        TextButton(
                                            onClick = {
                                                perform {
                                                    repository.execute {
                                                        listOf(
                                                            wishAction(wish.id, "rejectFulfillment")
                                                        )
                                                    }
                                                }
                                            }
                                        ) {
                                            Text(stringResource(R.string.action_reject_fulfillment))
                                        }
                                    }
                            }
                        }
                    }
                }
            state.snapshot
                .of("grantAdjustment")
                .filter { it.fields.id("grantId") == grantId }
                .forEach { a ->
                    Text(
                        (a.fields.number("delta") ?: 0).toString() +
                            " · " +
                            a.fields.text("notes").orEmpty()
                    )
                    if (a.fields.bool("effective") != true)
                        Text(stringResource(R.string.status_conflict))
                }
        }
    }
}
