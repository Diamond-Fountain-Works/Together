package com.together.domain

import com.together.protocol.*
import java.time.*
import kotlinx.serialization.json.*

fun logData(value: JsonElement) = LogValue.data(Canonical.bytes(value))

fun comparisonValue(fields: Map<String, JsonObject>, key: String): JsonObject? =
    fields[key]
        ?: when (key) {
            "notes",
            "description",
            "category" -> LogValue.string("")
            "relationshipLabel" -> LogValue.string("unknown")
            "assignedTo",
            "dueAt",
            "recurrenceRuleId",
            "eventId",
            "avatarAssetId",
            "avatarData",
            "salaryDay",
            "depositDay",
            "ownerId" -> LogValue.nil
            else -> null
        }

fun logId(id: String?) = id?.let { LogValue.string(uuid(it)) } ?: LogValue.nil

/** UI-independent commands: candidates are replayed and committed atomically by the repository. */
class BusinessCommands(
    val snapshot: Snapshot,
    val context: DomainContext,
    val actor: String,
    val now: Instant,
) {
    init {
        requireProtocol(actor in context.members, "UNAUTHORIZED_ACTOR")
    }

    fun record(
        id: String,
        type: String,
        fields: Map<String, JsonObject>,
        create: Boolean = snapshot.entities[id] == null,
    ): PlannedMutation {
        val previous = snapshot.entities[id]
        requireProtocol(
            previous == null || (previous.base.entityType == type && previous.deletedAt == null),
            "MISSING_RECORD",
        )
        val payload =
            if (create)
                fields +
                    mapOf(
                        "spaceId" to LogValue.string(context.spaceId),
                        "createdBy" to LogValue.string(actor),
                    )
            else fields.filter { previous?.fields?.get(it.key) != it.value }
        return PlannedMutation(id, type, if (create) "create" else "patch", payload)
    }

    fun delete(id: String): PlannedMutation {
        val old =
            snapshot.entities[id]
                ?: snapshot.gifts[id]?.entity
                ?: throw ProtocolException("MISSING_RECORD")
        requireProtocol(
            old.deletedAt == null &&
                old.base.entityType !in setOf("profile", "billRevision", "financeSettings"),
            "INVALID_DELETE",
        )
        if (old.base.entityType == "loveGift")
            requireProtocol(old.fields.id("senderId") == actor, "OWNER_ONLY")
        return PlannedMutation(id, old.base.entityType, "delete", emptyMap())
    }

    data class Repeat(
        val mode: String,
        val unit: String = "day",
        val interval: Int = 1,
        val zone: String,
    )

    fun task(
        id: String?,
        title: String,
        notes: String,
        assignee: String?,
        due: Long?,
        repeat: Repeat?,
        baseline: ProjectedEntity? = null,
        ruleBaseline: ProjectedEntity? = null,
    ): List<PlannedMutation> {
        requireProtocol(
            title.isNotBlank() && title.graphemeCount() <= 200 && notes.graphemeCount() <= 10_000,
            "INVALID_TASK",
        )
        val old = id?.let { snapshot.entities[it] ?: throw ProtocolException("MISSING_RECORD") }
        val taskId = id ?: uid()
        val result = mutableListOf<PlannedMutation>()
        var ruleId: String? = null
        if (repeat != null) {
            ruleId = old?.fields?.id("recurrenceRuleId") ?: uid()
            val rule = snapshot.entities[ruleId]
            val p =
                mapOf(
                    "mode" to LogValue.string(repeat.mode),
                    "unit" to LogValue.string(repeat.unit),
                    "interval" to LogValue.integer(repeat.interval.toLong()),
                    "timeZoneIdentifier" to LogValue.string(repeat.zone),
                    "anchorAt" to
                        LogValue.date(rule?.fields?.date("anchorAt") ?: due ?: now.toEpochMilli()),
                )
            val changedRule =
                if (ruleBaseline != null) p.filter { ruleBaseline.fields[it.key] != it.value }
                else p
            result.add(record(ruleId, "recurrenceRule", changedRule))
        }
        val fields =
            mapOf(
                "title" to LogValue.string(title),
                "notes" to LogValue.string(notes),
                "assignedTo" to logId(assignee),
                "dueAt" to (due?.let(LogValue::date) ?: LogValue.nil),
                "recurrenceRuleId" to logId(ruleId),
            )
        // Compare against the editor's baseline so untouched fields don't overwrite concurrent
        // edits.
        val changed =
            if (baseline != null)
                fields.filter { comparisonValue(baseline.fields, it.key) != it.value }
            else fields
        result.add(record(taskId, "task", changed, old == null))
        return result.filter { it.operationType == "create" || it.payload.isNotEmpty() }
    }

    fun completion(task: ProjectedEntity, next: Long? = null): List<PlannedMutation> {
        requireProtocol(task.base.entityType == "task" && task.deletedAt == null, "MISSING_RECORD")
        val result = mutableListOf<PlannedMutation>()
        if (next != null) result.add(setNext(task, next))
        else if (
            task.fields.text("status") != "completed" &&
                task.fields.date("nextAt") != null &&
                snapshot.entities[task.fields.id("recurrenceRuleId")]?.fields?.text("mode") ==
                    "flexible"
        )
            result.add(record(task.id, "task", mapOf("nextAt" to LogValue.nil), false))
        result.add(
            PlannedMutation(
                task.id,
                "task",
                if (task.fields.text("status") == "completed") "reopenTask" else "completeTask",
                emptyMap(),
            )
        )
        return result
    }

    fun setNext(task: ProjectedEntity, next: Long): PlannedMutation {
        requireProtocol(
            snapshot.entities[task.fields.id("recurrenceRuleId")]?.fields?.text("mode") ==
                "flexible",
            "NOT_FLEXIBLE",
        )
        return record(task.id, "task", mapOf("nextAt" to LogValue.date(next)), false)
    }

    fun grant(
        fulfiller: String,
        beneficiary: String,
        count: Long,
        on: CivilDate,
        notes: String,
    ): PlannedMutation {
        requireProtocol(
            fulfiller in context.members &&
                beneficiary in context.members &&
                fulfiller != beneficiary &&
                count in 1..10_000,
            "INVALID_GRANT",
        )
        return record(
            uid(),
            "wishGrant",
            mapOf(
                "fulfillerId" to logId(fulfiller),
                "beneficiaryId" to logId(beneficiary),
                "quantity" to LogValue.integer(count),
                "grantedOn" to LogValue.string(on.iso),
                "notes" to LogValue.string(notes),
            ),
        )
    }

    fun wish(
        grantId: String,
        title: String,
        description: String,
        id: String? = null,
        baseline: Wish? = null,
    ): PlannedMutation {
        val grant = snapshot.entities[grantId] ?: throw ProtocolException("MISSING_RECORD")
        requireProtocol(
            grant.fields.id("beneficiaryId") == actor && title.isNotBlank(),
            "BENEFICIARY_ONLY",
        )
        if (id == null)
            requireProtocol(
                snapshot.wishes.values.count { it.grantId == grantId && it.status != "conflict" } <
                    (snapshot.grantTotals[grantId] ?: 0),
                "NO_WISH_QUOTA",
            )
        return PlannedMutation(
            id ?: uid(),
            "wishItem",
            if (id == null) "create" else "patch",
            mapOf("title" to LogValue.string(title), "description" to LogValue.string(description))
                .filter {
                    baseline == null ||
                        (if (it.key == "title") LogValue.string(baseline.title)
                        else LogValue.string(baseline.description)) != it.value
                } +
                if (id == null) mapOf("grantId" to logId(grantId), "createdBy" to logId(actor))
                else emptyMap(),
        )
    }

    fun adjustment(grant: String, delta: Long, notes: String) =
        PlannedMutation(
            uid(),
            "grantAdjustment",
            "create",
            mapOf(
                "grantId" to logId(grant),
                "delta" to LogValue.integer(delta),
                "notes" to LogValue.string(notes),
            ),
        )

    fun wishAction(wish: String, action: String) =
        PlannedMutation(wish, "wishItem", action, emptyMap())

    fun deposit(
        id: String?,
        amount: Amount,
        by: String,
        date: CivilDate,
        notes: String,
        opening: Boolean = false,
        baseline: ProjectedEntity? = null,
    ): PlannedMutation {
        requireProtocol(
            opening || (amount.originalMinor > 0 && amount.finalCNYMinor >= 0),
            "INVALID_DEPOSIT",
        )
        val key = if (opening) stableId("finance-reserves-opening") else id ?: uid()
        val fields =
            mapOf(
                "amount" to logData(amount.json()),
                "depositedBy" to logId(by),
                "date" to logData(date.json()),
                "notes" to LogValue.string(notes),
            )
        return record(
            key,
            "reserveEntry",
            fields.filter {
                baseline == null || comparisonValue(baseline.fields, it.key) != it.value
            } +
                if (snapshot.entities[key] == null)
                    mapOf("kind" to logData(JsonPrimitive(if (opening) "opening" else "deposit")))
                else emptyMap(),
        )
    }

    fun dateEvent(id: String?, title: String, date: CivilDate, notes: String) =
        record(
            id ?: uid(),
            "dateEvent",
            mapOf(
                "title" to LogValue.string(title),
                "date" to logData(date.json()),
                "notes" to LogValue.string(notes),
            ),
        )

    fun expense(
        id: String?,
        title: String,
        amount: Amount,
        payment: Payment,
        date: CivilDate,
        category: String,
        notes: String,
        eventId: String?,
        baseline: ProjectedEntity? = null,
    ): PlannedMutation {
        val old = id?.let { snapshot.entities[it] }
        val values =
            mapOf(
                "title" to LogValue.string(title),
                "amount" to logData(amount.json()),
                "payment" to logData(payment.json()),
                "date" to logData(date.json()),
                "category" to LogValue.string(category),
                "notes" to LogValue.string(notes),
                "eventId" to logId(eventId),
            )
        val p =
            if (baseline == null) values
            else values.filter { comparisonValue(baseline.fields, it.key) != it.value }
        val flags =
            if (old == null)
                mapOf(
                    "zone" to LogValue.string(context.zone),
                    "status" to LogValue.string("reconciled"),
                )
            else
                buildMap {
                    if ("amount" in p) put("amountOverridden", LogValue.bool(true))
                    if ("payment" in p) put("paymentOverridden", LogValue.bool(true))
                }
        return record(id ?: uid(), "expense", p + flags)
    }

    fun reviewExpense(id: String, skipped: Boolean, baseline: ProjectedEntity): PlannedMutation {
        val old = snapshot.entities[id] ?: throw ProtocolException("MISSING_RECORD")
        requireProtocol(
            old.fields["amount"] == baseline.fields["amount"] &&
                old.fields["payment"] == baseline.fields["payment"],
            "RECORD_CHANGED",
        )
        return PlannedMutation(
            id,
            "expense",
            "patch",
            if (skipped) mapOf("status" to LogValue.string("skipped"))
            else
                mapOf(
                    "status" to LogValue.string("reconciled"),
                    "amount" to old.fields.getValue("amount"),
                    "payment" to old.fields.getValue("payment"),
                    "amountOverridden" to LogValue.bool(true),
                    "paymentOverridden" to LogValue.bool(true),
                ),
        )
    }

    fun bill(
        title: String,
        amount: Amount,
        payment: Payment,
        day: Int,
        zone: String,
        category: String,
    ): PlannedMutation {
        val month = FinanceMonth.at(now, zone)
        val today = CivilDate.parse(dayKey(now, zone))
        val start = if (FinancialCalendar.day(month, day, zone) < today) month.next else month
        return record(
            uid(),
            "recurringBill",
            mapOf(
                "title" to LogValue.string(title),
                "amount" to logData(amount.json()),
                "payment" to logData(payment.json()),
                "day" to LogValue.integer(day.toLong()),
                "zone" to LogValue.string(zone),
                "startMonth" to logData(start.json()),
                "minute" to LogValue.nil,
                "category" to LogValue.string(category),
            ),
        )
    }

    fun billDefaults(
        id: String,
        title: String,
        category: String,
        amount: Amount,
        payment: Payment,
        baseline: ProjectedEntity? = null,
        defaultBaseline: FinanceProjection.Occurrence? = null,
    ): List<PlannedMutation> {
        val bill = snapshot.entities[id] ?: throw ProtocolException("MISSING_RECORD")
        val next = FinanceMonth.at(now, bill.fields.text("zone")!!).next
        val occurrence = FinanceProjection.occurrence(bill, next, snapshot)
        val revisions =
            buildMap<String, JsonObject> {
                put("billId", logId(id))
                put("month", logData(next.json()))
                if (amount != (defaultBaseline?.amount ?: occurrence.amount))
                    put("amount", logData(amount.json()))
                if (payment != (defaultBaseline?.payment ?: occurrence.payment))
                    put("payment", logData(payment.json()))
            }
        return listOf(
            record(
                id,
                "recurringBill",
                mapOf("title" to LogValue.string(title), "category" to LogValue.string(category))
                    .filter {
                        baseline == null || comparisonValue(baseline.fields, it.key) != it.value
                    },
                false,
            )
        ) +
            if (revisions.size > 2) listOf(record(uid(), "billRevision", revisions))
            else emptyList()
    }

    fun billActive(id: String, active: Boolean): PlannedMutation {
        val bill = snapshot.entities[id] ?: throw ProtocolException("MISSING_RECORD")
        val zone = bill.fields.text("zone")!!
        return record(
            uid(),
            "billRevision",
            mapOf(
                "billId" to logId(id),
                "month" to logData(FinanceMonth.at(now, zone).json()),
                "active" to LogValue.bool(active),
                "activeFrom" to logData(CivilDate.parse(dayKey(now, zone)).json()),
            ),
        )
    }

    fun forecast(
        id: String,
        month: FinanceMonth,
        amount: Amount,
        payment: Payment,
    ): PlannedMutation {
        val bill = snapshot.entities[id] ?: throw ProtocolException("MISSING_RECORD")
        val occurrence = FinanceProjection.occurrence(bill, month, snapshot)
        requireProtocol(
            now <
                FinancialCalendar.instant(
                    occurrence.day,
                    bill.fields.text("zone")!!,
                    bill.fields.number("minute")?.toInt(),
                ),
            "OCCURRENCE_ALREADY_DUE",
        )
        val key = stableId("finance-forecast:$id:${month.iso}")
        return record(
            key,
            "billOccurrence",
            mapOf("amount" to logData(amount.json()), "payment" to logData(payment.json())) +
                if (snapshot.entities[key] == null)
                    mapOf("billId" to logId(id), "month" to logData(month.json()))
                else emptyMap(),
        )
    }

    fun cycle(
        owner: String?,
        day: Int,
        zone: String,
        salary: Int?,
        deposit: Int?,
        baseline: ProjectedEntity? = null,
    ): PlannedMutation {
        requireProtocol(owner == null || owner == actor, "OWNER_ONLY")
        return record(
            stableId("finance-settings:${owner ?: "shared"}"),
            "financeSettings",
            mapOf(
                    "ownerId" to logId(owner),
                    "day" to LogValue.integer(day.toLong()),
                    "zone" to LogValue.string(zone),
                    "salaryDay" to (salary?.let { LogValue.integer(it.toLong()) } ?: LogValue.nil),
                    "depositDay" to
                        (deposit?.let { LogValue.integer(it.toLong()) } ?: LogValue.nil),
                )
                .filter {
                    baseline == null || comparisonValue(baseline.fields, it.key) != it.value
                },
        )
    }
}

