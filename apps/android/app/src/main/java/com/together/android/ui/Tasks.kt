package com.together.android.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.together.android.R
import com.together.android.data.TogetherRepository
import com.together.domain.*
import com.together.protocol.*
import java.time.*

@Composable
internal fun TasksPage(
    state: TogetherRepository.State,
    filter: String,
    onFilter: (String) -> Unit,
    onEdit: (ProjectedEntity) -> Unit,
    onComplete: (ProjectedEntity) -> Unit,
    onDelete: (ProjectedEntity) -> Unit,
) {
    val selectedFilter = if (filter == "completed") "completed" else "pending"
    val tasks = BusinessQueries.tasks(state.snapshot, selectedFilter, state.now)
    Column(
        Modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            listOf(
                    "pending" to R.string.filter_pending,
                    "completed" to R.string.filter_completed,
                )
                .forEachIndexed { i, p ->
                    SegmentedButton(
                        selected = selectedFilter == p.first,
                        onClick = { onFilter(p.first) },
                        shape = SegmentedButtonDefaults.itemShape(i, 2),
                        modifier = Modifier.testTag("tasks.${p.first}"),
                    ) {
                        Text(stringResource(p.second), maxLines = 1)
                    }
                }
        }
        if (tasks.isEmpty())
            Text(
                stringResource(R.string.empty_tasks),
                modifier = Modifier.padding(vertical = 32.dp).testTag("tasks.empty"),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(bottom = 24.dp),
            modifier = Modifier.testTag("tasks.list"),
        ) {
            items(tasks, key = { it.id }) { task ->
                val completionDescription =
                    stringResource(
                        if (task.fields.text("status") == "completed") R.string.action_reopen
                        else R.string.action_complete
                    ) + ": " + task.fields.text("title").orEmpty()
                OutlinedCard(Modifier.fillMaxWidth().animateItem()) {
                    Row(
                        Modifier.fillMaxWidth().padding(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Checkbox(
                            checked = task.fields.text("status") == "completed",
                            enabled = state.canWrite && (task.fields.date("availableAt") ?: Long.MIN_VALUE) <= state.now.toEpochMilli(),
                            onCheckedChange = { onComplete(task) },
                            modifier =
                                Modifier.testTag("task.complete.${task.id}").semantics {
                                    contentDescription = completionDescription
                                },
                        )
                        Column(
                            Modifier.weight(1f)
                                .clickable { onEdit(task) }
                                .padding(vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(
                                task.fields.text("title").orEmpty(),
                                style = MaterialTheme.typography.titleMedium,
                            )
                            task.fields
                                .text("notes")
                                ?.takeIf { it.isNotBlank() }
                                ?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                            task.fields.date("dueAt")?.let {
                                Text(
                                    Instant.ofEpochMilli(it)
                                        .atZone(ZoneId.systemDefault())
                                        .toLocalDateTime()
                                        .toString(),
                                    style = MaterialTheme.typography.labelMedium,
                                )
                            }
                            task.fields.id("assignedTo")?.let {
                                Text(
                                    memberName(state, it),
                                    style = MaterialTheme.typography.labelMedium,
                                )
                            }
                        }
                        IconButton(
                            onClick = { onDelete(task) },
                            enabled = state.canWrite,
                            modifier = Modifier.testTag("task.delete.${task.id}"),
                        ) {
                            Icon(Icons.Outlined.Delete, stringResource(R.string.action_delete))
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun TaskForm(
    task: ProjectedEntity?,
    state: TogetherRepository.State,
    repository: TogetherRepository,
    onClose: () -> Unit,
    onError: (String) -> Unit,
    onNext: () -> Unit,
) {
    var title by
        rememberSaveable(task?.id) { mutableStateOf(task?.fields?.text("title").orEmpty()) }
    var notes by
        rememberSaveable(task?.id) { mutableStateOf(task?.fields?.text("notes").orEmpty()) }
    var assignee by rememberSaveable { mutableStateOf(task?.fields?.id("assignedTo") ?: "") }
    val oldDue =
        task?.fields?.date("dueAt")?.let { Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()) }
    var day by rememberSaveable { mutableStateOf(oldDue?.toLocalDate()?.toString() ?: "") }
    var time by rememberSaveable { mutableStateOf(oldDue?.toLocalTime()?.toString() ?: "09:00") }
    val rule = remember(task?.id) { state.snapshot.entities[task?.fields?.id("recurrenceRuleId")] }
    var mode by rememberSaveable { mutableStateOf(rule?.fields?.text("mode") ?: "none") }
    var unit by rememberSaveable { mutableStateOf(rule?.fields?.text("unit") ?: "day") }
    var interval by rememberSaveable {
        mutableStateOf((rule?.fields?.number("interval") ?: 1).toString())
    }
    var zone by rememberSaveable {
        mutableStateOf(rule?.fields?.text("timeZoneIdentifier") ?: ZoneId.systemDefault().id)
    }
    FormSheet(
        if (task == null) R.string.action_new_task else R.string.action_edit,
        onClose,
        "task.editor",
        onSave = {
            val due =
                if (day.isBlank()) null
                else if (
                    day == oldDue?.toLocalDate()?.toString() &&
                        time == oldDue.toLocalTime().toString()
                )
                    task?.fields?.date("dueAt")
                else
                    LocalDateTime.of(LocalDate.parse(day), LocalTime.parse(time))
                        .atZone(ZoneId.systemDefault())
                        .toInstant()
                        .toEpochMilli()
            repository.execute {
                this.task(
                    task?.id,
                    title,
                    notes,
                    assignee.ifBlank { null },
                    due,
                    if (mode == "none") null
                    else BusinessCommands.Repeat(mode, unit, interval.toInt(), zone),
                    task,
                    rule,
                )
            }
        },
        onError = onError,
        enabled = state.canWrite && title.isNotBlank() && title.graphemeCount() <= 200,
    ) {
        Input(title, { title = it }, R.string.label_title, "task.title")
        Input(notes, { notes = it }, R.string.label_notes, "task.notes", 3)
        Choice(
            R.string.label_assignee,
            assignee,
            listOf("" to stringResource(R.string.label_unassigned)) +
                members(state).map { it to memberName(state, it) },
            { assignee = it },
        )
        DateField(day, { day = it }, R.string.label_due_date, true)
        if (day.isNotBlank()) Input(time, { time = it }, R.string.label_time)
        Choice(
            R.string.label_recurrence,
            mode,
            listOf(
                "none" to stringResource(R.string.label_none),
                "regular" to stringResource(R.string.label_regular),
                "flexible" to stringResource(R.string.label_flexible),
            ),
            { mode = it },
            "task.recurrence",
        )
        if (mode == "regular") {
            Choice(
                R.string.label_unit,
                unit,
                listOf(
                    "day" to stringResource(R.string.label_daily),
                    "week" to stringResource(R.string.label_weekly),
                    "month" to stringResource(R.string.label_monthly),
                ),
                { unit = it },
            )
            Input(interval, { interval = it }, R.string.label_every_n)
        }
        if (mode != "none") Input(zone, { zone = it }, R.string.label_time_zone)
        if (mode == "flexible" && task != null)
            TextButton(onClick = onNext) { Text(stringResource(R.string.action_set_next)) }
    }
}

@Composable
internal fun NextTimeForm(
    task: ProjectedEntity,
    repository: TogetherRepository,
    onClose: () -> Unit,
    onError: (String) -> Unit,
    complete: Boolean,
) {
    val existingNext =
        task.fields.date("nextAt")?.let { Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()) }
    var day by rememberSaveable { mutableStateOf(existingNext?.toLocalDate()?.toString() ?: "") }
    var time by rememberSaveable {
        mutableStateOf(existingNext?.toLocalTime()?.toString() ?: "09:00")
    }
    FormSheet(
        R.string.action_set_next,
        onClose,
        "task.next",
        onSave = {
            val next =
                if (day.isBlank()) null
                else if (
                    day == existingNext?.toLocalDate()?.toString() &&
                        time == existingNext.toLocalTime().toString()
                )
                    task.fields.date("nextAt")
                else
                    LocalDateTime.of(LocalDate.parse(day), LocalTime.parse(time))
                        .atZone(ZoneId.systemDefault())
                        .toInstant()
                        .toEpochMilli()
            repository.execute {
                if (complete) completion(task, next)
                else listOf(setNext(task, next ?: throw ProtocolException("INVALID_DATE")))
            }
        },
        onError = onError,
        enabled = complete || day.isNotBlank(),
        saveLabel =
            if (complete && day.isBlank()) R.string.action_complete_later else R.string.action_save,
    ) {
        DateField(day, { day = it }, R.string.action_set_next, true)
        if (day.isNotBlank()) Input(time, { time = it }, R.string.label_time)
    }
}

internal fun members(s: TogetherRepository.State) =
    s.authorization?.members?.sorted() ?: listOfNotNull(s.descriptor?.userId)

@Composable
internal fun memberName(s: TogetherRepository.State, id: String): String =
    s.snapshot.entities[id]?.fields?.text("displayName")
        ?: stringResource(
            if (id == s.descriptor?.userId) R.string.label_you else R.string.label_partner
        )
