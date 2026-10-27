package com.together.android.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.together.android.R
import com.together.domain.*
import com.together.protocol.*
import java.time.*
import kotlinx.coroutines.*
import kotlinx.serialization.json.*

@Composable
internal fun FormSheet(
    title: Int,
    onClose: () -> Unit,
    tag: String = "form.sheet",
    onSave: (suspend () -> Unit)? = null,
    onError: (String) -> Unit = {},
    enabled: Boolean = true,
    saveLabel: Int = R.string.action_save,
    dismissible: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    Dialog(
        onDismissRequest = { if (!busy && dismissible) onClose() },
        properties = DialogProperties(usePlatformDefaultWidth = false,
            dismissOnBackPress = dismissible && !busy, dismissOnClickOutside = dismissible && !busy),
    ) {
        Surface(
            shape = MaterialTheme.shapes.large,
            tonalElevation = 4.dp,
            modifier =
                Modifier.widthIn(max = 660.dp)
                    .fillMaxWidth(.96f)
                    .fillMaxHeight(.92f)
                    .imePadding()
                    .testTag(tag),
        ) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(stringResource(title), style = MaterialTheme.typography.headlineSmall)
                Column(
                    Modifier.weight(1f).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    content = content,
                )
                HorizontalDivider()
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (dismissible) TextButton(
                        onClick = onClose,
                        enabled = !busy,
                        modifier = Modifier.testTag("sheet.close"),
                    ) {
                        Text(
                            stringResource(
                                if (onSave == null) R.string.action_close
                                else R.string.action_cancel
                            )
                        )
                    }
                    if (onSave != null)
                        Button(
                            enabled = enabled && !busy,
                            modifier =
                                Modifier.testTag(
                                    if (tag == "task.editor") "task.save" else "sheet.save"
                                ),
                            onClick = {
                                if (!busy) {
                                    busy = true
                                    scope.launch {
                                        try {
                                            onSave()
                                            onClose()
                                        } catch (e: Exception) {
                                            if (e is CancellationException) throw e
                                            onError(
                                                (e as? ProtocolException)?.code
                                                    ?: "LOCAL_OPERATION_FAILED"
                                            )
                                        } finally {
                                            busy = false
                                        }
                                    }
                                }
                            },
                        ) {
                            Text(stringResource(saveLabel))
                        }
                }
            }
        }
    }
}

@Composable
internal fun Input(
    value: String,
    onChange: (String) -> Unit,
    label: Int,
    tag: String = "",
    lines: Int = 1,
    enabled: Boolean = true,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(stringResource(label)) },
        enabled = enabled,
        modifier = Modifier.fillMaxWidth().testTag(tag),
        singleLine = lines == 1,
        minLines = lines,
        maxLines = maxOf(lines, 6),
    )
}

