package com.together.domain

import com.together.protocol.*
import kotlinx.serialization.json.*
import java.time.Instant
import java.time.ZoneId

object FinanceProjection {
    val types = setOf("reserveEntry", "dateEvent", "expense", "recurringBill", "billRevision", "billOccurrence", "financeSettings", "paymentMethod")
    private val allowed = mapOf(
        "reserveEntry" to setOf("kind", "depositedBy", "amount", "date", "notes"),
        "dateEvent" to setOf("title", "date", "notes"),
        "expense" to setOf("title", "amount", "payment", "date", "zone", "category", "notes", "eventId", "billId", "month", "status", "amountOverridden", "paymentOverridden"),
        "recurringBill" to setOf("title", "amount", "payment", "day", "zone", "minute", "startMonth", "category"),
        "billRevision" to setOf("billId", "month", "amount", "payment", "active", "activeFrom"),
        "billOccurrence" to setOf("billId", "month", "amount", "payment"),
        "financeSettings" to setOf("ownerId", "day", "zone", "salaryDay", "depositDay"),
        "paymentMethod" to setOf("ownerId", "card", "shared")
    )
    private val required = mapOf(
        "reserveEntry" to setOf("kind", "depositedBy", "amount", "date"), "dateEvent" to setOf("title", "date"),
        "expense" to setOf("title", "amount", "payment", "date", "zone", "status"), "recurringBill" to setOf("title", "amount", "payment", "day", "zone", "startMonth"),
        "billRevision" to setOf("billId", "month"), "billOccurrence" to setOf("billId", "month"), "financeSettings" to setOf("day", "zone"), "paymentMethod" to setOf("ownerId", "card")
    )
    internal fun valid(p: Map<String, JsonObject>, type: String, c: DomainContext, actor: String, creating: Boolean): Boolean = runCatching {
        val fields = if (type == "recurringBill" && !creating) setOf("title", "category") else if (type == "billRevision" && !creating) emptySet() else allowed.getValue(type)
        requireProtocol((fields + if (creating) setOf("spaceId", "createdBy") else emptySet()).containsAll(p.keys), "UNKNOWN_FINANCE_FIELD")
        for (key in listOf("title", "category", "notes")) if (key in p) requireProtocol(textValid(p[key], if (key == "notes") 2000 else 120, key == "title"), "INVALID_TEXT")
        p.optionalData("kind")?.let { requireProtocol(it.jsonPrimitive.content in setOf("opening", "deposit"), "INVALID_RESERVE_KIND") }
        p.optionalData("amount")?.let {
            val a = Amount.from(it)
            if (type != "reserveEntry") requireProtocol(a.originalMinor > 0 && a.finalCNYMinor >= 0, "INVALID_EXPENSE_AMOUNT")
            if (type == "reserveEntry" && p.optionalData("kind")?.jsonPrimitive?.content == "deposit") requireProtocol(a.originalMinor > 0 && a.finalCNYMinor >= 0, "INVALID_DEPOSIT")
        }
        p.optionalData("payment")?.let { Payment.from(it).validate(c.members) }
        if ("date" in p) CivilDate.from(p.data("date"))
        for (key in listOf("month", "startMonth")) p.optionalData(key)?.let { FinanceMonth.from(it) }
        for (key in listOf("day", "salaryDay", "depositDay")) if (p[key] != null && p[key] != LogValue.nil) requireProtocol(p.number(key) in 1..31L, "INVALID_DAY")
        if (p["minute"] != null && p["minute"] != LogValue.nil) requireProtocol(p.number("minute") in 0..1439L, "INVALID_MINUTE")
        if ("zone" in p) ZoneId.of(p.text("zone") ?: throw ProtocolException("INVALID_ZONE"))
        for (key in listOf("depositedBy", "ownerId")) if (p[key] != null && p[key] != LogValue.nil) requireProtocol(p.id(key) in c.members, "NOT_A_MEMBER")
        for (key in listOf("billId", "eventId")) if (p[key] != null && p[key] != LogValue.nil) requireProtocol(p.id(key) != null, "INVALID_ID")
        p.optionalData("activeFrom")?.let { CivilDate.from(it) }
        for (key in listOf("active", "amountOverridden", "paymentOverridden", "shared")) if (p[key] != null && p[key] != LogValue.nil) requireProtocol(p.bool(key) != null, "INVALID_BOOLEAN")
        if ("status" in p) requireProtocol(p.text("status") in setOf("provisional", "reconciled", "skipped"), "INVALID_REVIEW_STATUS")
        if ("card" in p) {
            val card = p.data("card").jsonObject
            fun text(k: String) = card.getValue(k).jsonPrimitive.content
            requireProtocol(text("ownerId") == actor && text("holderId") in c.members && card.getValue("isShared").jsonPrimitive.boolean && text("name").isNotEmpty() && text("name").length <= 60 && text("bankName").isNotEmpty() && text("bankName").length <= 100 && Regex("[0-9]{4}").matches(text("lastFour")) && (card["currencyCode"]?.jsonPrimitive?.content?.let { it in Money.precisions } ?: true), "INVALID_CARD")
            requireProtocol(text("cardKind") in setOf("credit", "debit"), "INVALID_CARD")
        }
        if (creating) {
            requireProtocol(p.keys.containsAll(required.getValue(type)), "MISSING_FINANCE_FIELD")
            for (key in required.getValue(type)) requireProtocol(p[key] != LogValue.nil, "MISSING_FINANCE_FIELD")
            if (type == "financeSettings") requireProtocol(p.id("ownerId") == null || p.id("ownerId") == actor, "OWNER_ONLY")
            if (type == "paymentMethod") requireProtocol(p.id("ownerId") == actor, "OWNER_ONLY")
            if (type == "billRevision") {
                requireProtocol("amount" in p || "payment" in p || p.bool("active") != null, "EMPTY_REVISION")
                if ("active" in p) CivilDate.from(p.data("activeFrom"))
            }
        }
        true
    }.getOrDefault(false)
    fun apply(ops: List<SyncOperation>, c: DomainContext, s: Snapshot) {
        val drafts = mutableMapOf<String, Draft>(); val relevant = ops.filter { it.entityType in types }
        fun bad(op: SyncOperation) { s.conflicts.add(Conflict(op.operationId, op.entityId, "INVALID_FINANCE_RECORD")) }
        for (op in relevant.filter { it.operationType == "create" }) {
            val p = op.payload
            if (!runCatching { Projector.space(p, c) && p.id("createdBy") == op.actorId && valid(p, op.entityType, c, op.actorId, true) }.getOrDefault(false)) { bad(op); continue }
            val prior = drafts[op.entityId]
            if (prior == null) { drafts[op.entityId] = Draft(op); Projector.record(s, op, emptyMap(), p) }
            else {
                val keys = when {
                    op.entityType != prior.base.entityType -> emptySet()
                    op.entityType == "financeSettings" && p["ownerId"] == prior.fields["ownerId"] && op.entityId == stableId("finance-settings:${p.id("ownerId") ?: "shared"}") -> setOf("day", "zone", "salaryDay", "depositDay")
                    op.entityType == "reserveEntry" && op.entityId == stableId("finance-reserves-opening") && p.data("kind").jsonPrimitive.content == "opening" && prior.fields.data("kind").jsonPrimitive.content == "opening" -> setOf("amount", "date", "notes", "depositedBy")
                    op.entityType == "billOccurrence" && p["billId"] == prior.fields["billId"] && p["month"] == prior.fields["month"] -> setOf("amount", "payment")
                    else -> emptySet()
                }
                val before = prior.fields.toMap(); keys.forEach { key -> p[key]?.let { prior.assign(key, it, op) } }; Projector.record(s, op, before, prior.fields.toMap())
            }
        }
        for (op in relevant.filter { it.operationType != "create" }) {
            val d = drafts[op.entityId] ?: continue
            val owner = d.fields.id("ownerId")
            if (op.entityType != d.base.entityType || op.entityType == "billRevision" || (op.entityType == "paymentMethod" && owner != op.actorId) || (op.entityType == "financeSettings" && owner != null && owner != op.actorId)) { bad(op); continue }
            val before = d.entity().fields + ("deletedAt" to (d.deletedAt?.let(LogValue::date) ?: LogValue.nil))
            if (op.operationType == "delete") d.deletedAt = d.deletedAt ?: op.createdAt
            else if (op.operationType == "patch" && valid(op.payload, op.entityType, c, op.actorId, false)) {
                if (op.payload["ownerId"] != null && op.payload["ownerId"] != d.base.payload["ownerId"]) { bad(op); continue }
                val candidate = d.fields + op.payload
                if (!valid(candidate, op.entityType, c, d.base.actorId, true)) { bad(op); continue }
                op.payload.forEach { (k, v) -> d.assign(k, v, op) }
            } else { bad(op); continue }
            Projector.record(s, op, before, d.fields.toMap() + ("deletedAt" to (d.deletedAt?.let(LogValue::date) ?: LogValue.nil)))
        }
        for ((id, d) in drafts.filterValues { it.base.entityType != "expense" }) {
            val p = d.fields
            if (runCatching {
                when (d.base.entityType) {
                    "reserveEntry" -> requireProtocol(p.data("kind").jsonPrimitive.content != "opening" || id == stableId("finance-reserves-opening"), "INVALID_OPENING_ID")
                    "financeSettings" -> requireProtocol(id == stableId("finance-settings:${p.id("ownerId") ?: "shared"}"), "INVALID_SETTINGS_ID")
                    "billOccurrence" -> requireProtocol(id == stableId("finance-forecast:${p.id("billId")}:${FinanceMonth.from(p.data("month")).iso}"), "INVALID_FORECAST_ID")
                    "paymentMethod" -> requireProtocol(p.data("card").jsonObject.getValue("id").jsonPrimitive.content == id, "INVALID_CARD_ID")
                }
            }.isFailure) { bad(d.base); continue }
            s.entities[id] = d.entity()
        }
        for (revision in s.of("billRevision")) {
            val bill = s.entities[revision.fields.id("billId")]
            val p = revision.fields
            if (bill == null || bill.base.entityType != "recurringBill" || ((p.optionalData("amount") != null || p.optionalData("payment") != null) && FinanceMonth.from(p.data("month")) < FinanceMonth.at(Instant.ofEpochMilli(revision.base.createdAt), bill.fields.text("zone")!!).next)) {
                s.entities.remove(revision.id); bad(revision.base)
            }
        }
        for ((id, d) in drafts.filterValues { it.base.entityType == "expense" }) {
            val p = d.fields.toMutableMap()
            val valid = runCatching {
                val eventId = p.id("eventId"); if (eventId != null) requireProtocol(s.entities[eventId]?.base?.entityType == "dateEvent", "MISSING_DATE_EVENT")
                val billId = p.id("billId"); val month = p.optionalData("month")?.let(FinanceMonth::from)
                requireProtocol((billId == null) == (month == null), "MISSING_BILL_MONTH")
                if (billId != null && month != null) {
                    val bill = s.entities[billId] ?: throw ProtocolException("MISSING_BILL")
                    val occurrence = occurrence(bill, month, s)
                    requireProtocol(id == occurrenceId(billId, month) && CivilDate.from(p.data("date")) == occurrence.day && p.text("zone") == bill.fields.text("zone"), "INVALID_OCCURRENCE")
                    if (p.bool("amountOverridden") != true) p["amount"] = LogValue.data(Canonical.bytes(occurrence.amount.json()))
                    if (p.bool("paymentOverridden") != true) p["payment"] = LogValue.data(Canonical.bytes(occurrence.payment.json()))
                    if (!occurrence.active && p.text("status") == "provisional" && p.bool("amountOverridden") != true && p.bool("paymentOverridden") != true) p["status"] = LogValue.string("skipped")
                }
            }.isSuccess
            if (valid) s.entities[id] = d.entity().copy(fields = p.toMap()) else bad(d.base)
        }
        // Failed domain candidates do not enter successful change review.
        val invalid = s.conflicts.map { it.operationId }.toSet(); s.changes.removeAll { it.operationId in invalid }
    }
    data class Occurrence(val day: CivilDate, val amount: Amount, val payment: Payment, val active: Boolean)
    fun occurrence(bill: ProjectedEntity, month: FinanceMonth, snapshot: Snapshot): Occurrence {
        val f = bill.fields; val zone = f.text("zone")!!; val day = FinancialCalendar.day(month, f.number("day")!!.toInt(), zone)
        val due = FinancialCalendar.instant(day, zone, f.number("minute")?.toInt())
        var amount = Amount.from(f.data("amount")); var payment = Payment.from(f.data("payment")); var active = true
        val revisions = snapshot.of("billRevision").filter { it.deletedAt == null && it.fields.id("billId") == bill.id && FinanceMonth.from(it.fields.data("month")) <= month }
        for (r in revisions.sortedWith(compareBy({ FinanceMonth.from(it.fields.data("month")) }, { it.base }))) {
            r.fields.optionalData("amount")?.let { amount = Amount.from(it) }; r.fields.optionalData("payment")?.let { payment = Payment.from(it) }
        }
        for (r in revisions.sortedBy { it.base }) {
            val from = r.fields.optionalData("activeFrom")?.let(CivilDate::from)
            if (from != null && from <= day && r.base.createdAt <= due.toEpochMilli()) r.fields.bool("active")?.let { active = it }
        }
        snapshot.of("billOccurrence").firstOrNull { it.deletedAt == null && it.fields.id("billId") == bill.id && FinanceMonth.from(it.fields.data("month")) == month }?.let { r ->
            r.fields.optionalData("amount")?.let { amount = Amount.from(it) }; r.fields.optionalData("payment")?.let { payment = Payment.from(it) }
        }
        return Occurrence(day, amount, payment, active && (bill.deletedAt == null || due.toEpochMilli() <= bill.deletedAt) && month >= FinanceMonth.from(f.data("startMonth")))
    }
    data class Statistics(val total: Long, val shared: Long, val personal: Map<String, Long>, val bookBalance: Long, val verifiedBalance: Long, val provisional: Long)
    fun statistics(s: Snapshot): Statistics {
        val expenses = s.of("expense").filter { it.deletedAt == null && it.fields.text("status") != "skipped" }
        val incoming = Money.sum(s.of("reserveEntry").filter { it.deletedAt == null }.map { Amount.from(it.fields.data("amount")).finalCNYMinor })
        val shared = expenses.filter { Payment.from(it.fields.data("payment")).kind == "reserves" }
        val spent = Money.sum(shared.map { Amount.from(it.fields.data("amount")).finalCNYMinor })
        val pending = Money.sum(shared.filter { it.fields.text("status") == "provisional" }.map { Amount.from(it.fields.data("amount")).finalCNYMinor })
        val personal = mutableMapOf<String, Long>()
        for (e in expenses) Payment.from(e.fields.data("payment")).allocations(Amount.from(e.fields.data("amount")).finalCNYMinor).forEach { (id, amount) -> personal[id] = Math.addExact(personal[id] ?: 0, amount) }
        return Statistics(Money.sum(expenses.map { Amount.from(it.fields.data("amount")).finalCNYMinor }), spent, personal, Math.subtractExact(incoming, spent), Math.addExact(Math.subtractExact(incoming, spent), pending), pending)
    }
}
