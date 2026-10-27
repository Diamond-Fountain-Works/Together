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
import java.time.*
import kotlinx.serialization.json.*

internal fun cnyDisplay(value: Long) = "¥" + Money.string(value)

internal fun visibleCards(s: TogetherRepository.State) =
    (s.privateCards +
            s.snapshot
                .of("paymentMethod")
                .filter { it.deletedAt == null && it.fields.bool("shared") == true }
                .map { it.fields.data("card").jsonObject })
        .distinctBy { it.getValue("id").jsonPrimitive.content }

@Composable
internal fun PaymentFields(
    value: Payment,
    state: TogetherRepository.State,
    onChange: (Payment) -> Unit,
) {
    val me = state.descriptor!!.userId
    val partner = members(state).firstOrNull { it != me }
    val selected =
        when (value.kind) {
            "reserves" -> "reserves"
            "equalSplit" -> "aa"
            else -> if (value.userIds.firstOrNull() == me) "me" else "partner"
        }
    val options =
        listOf(
            "reserves" to stringResource(R.string.label_shared_reserves),
            "me" to stringResource(R.string.payment_me),
        ) +
            if (partner != null)
                listOf(
                    "partner" to stringResource(R.string.payment_partner),
                    "aa" to stringResource(R.string.payment_aa),
                )
            else emptyList()
    Choice(
        R.string.label_payment,
        selected,
        options,
        { v ->
            onChange(
                when (v) {
                    "reserves" -> Payment("reserves", emptyList(), value.paymentMethodId)
                    "aa" -> Payment("equalSplit", listOf(me, partner!!), value.paymentMethodId)
                    else ->
                        Payment(
                            "personal",
                            listOf(if (v == "me") me else partner!!),
                            value.paymentMethodId,
                        )
                }
            )
        },
        "payment.kind",
    )
    val cards = visibleCards(state)
    Choice(
        R.string.label_payment_tool,
        value.paymentMethodId ?: "",
        listOf("" to stringResource(R.string.label_none)) +
            cards.map {
                it.getValue("id").jsonPrimitive.content to
                    (it.getValue("name").jsonPrimitive.content +
                        " · " +
                        it.getValue("lastFour").jsonPrimitive.content)
            },
        { onChange(value.copy(paymentMethodId = it.ifBlank { null })) },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FinancesPage(
    state: TogetherRepository.State,
    tab: Int,
    onTab: (Int) -> Unit,
    onEdit: (String, ProjectedEntity?) -> Unit,
    onSettings: () -> Unit,
    onChanges: () -> Unit,
    perform: (suspend () -> Unit) -> Unit,
    repository: TogetherRepository,
) {
    var period by rememberSaveable { mutableStateOf("all") }
    var funding by rememberSaveable { mutableStateOf("all") }
    var status by rememberSaveable { mutableStateOf("all") }
    var source by rememberSaveable { mutableStateOf("all") }
    var category by rememberSaveable { mutableStateOf("") }
    val s = state.snapshot
    val me = state.descriptor!!.userId
    val zone =
        state.authorization?.archive?.genesis?.body?.sharedTimeZoneIdentifier
            ?: ZoneId.systemDefault().id
    val owner = if (period == "me") me else null
    val settings = s.entities[stableId("finance-settings:${owner?:"shared"}")]
    val cycleZone = settings?.fields?.text("zone") ?: zone
    val interval =
        FinancialCalendar.cycle(
            state.now,
            (settings?.fields?.number("day") ?: 1).toInt(),
            cycleZone,
        )
    fun inPeriod(e: ProjectedEntity): Boolean {
        if (period == "all") return true
        val at =
            FinancialCalendar.instant(
                CivilDate.from(e.fields.data("date")),
                e.fields.text("zone") ?: cycleZone,
            )
        return at >= interval.first && at < interval.second
    }
    val subset =
        Snapshot(
            entities =
                s.entities
                    .filterValues {
                        it.base.entityType !in setOf("expense", "reserveEntry") || inPeriod(it)
                    }
                    .toMutableMap()
        )
    val stats = FinanceProjection.statistics(subset)
    LazyColumn(
        Modifier.fillMaxSize().padding(horizontal = 20.dp).testTag("finance.page"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        item {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                listOf(R.string.tab_reserves, R.string.tab_expenses, R.string.tab_bills)
                    .forEachIndexed { i, label ->
                        SegmentedButton(
                            selected = tab == i,
                            onClick = { onTab(i) },
                            shape = SegmentedButtonDefaults.itemShape(i, 3),
                            modifier = Modifier.testTag("finance.tab.$i"),
                        ) {
                            Text(stringResource(label), maxLines = 1)
                        }
                    }
            }
        }
        item {
            Row {
                TextButton(onClick = onSettings, modifier = Modifier.testTag("finance.settings")) {
                    Text(stringResource(R.string.action_finance_settings))
                }
                TextButton(onClick = onChanges) { Text(stringResource(R.string.action_changes)) }
            }
        }
        items(
            BusinessQueries.reminders(s, state.now, me).filter {
                it.id !in state.dismissedReminders
            },
            key = { it.id },
        ) { r ->
            OutlinedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text(
                        stringResource(
                            if (r.kind == "before") R.string.reminder_before_bill
                            else if (r.kind == "depositPlan") R.string.reminder_planned_deposit
                            else R.string.reminder_review_bill
                        )
                    )
                    Text(s.entities[r.entityId]?.fields?.text("title").orEmpty())
                    if (r.kind == "before")
                        s.entities[r.entityId]?.let { bill ->
                            val z = bill.fields.text("zone")!!
                            val tomorrow = state.now.atZone(ZoneId.of(z)).toLocalDate().plusDays(1)
                            val o =
                                FinanceProjection.occurrence(
                                    bill,
                                    FinanceMonth(tomorrow.year, tomorrow.monthValue),
                                    s,
                                )
                            Text(
                                Money.string(o.amount.originalMinor, o.amount.currencyCode) +
                                    " " +
                                    o.amount.currencyCode +
                                    " → " +
                                    cnyDisplay(o.amount.finalCNYMinor)
                            )
                            o.amount.exchangeRate?.let { fx ->
                                Text(
                                    fx.getValue("cnyPerOriginalUnit").jsonPrimitive.content +
                                        " · " +
                                        fx.getValue("source").jsonPrimitive.content
                                )
                            }
                        }
                    Row {
                        TextButton(
                            onClick = {
                                onEdit(
                                    if (r.kind == "before") "forecast"
                                    else if (r.kind == "depositPlan") "reserveEntry" else "expense",
                                    if (r.kind == "depositPlan") null else s.entities[r.entityId],
                                )
                            }
                        ) {
                            Text(stringResource(R.string.action_review_bill))
                        }
                        TextButton(onClick = { perform { repository.dismissReminder(r.id) } }) {
                            Text(stringResource(R.string.action_dismiss))
                        }
                    }
                }
            }
        }
        if (tab != 2)
            item {
                Choice(
                    R.string.label_period,
                    period,
                    listOf(
                        "all" to stringResource(R.string.filter_all),
                        "shared" to stringResource(R.string.label_shared_cycle),
                        "me" to stringResource(R.string.label_my_cycle),
                    ),
                    { period = it },
                )
                if (period != "all")
                    Text(
                        interval.first.atZone(ZoneId.of(cycleZone)).toLocalDate().toString() +
                            " – " +
                            interval.second.atZone(ZoneId.of(cycleZone)).toLocalDate().toString(),
                        style = MaterialTheme.typography.labelMedium,
                    )
            }
        if (tab == 0) {
            item {
                OutlinedCard(Modifier.fillMaxWidth()) {
                    Column(
                        Modifier.padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(stringResource(R.string.label_book_balance))
                        Text(
                            cnyDisplay(stats.bookBalance),
                            style = MaterialTheme.typography.headlineLarge,
                            color =
                                if (stats.bookBalance < 0) MaterialTheme.colorScheme.error
                                else MaterialTheme.colorScheme.onSurface,
                        )
                        Text(
                            stringResource(R.string.label_verified_balance) +
                                " · " +
                                cnyDisplay(stats.verifiedBalance)
                        )
                        Text(
                            stringResource(R.string.label_provisional_amount) +
                                " · " +
                                cnyDisplay(stats.provisional)
                        )
                    }
                }
            }
            item {
                TextButton(
                    onClick = {
                        onEdit("opening", s.entities[stableId("finance-reserves-opening")])
                    }
                ) {
                    Text(stringResource(R.string.action_opening_balance))
                }
            }
            val deposits =
                s.of("reserveEntry")
                    .filter { it.deletedAt == null && inPeriod(it) }
                    .sortedByDescending { CivilDate.from(it.fields.data("date")) }
            if (deposits.isEmpty()) item { Text(stringResource(R.string.empty_deposits)) }
            items(deposits, key = { it.id }) { e ->
                FinanceRow(e, state) {
                    onEdit(
                        if (e.fields.data("kind").jsonPrimitive.content == "opening") "opening"
                        else "reserveEntry",
                        e,
                    )
                }
            }
            val spending =
                s.of("expense").filter {
                    it.deletedAt == null &&
                        it.fields.text("status") != "skipped" &&
                        Payment.from(it.fields.data("payment")).kind == "reserves" &&
                        inPeriod(it)
                }
            if (spending.isNotEmpty())
                item {
                    Text(
                        stringResource(R.string.label_shared_spending),
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
            items(spending, key = { "shared:${it.id}" }) { e ->
                FinanceRow(e, state) { onEdit("expense", e) }
            }
        } else if (tab == 1) {
            item {
                Text(
                    stringResource(R.string.label_total_expenses) + " · " + cnyDisplay(stats.total),
                    style = MaterialTheme.typography.titleLarge,
                )
                members(state).forEach { user ->
                    Text(memberName(state, user) + " · " + cnyDisplay(stats.personal[user] ?: 0))
                }
                Text(
                    stringResource(R.string.label_shared_reserves) +
                        " · " +
                        cnyDisplay(stats.shared)
                )
                TextButton(onClick = { onEdit("events", null) }) {
                    Text(stringResource(R.string.label_date_events))
                }
                Choice(
                    R.string.label_payment,
                    funding,
                    listOf(
                        "all" to stringResource(R.string.filter_all),
                        "reserves" to stringResource(R.string.label_shared_reserves),
                        "me" to stringResource(R.string.payment_me),
                        "partner" to stringResource(R.string.payment_partner),
                        "equalSplit" to stringResource(R.string.payment_aa),
                    ),
                    { funding = it },
                )
                Choice(
                    R.string.label_status,
                    status,
                    listOf(
                        "all" to stringResource(R.string.filter_all),
                        "provisional" to stringResource(R.string.status_provisional),
                        "reconciled" to stringResource(R.string.status_reconciled),
                        "skipped" to stringResource(R.string.status_skipped),
                    ),
                    { status = it },
                )
                Choice(
                    R.string.label_source,
                    source,
                    listOf(
                        "all" to stringResource(R.string.filter_all),
                        "standalone" to stringResource(R.string.label_standalone),
                        "date" to stringResource(R.string.label_date_event),
                        "bill" to stringResource(R.string.tab_bills),
                    ),
                    { source = it },
                )
                Input(category, { category = it }, R.string.label_category_filter)
            }
            val expenses =
                s.of("expense")
                    .filter { e ->
                        e.deletedAt == null &&
                            inPeriod(e) &&
                            (funding == "all" ||
                                Payment.from(e.fields.data("payment")).let { p ->
                                    when (funding) {
                                        "me" -> p.kind == "personal" && me in p.userIds
                                        "partner" -> p.kind == "personal" && me !in p.userIds
                                        else -> p.kind == funding
                                    }
                                }) &&
                            (status == "all" || e.fields.text("status") == status) &&
                            (category.isBlank() || e.fields.text("category") == category) &&
                            when (source) {
                                "bill" -> e.fields.id("billId") != null
                                "date" -> e.fields.id("eventId") != null
                                "standalone" ->
                                    e.fields.id("billId") == null && e.fields.id("eventId") == null
                                else -> true
                            }
                    }
                    .sortedByDescending { CivilDate.from(it.fields.data("date")) }
            if (expenses.isEmpty()) item { Text(stringResource(R.string.empty_expenses)) }
            items(expenses, key = { it.id }) { e -> FinanceRow(e, state) { onEdit("expense", e) } }
            val categories =
                expenses
                    .filter { it.fields.text("status") != "skipped" }
                    .groupBy { it.fields.text("category").orEmpty() }
            items(categories.keys.sorted()) { c ->
                Text(
                    c.ifBlank { stringResource(R.string.label_uncategorized) } +
                        " · " +
                        cnyDisplay(
                            Money.sum(
                                categories.getValue(c).map {
                                    Amount.from(it.fields.data("amount")).finalCNYMinor
                                }
                            )
                        )
                )
            }
        } else {
            val bills =
                s.of("recurringBill")
                    .filter { it.deletedAt == null }
                    .sortedBy { it.fields.text("title") }
            if (bills.isEmpty()) item { Text(stringResource(R.string.empty_bills)) }
            items(bills, key = { it.id }) { bill ->
                val next = FinanceMonth.at(state.now, bill.fields.text("zone")!!).next
                val o = FinanceProjection.occurrence(bill, next, s)
                OutlinedCard(
                    onClick = { onEdit("recurringBill", bill) },
                    modifier = Modifier.fillMaxWidth().testTag("bill.${bill.id}"),
                ) {
                    Column(
                        Modifier.padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            bill.fields.text("title").orEmpty(),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(stringResource(R.string.bill_day, bill.fields.number("day") ?: 1))
                        Text(next.iso + " · " + cnyDisplay(o.amount.finalCNYMinor))
                        Text(
                            stringResource(
                                if (o.active) R.string.status_active else R.string.status_paused
                            )
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun FinanceRow(e: ProjectedEntity, s: TogetherRepository.State, onClick: () -> Unit) {
    OutlinedCard(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().testTag("finance.record.${e.id}"),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                e.fields.text("title") ?: memberName(s, e.fields.id("depositedBy")!!),
                style = MaterialTheme.typography.titleMedium,
            )
            val amount = Amount.from(e.fields.data("amount"))
            Text(cnyDisplay(amount.finalCNYMinor), style = MaterialTheme.typography.titleLarge)
            if (amount.currencyCode != "CNY")
                Text(
                    Money.string(amount.originalMinor, amount.currencyCode) +
                        " " +
                        amount.currencyCode
                )
            Text(CivilDate.from(e.fields.data("date")).iso)
            e.fields.text("status")?.let {
                Text(
                    stringResource(
                        when (it) {
                            "provisional" -> R.string.status_provisional
                            "skipped" -> R.string.status_skipped
                            else -> R.string.status_reconciled
                        }
                    )
                )
            }
        }
    }
}

@Composable
internal fun FinanceForm(
    kind: String,
    entry: ProjectedEntity?,
    state: TogetherRepository.State,
    repository: TogetherRepository,
    onClose: () -> Unit,
    onError: (String) -> Unit,
    perform: (suspend () -> Unit) -> Unit,
    onForecast: () -> Unit,
) {
    val forecast = kind == "forecast"
    val isBill = kind == "recurringBill"
    val isDeposit = kind in setOf("reserveEntry", "opening")
    val isEvent = kind == "dateEvent"
    val zone =
        entry?.fields?.text("zone")
            ?: state.authorization?.archive?.genesis?.body?.sharedTimeZoneIdentifier
            ?: ZoneId.systemDefault().id
    var month by rememberSaveable {
        mutableStateOf(
            FinanceMonth.at(state.now, zone)
                .let { current ->
                    if (forecast && entry != null) {
                        val due = FinanceProjection.occurrence(entry, current, state.snapshot)
                        val candidate =
                            if (
                                FinancialCalendar.instant(
                                    due.day,
                                    zone,
                                    entry.fields.number("minute")?.toInt(),
                                ) > state.now
                            )
                                current
                            else current.next
                        maxOf(candidate, FinanceMonth.from(entry.fields.data("startMonth")))
                    } else if (entry != null && isBill) current.next else current
                }
                .iso
        )
    }
    val occurrence =
        if ((forecast || isBill) && entry != null)
            runCatching {
                    FinanceProjection.occurrence(entry, FinanceMonth.parse(month), state.snapshot)
                }
                .getOrNull()
        else null
    val baselineDefaults = remember(entry?.id, month) { occurrence }
    val amount =
        remember(entry?.id, month) {
            AmountDraft(
                occurrence?.amount ?: entry?.fields?.optionalData("amount")?.let(Amount::from)
            )
        }
    var payment by
        remember(entry?.id, month) {
            mutableStateOf(
                occurrence?.payment
                    ?: entry?.fields?.optionalData("payment")?.let(Payment::from)
                    ?: Payment("reserves", emptyList())
            )
        }
    var title by rememberSaveable { mutableStateOf(entry?.fields?.text("title").orEmpty()) }
    var notes by rememberSaveable { mutableStateOf(entry?.fields?.text("notes").orEmpty()) }
    var category by rememberSaveable { mutableStateOf(entry?.fields?.text("category").orEmpty()) }
    var date by rememberSaveable {
        mutableStateOf(
            entry?.fields?.optionalData("date")?.let(CivilDate::from)?.iso
                ?: dayKey(state.now, zone)
        )
    }
    var owner by rememberSaveable {
        mutableStateOf(entry?.fields?.id("depositedBy") ?: state.descriptor!!.userId)
    }
    var event by rememberSaveable { mutableStateOf(entry?.fields?.id("eventId") ?: "") }
    var day by rememberSaveable { mutableIntStateOf((entry?.fields?.number("day") ?: 1).toInt()) }
    var timeZone by rememberSaveable { mutableStateOf(zone) }
    FormSheet(
        when {
            forecast -> R.string.action_override_occurrence
            isDeposit ->
                if (kind == "opening") R.string.action_opening_balance else R.string.action_deposit
            isBill -> R.string.action_recurring_bill
            isEvent -> R.string.label_date_event
            else -> R.string.action_expense
        },
        onClose,
        "finance.editor",
        onSave = {
            repository.execute {
                when {
                    isEvent -> listOf(dateEvent(entry?.id, title, CivilDate.parse(date), notes))
                    isDeposit ->
                        listOf(
                            deposit(
                                entry?.id,
                                amount.amount(),
                                owner,
                                CivilDate.parse(date),
                                notes,
                                kind == "opening",
                                entry,
                            )
                        )
                    forecast ->
                        listOf(
                            this.forecast(
                                entry!!.id,
                                FinanceMonth.parse(month),
                                amount.amount(),
                                payment,
                            )
                        )
                    isBill && entry == null ->
                        listOf(bill(title, amount.amount(), payment, day, timeZone, category))
                    isBill ->
                        billDefaults(
                            entry!!.id,
                            title,
                            category,
                            amount.amount(),
                            payment,
                            entry,
                            baselineDefaults,
                        )
                    else ->
                        listOf(
                            expense(
                                entry?.id,
                                title,
                                amount.amount(),
                                payment,
                                CivilDate.parse(date),
                                category,
                                notes,
                                event.ifBlank { null },
                                entry,
                            )
                        )
                }
            }
        },
        onError = onError,
        enabled = state.canWrite,
    ) {
        if (!isDeposit && !forecast)
            Input(title, { title = it }, R.string.label_title, "finance.title")
        if (!isEvent) {
            AmountFields(amount)
            if (!isDeposit) {
                PaymentFields(payment, state) { payment = it }
                if (payment.kind == "equalSplit")
                    runCatching { payment.allocations(amount.amount().finalCNYMinor) }
                        .getOrNull()
                        ?.forEach { (user, share) ->
                            Text(memberName(state, user) + " · " + cnyDisplay(share))
                        }
            }
        }
        if (isDeposit)
            Choice(
                R.string.label_deposited_by,
                owner,
                members(state).map { it to memberName(state, it) },
                { owner = it },
            )
        if (!isBill && !forecast) {
            if (entry?.fields?.id("billId") == null) DateField(date, { date = it }) else Text(date)
        }
        if (isBill && entry == null) {
            DayWheel(day) { day = it }
            Input(timeZone, { timeZone = it }, R.string.label_time_zone)
        }
        if (isBill && entry != null) {
            TextButton(onClick = onForecast) {
                Text(stringResource(R.string.action_override_occurrence))
            }
            Text(stringResource(R.string.guidance_next_month))
            Text(stringResource(R.string.bill_day, day))
            TextButton(
                onClick = {
                    perform {
                        repository.execute {
                            listOf(
                                billActive(
                                    entry.id,
                                    !FinanceProjection.occurrence(
                                            entry,
                                            FinanceMonth.at(state.now, zone).next,
                                            state.snapshot,
                                        )
                                        .active,
                                )
                            )
                        }
                    }
                }
            ) {
                Text(stringResource(R.string.action_toggle_bill))
            }
        }
        if (forecast) Input(month, { month = it }, R.string.label_occurrence_month)
        if (!isDeposit && !isEvent && !forecast)
            Input(category, { category = it }, R.string.label_category)
        if (!isBill && !forecast) Input(notes, { notes = it }, R.string.label_notes, lines = 3)
        if (kind == "expense")
            Choice(
                R.string.label_date_event,
                event,
                listOf("" to stringResource(R.string.label_none)) +
                    state.snapshot
                        .of("dateEvent")
                        .filter { it.deletedAt == null }
                        .map { it.id to it.fields.text("title").orEmpty() },
                { event = it },
            )
        if (kind == "expense" && entry != null && entry.fields.text("status") == "provisional") {
            Button(
                onClick = {
                    perform {
                        repository.execute { listOf(reviewExpense(entry.id, false, entry)) }
                        onClose()
                    }
                },
                modifier = Modifier.testTag("expense.confirm"),
            ) {
                Text(stringResource(R.string.action_confirm_bill))
            }
            TextButton(
                onClick = {
                    perform {
                        repository.execute { listOf(reviewExpense(entry.id, true, entry)) }
                        onClose()
                    }
                },
                modifier = Modifier.testTag("expense.skip"),
            ) {
                Text(stringResource(R.string.action_skip_bill))
            }
        }
        if (entry != null && !forecast)
            TextButton(
                onClick = {
                    perform {
                        repository.execute { listOf(delete(entry.id)) }
                        onClose()
                    }
                },
                modifier = Modifier.testTag("finance.delete"),
            ) {
                Text(stringResource(R.string.action_delete))
            }
    }
}

@Composable
internal fun FinanceSettings(
    state: TogetherRepository.State,
    repository: TogetherRepository,
    onClose: () -> Unit,
    onError: (String) -> Unit,
    onCards: () -> Unit,
) {
    var owner by rememberSaveable { mutableStateOf("") }
    val existing = state.snapshot.entities[stableId("finance-settings:${owner.ifBlank{"shared"}}")]
    val baseline = remember(owner) { existing }
    var day by remember(owner) { mutableIntStateOf((existing?.fields?.number("day") ?: 1).toInt()) }
    var zone by
        remember(owner) {
            mutableStateOf(
                existing?.fields?.text("zone")
                    ?: state.authorization?.archive?.genesis?.body?.sharedTimeZoneIdentifier
                    ?: ZoneId.systemDefault().id
            )
        }
    var salary by
        remember(owner) { mutableStateOf(existing?.fields?.number("salaryDay")?.toString() ?: "") }
    var deposit by
        remember(owner) { mutableStateOf(existing?.fields?.number("depositDay")?.toString() ?: "") }
    FormSheet(
        R.string.action_finance_settings,
        onClose,
        "finance.settings.sheet",
        onSave = {
            repository.execute {
                listOf(
                    cycle(
                        owner.ifBlank { null },
                        day,
                        zone,
                        salary.takeIf { it.isNotBlank() }?.toInt(),
                        deposit.takeIf { it.isNotBlank() }?.toInt(),
                        baseline,
                    )
                )
            }
        },
        onError = onError,
    ) {
        Choice(
            R.string.label_financial_cycle,
            owner,
            listOf(
                "" to stringResource(R.string.label_shared_cycle),
                state.descriptor!!.userId to stringResource(R.string.label_my_cycle),
            ),
            { owner = it },
        )
        DayWheel(day) { day = it }
        Input(zone, { zone = it }, R.string.label_time_zone)
        if (owner.isNotBlank()) {
            Input(salary, { salary = it }, R.string.label_salary_day)
            Input(deposit, { deposit = it }, R.string.label_planned_deposit)
        }
        TextButton(onClick = onCards, modifier = Modifier.testTag("cards.open")) {
            Text(stringResource(R.string.label_payment_methods))
        }
    }
}

@Composable
internal fun CardsSheet(
    state: TogetherRepository.State,
    repository: TogetherRepository,
    onClose: () -> Unit,
    onError: (String) -> Unit,
    perform: (suspend () -> Unit) -> Unit,
) {
    var editing by rememberSaveable { mutableStateOf(false) }
    var cardId by rememberSaveable { mutableStateOf<String?>(null) }
    var bank by rememberSaveable { mutableStateOf("") }
    var name by rememberSaveable { mutableStateOf("") }
    var four by rememberSaveable { mutableStateOf("") }
    var kind by rememberSaveable { mutableStateOf("debit") }
    var holder by rememberSaveable { mutableStateOf(state.descriptor!!.userId) }
    var currency by rememberSaveable { mutableStateOf("CNY") }
    var shared by rememberSaveable { mutableStateOf(false) }
    val save: (suspend () -> Unit)? =
        if (!editing) null
        else {
            {
                repository.saveCard(
                    buildJsonObject {
                        put("id", cardId ?: uid())
                        put("ownerId", state.descriptor!!.userId)
                        put("holderId", holder)
                        put("bankName", bank)
                        put("name", name)
                        put("cardKind", kind)
                        put("lastFour", four)
                        put("currencyCode", currency)
                        put("isShared", shared)
                    }
                )
            }
        }
    FormSheet(
        R.string.label_payment_methods,
        onClose,
        "cards.sheet",
        onSave = save,
        onError = onError,
    ) {
        if (editing) {
            Input(bank, { bank = it }, R.string.label_bank)
            Input(name, { name = it }, R.string.label_card_name)
            Input(
                four,
                { if (it.length <= 4 && it.all(Char::isDigit)) four = it },
                R.string.label_last_four,
                "card.lastFour",
            )
            Choice(
                R.string.label_holder,
                holder,
                members(state).map { it to memberName(state, it) },
                { holder = it },
            )
            Choice(
                R.string.label_card_kind,
                kind,
                listOf(
                    "debit" to stringResource(R.string.label_debit),
                    "credit" to stringResource(R.string.label_credit),
                ),
                { kind = it },
            )
            CurrencyWheel(currency) { currency = it }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = shared, onCheckedChange = { shared = it })
                Text(stringResource(R.string.label_shared_visibility))
            }
            if (!shared && visibleCards(state).any {
                    it["id"]?.jsonPrimitive?.content == cardId &&
                        it["isShared"]?.jsonPrimitive?.booleanOrNull == true
                }) {
                Text(
                    stringResource(R.string.guidance_card_history),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        } else {
            Button(
                onClick = {
                    editing = true
                    cardId = null
                    bank = ""
                    name = ""
                    four = ""
                    shared = false
                }
            ) {
                Text(stringResource(R.string.action_add_card))
            }
            visibleCards(state).forEach { card ->
                val owner = card.getValue("ownerId").jsonPrimitive.content
                OutlinedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text(
                            card.getValue("name").jsonPrimitive.content +
                                " · " +
                                card.getValue("lastFour").jsonPrimitive.content
                        )
                        Text(card.getValue("bankName").jsonPrimitive.content)
                        Text(memberName(state, card.getValue("holderId").jsonPrimitive.content))
                        if (owner == state.descriptor!!.userId) {
                            Row {
                                TextButton(
                                    onClick = {
                                        cardId = card.getValue("id").jsonPrimitive.content
                                        bank = card.getValue("bankName").jsonPrimitive.content
                                        name = card.getValue("name").jsonPrimitive.content
                                        four = card.getValue("lastFour").jsonPrimitive.content
                                        holder = card.getValue("holderId").jsonPrimitive.content
                                        kind = card.getValue("cardKind").jsonPrimitive.content
                                        currency =
                                            card["currencyCode"]?.jsonPrimitive?.content ?: "CNY"
                                        shared = card.getValue("isShared").jsonPrimitive.boolean
                                        editing = true
                                    }
                                ) {
                                    Text(stringResource(R.string.action_edit))
                                }
                                TextButton(
                                    onClick = {
                                        perform {
                                            repository.deleteCard(
                                                card.getValue("id").jsonPrimitive.content
                                            )
                                        }
                                    }
                                ) {
                                    Text(stringResource(R.string.action_delete))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun DateEventsSheet(
    state: TogetherRepository.State,
    onClose: () -> Unit,
    onEdit: (ProjectedEntity?) -> Unit,
) {
    FormSheet(R.string.label_date_events, onClose, "finance.events") {
        Button(onClick = { onEdit(null) }) { Text(stringResource(R.string.action_add_date_event)) }
        state.snapshot
            .of("dateEvent")
            .filter { it.deletedAt == null }
            .sortedByDescending { CivilDate.from(it.fields.data("date")) }
            .forEach { event ->
                OutlinedCard(onClick = { onEdit(event) }, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text(
                            event.fields.text("title").orEmpty(),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(CivilDate.from(event.fields.data("date")).iso)
                    }
                }
            }
    }
}