enum class Relationship {
    BOYFRIEND,
    GIRLFRIEND,
    UNKNOWN;

    companion object {
        fun parse(value: String?) =
            when (value?.trim()?.lowercase()) {
                "boyfriend",
                "男朋友",
                "小男友" -> BOYFRIEND
                "girlfriend",
                "女朋友",
                "小女友" -> GIRLFRIEND
                else -> UNKNOWN
            }
    }
}

object BusinessQueries {
    fun tasks(snapshot: Snapshot, filter: String, now: Instant) =
        snapshot
            .of("task")
            .filter {
                it.deletedAt == null &&
                    when (filter) {
                        "completed" -> it.fields.text("status") == "completed"
                        "upcoming" ->
                            it.fields.text("status") != "completed" &&
                                (it.fields.date("dueAt") ?: Long.MIN_VALUE) > now.toEpochMilli()
                        else -> it.fields.text("status") != "completed"
                    }
            }
            .let {
                if (filter == "completed")
                    it.sortedByDescending { e -> e.fields.date("completedAt") ?: 0 }
                else it.sortedWith(compareBy<ProjectedEntity> { e -> e.fields.date("dueAt") ?: Long.MAX_VALUE }.thenBy { e -> e.id })
            }

    data class Reminder(val id: String, val entityId: String, val kind: String)

