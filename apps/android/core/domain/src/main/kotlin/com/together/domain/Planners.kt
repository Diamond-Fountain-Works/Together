package com.together.domain

import com.together.protocol.*
import kotlinx.serialization.json.*
import java.time.Instant

data class PlannedMutation(val entityId: String, val entityType: String, val operationType: String, val payload: Map<String, JsonObject>)
object RecurrencePlanner {
    fun pending(snapshot: Snapshot, context: DomainContext, actor: String): List<PlannedMutation> {
        val result = mutableListOf<PlannedMutation>()
        for (task in snapshot.of("task").filter { it.deletedAt == null && it.fields.text("status") == "completed" }.sortedBy { it.id }) {
            val ruleId = task.fields.id("recurrenceRuleId") ?: continue
            val rule = snapshot.entities[ruleId]?.takeIf { it.base.entityType == "recurrenceRule" } ?: continue
            val index = (task.fields.number("occurrenceIndex") ?: 0) + 1
            val flexible = rule.fields.text("mode") == "flexible"
            val date = if (flexible) task.fields.date("nextAt")?.let(Instant::ofEpochMilli) else Recurrence.date(Instant.ofEpochMilli(rule.fields.date("anchorAt")!!), rule.fields.text("unit")!!, rule.fields.number("interval")!!.toInt(), index.toInt(), rule.fields.text("timeZoneIdentifier")!!)
            if (date == null) continue
            val id = if (flexible) Recurrence.flexibleId(task.id) else Recurrence.instanceId(ruleId, index.toInt())
            val old = snapshot.entities[id]
            if (old != null) {
                if (flexible && old.deletedAt == null && old.fields.text("status") != "completed" && old.fields.date("dueAt") != date.toEpochMilli()) result.add(PlannedMutation(id, "task", "patch", mapOf("dueAt" to LogValue.date(date.toEpochMilli()), "availableAt" to LogValue.date(date.toEpochMilli()))))
            } else {
                val fields = mapOf("spaceId" to LogValue.string(context.spaceId), "createdBy" to LogValue.string(actor), "title" to LogValue.string(task.fields.text("title")!!), "notes" to LogValue.string(task.fields.text("notes") ?: ""), "assignedTo" to (task.fields["assignedTo"] ?: LogValue.nil), "dueAt" to LogValue.date(date.toEpochMilli()), "status" to LogValue.string("pending"), "recurrenceRuleId" to LogValue.string(ruleId), "occurrenceIndex" to LogValue.integer(index), "spawnedFromId" to LogValue.string(task.id), "availableAt" to LogValue.date(date.toEpochMilli()))
                result.add(PlannedMutation(id, "task", "create", fields))
            }
        }
        return result
    }
}
object BillPlanner {
    fun pending(snapshot: Snapshot, context: DomainContext, actor: String, clock: DateProvider): List<PlannedMutation> {
        val now = clock.now(); val result = mutableListOf<PlannedMutation>()
        for (bill in snapshot.of("recurringBill").sortedBy { it.id }) {
            val f = bill.fields; val zone = f.text("zone")!!
            var month = FinanceMonth.from(f.data("startMonth"))
            val current = FinanceMonth.at(minOf(now, bill.deletedAt?.let(Instant::ofEpochMilli) ?: now), zone)
            while (month <= current) {
                val occurrence = FinanceProjection.occurrence(bill, month, snapshot)
                val due = FinancialCalendar.instant(occurrence.day, zone, f.number("minute")?.toInt()); val id = occurrenceId(bill.id, month)
                if (occurrence.active && due <= now && id !in snapshot.entities) result.add(PlannedMutation(id, "expense", "create", mapOf(
                    "spaceId" to LogValue.string(context.spaceId), "createdBy" to LogValue.string(actor), "title" to LogValue.string(f.text("title")!!), "amount" to LogValue.data(Canonical.bytes(occurrence.amount.json())), "payment" to LogValue.data(Canonical.bytes(occurrence.payment.json())), "date" to LogValue.data(Canonical.bytes(occurrence.day.json())), "zone" to LogValue.string(zone), "category" to LogValue.string(f.text("category") ?: ""), "notes" to LogValue.string(""), "billId" to LogValue.string(bill.id), "month" to LogValue.data(Canonical.bytes(month.json())), "status" to LogValue.string("provisional")
                )))
                if (month.year == 3000 && month.month == 12) break
                month = month.next
            }
        }
        return result
    }
}