@Composable
internal fun Choice(
    label: Int,
    value: String,
    options: List<Pair<String, String>>,
    onChange: (String) -> Unit,
    tag: String = "choice",
) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        Text(stringResource(label), style = MaterialTheme.typography.labelMedium)
        Box {
            OutlinedButton(
                onClick = { expanded = true },
                modifier = Modifier.fillMaxWidth().testTag(tag),
            ) {
                Text(
                    options.firstOrNull { it.first == value }?.second
                        ?: stringResource(R.string.label_none)
                )
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                options.forEach { (id, text) ->
                    DropdownMenuItem(
                        text = { Text(text) },
                        onClick = {
                            onChange(id)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DateField(
    value: String,
    onChange: (String) -> Unit,
    label: Int = R.string.label_date,
    nullable: Boolean = false,
) {
    var choosing by remember { mutableStateOf(false) }
    Column {
        Text(stringResource(label), style = MaterialTheme.typography.labelMedium)
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = { choosing = true }) {
                Text(value.ifBlank { stringResource(R.string.label_none) })
            }
            if (nullable && value.isNotBlank())
                TextButton(onClick = { onChange("") }) {
                    Text(stringResource(R.string.action_clear))
                }
        }
    }
    if (choosing) {
        val selected =
            runCatching {
                    LocalDate.parse(value).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
                }
                .getOrNull()
        val state =
            rememberDatePickerState(initialSelectedDateMillis = selected, yearRange = 1900..3000)
        DatePickerDialog(
            onDismissRequest = { choosing = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        state.selectedDateMillis?.let {
                            onChange(
                                Instant.ofEpochMilli(it)
                                    .atZone(ZoneOffset.UTC)
                                    .toLocalDate()
                                    .toString()
                            )
                        }
                        choosing = false
                    }
                ) {
                    Text(stringResource(R.string.action_save))
                }
            },
            dismissButton = {
                TextButton(onClick = { choosing = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        ) {
            DatePicker(state = state)
        }
    }
}

@Composable
internal fun DayWheel(day: Int, onChange: (Int) -> Unit) {
    val state = rememberLazyListState(initialFirstVisibleItemIndex = maxOf(day - 2, 0))
    Column {
        Text(stringResource(R.string.label_month_day), style = MaterialTheme.typography.labelMedium)
        LazyRow(
            state = state,
            flingBehavior = rememberSnapFlingBehavior(state),
            modifier = Modifier.fillMaxWidth().height(60.dp).testTag("day.wheel"),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(31) { index ->
                val value = index + 1
                FilterChip(
                    selected = value == day,
                    onClick = { onChange(value) },
                    label = { Text(value.toString()) },
                )
            }
        }
    }
}

@Composable
internal fun CurrencyWheel(currency: String, onChange: (String) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val locale = androidx.compose.ui.platform.LocalConfiguration.current.locales[0]
    val names =
        mapOf(
            "CNY" to R.string.currency_cny,
            "USD" to R.string.currency_usd,
            "EUR" to R.string.currency_eur,
            "JPY" to R.string.currency_jpy,
            "GBP" to R.string.currency_gbp,
            "HKD" to R.string.currency_hkd,
            "KRW" to R.string.currency_krw,
            "SGD" to R.string.currency_sgd,
        )
    val labels =
        Money.currencies.mapValues { (code, info) ->
            info.getValue("symbol").jsonPrimitive.content +
                " " +
                code +
                " — " +
                (names[code]?.let { context.getString(it) }
                    ?: runCatching {
                        val name = java.util.Currency.getInstance(code)
                            .getDisplayName(locale)
                        if (locale.language == "zh" &&
                            name.none { it in '\u4e00'..'\u9fff' }) code else name
                    }.getOrElse {
                        if (locale.language == "zh") code
                        else info.getValue("name").jsonPrimitive.content
                    })
        }
    var expanded by remember { mutableStateOf(false) }
    var search by rememberSaveable { mutableStateOf("") }
    OutlinedButton(onClick = { expanded = true }, modifier = Modifier.testTag("currency.open")) {
        Text(labels[currency].orEmpty())
    }
    if (expanded)
        FormSheet(R.string.label_currency, onClose = { expanded = false }, tag = "currency.sheet") {
            Input(search, { search = it }, R.string.action_search, "currency.search")
            val common = listOf("CNY", "USD", "EUR", "JPY", "GBP", "HKD", "KRW", "SGD")
            val codes =
                (common + Money.precisions.keys.sorted()).distinct().filter {
                    search.isBlank() ||
                        it.contains(search, true) ||
                        labels[it].orEmpty().contains(search, true)
                }
            val state = rememberLazyListState()
            LazyColumn(
                state = state,
                flingBehavior = rememberSnapFlingBehavior(state),
                modifier = Modifier.fillMaxWidth().height(300.dp).testTag("currency.wheel"),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                items(codes, key = { it }) { code ->
                    TextButton(
                        onClick = {
                            onChange(code)
                            expanded = false
                        },
                        modifier = Modifier.fillMaxWidth().height(48.dp).testTag("currency.$code"),
                    ) {
                        Text(
                            labels[code].orEmpty(),
                            style =
                                if (code == currency) MaterialTheme.typography.titleLarge
                                else MaterialTheme.typography.bodyLarge,
                        )
                    }
                }
            }
        }
}

internal class AmountDraft(amount: Amount? = null) {
    var currency by mutableStateOf(amount?.currencyCode ?: "CNY")
    var original by
        mutableStateOf(amount?.let { Money.string(it.originalMinor, it.currencyCode) } ?: "")
    var cny by mutableStateOf(amount?.let { Money.string(it.finalCNYMinor) } ?: "")
    var rate by
        mutableStateOf(
            amount?.exchangeRate?.get("cnyPerOriginalUnit")?.jsonPrimitive?.content ?: ""
        )
    var source by mutableStateOf(amount?.exchangeRate?.get("source")?.jsonPrimitive?.content ?: "")
    var quoteDate by
        mutableStateOf(
            amount?.exchangeRate?.get("quotedOn")?.let(CivilDate::from)?.iso
                ?: LocalDate.now().toString()
        )

    fun amount(): Amount {
        val r =
            if (rate.isBlank()) null
            else
                kotlinx.serialization.json.buildJsonObject {
                    put("cnyPerOriginalUnit", kotlinx.serialization.json.JsonPrimitive(rate))
                    put("source", kotlinx.serialization.json.JsonPrimitive(source))
                    put("quotedOn", CivilDate.parse(quoteDate).json())
                }
        return Amount.create(original, currency, cny.ifBlank { null }, r)
    }
}

@Composable
internal fun AmountFields(d: AmountDraft) {
    CurrencyWheel(d.currency) {
        if (it != d.currency) {
            d.currency = it
            d.original = ""
            d.cny = ""
            d.rate = ""
            d.source = ""
        }
    }
    Input(d.original, { d.original = it }, R.string.label_original_amount, "amount.original")
    if (d.currency != "CNY") {
        Input(d.cny, { d.cny = it }, R.string.label_final_cny, "amount.cny")
        Input(d.rate, { d.rate = it }, R.string.label_exchange_rate, "amount.rate")
        Input(d.source, { d.source = it }, R.string.label_rate_source)
        DateField(d.quoteDate, { d.quoteDate = it }, R.string.label_rate_date)
    }
    runCatching { d.amount() }
        .getOrNull()
        ?.let { Text(cnyDisplay(it.finalCNYMinor), style = MaterialTheme.typography.titleLarge) }
}