    fun reminders(s: Snapshot, now: Instant, actor: String? = null): List<Reminder> {
        val result = mutableListOf<Reminder>()
        for (bill in s.of("recurringBill").filter { it.deletedAt == null }) {
            val zone = bill.fields.text("zone")!!
            val today = CivilDate.parse(dayKey(now, zone))
            val tomorrow = today.local.plusDays(1)
            val month = FinanceMonth(tomorrow.year, tomorrow.monthValue)
            val o = FinanceProjection.occurrence(bill, month, s)
            val due = FinancialCalendar.instant(o.day, zone, bill.fields.number("minute")?.toInt())
            val before =
                if (bill.fields.number("minute") == null) o.day.local.minusDays(1) == today.local
                else now >= due.minusSeconds(86400) && now < due
            if (o.active && before && occurrenceId(bill.id, month) !in s.entities)
                result.add(Reminder("before:${bill.id}:${month.iso}", bill.id, "before"))
        }
        for (e in
            s.of("expense").filter {
                it.deletedAt == null && it.fields.text("status") == "provisional"
            }) {
            val yesterday = CivilDate.parse(dayKey(now, e.fields.text("zone")!!)).local.minusDays(1)
            if (CivilDate.from(e.fields.data("date")).local == yesterday)
                result.add(Reminder("review:${e.id}", e.id, "review"))
        }
        if (actor != null)
            for (setting in
                s.of("financeSettings").filter {
                    it.deletedAt == null && it.fields.id("ownerId") == actor
                }) {
                val day = setting.fields.number("depositDay")?.toInt() ?: continue
                val zone = setting.fields.text("zone")!!
                val month = FinanceMonth.at(now, zone)
                if (FinancialCalendar.day(month, day, zone).iso == dayKey(now, zone))
                    result.add(
                        Reminder("deposit-plan:$actor:${month.iso}", setting.id, "depositPlan")
                    )
            }
        return result
    }
}
