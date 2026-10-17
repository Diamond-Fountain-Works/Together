package com.together.domain

import com.together.protocol.*
import kotlinx.serialization.json.*

/**
 * On-demand bounded audit pages. Signed facts remain the source; no per-balance counters. Replay
 * logical prefixes only for the selected page, off the UI thread.
 */
object ChangeReview {
    const val PAGE_SIZE = 16

    fun domain(type: String) =
        when (type) {
            "task",
            "recurrenceRule" -> "task"
            "wishGrant",
            "wishItem",
            "grantAdjustment" -> "wish"
            "profile" -> "profile"
            "loveGift" -> "gift"
            else -> "finance"
        }

    fun page(
        facts: List<SignedOperation>,
        context: DomainContext,
        current: Snapshot,
        filter: String,
        page: Int,
    ): List<ChangeEvent> {
        requireProtocol(page >= 0, "INVALID_PAGE")
        val selected =
            current.changes
                .asReversed()
                .filter { filter == "all" || domain(it.entityType) == filter }
                .drop(page * PAGE_SIZE)
                .take(PAGE_SIZE)
        val ordered = facts.distinctBy { it.operation.operationId }.sortedBy { it.operation }
        val positions = ordered.mapIndexed { i, v -> v.operation.operationId to i }.toMap()
        return selected.map { event ->
            val index = positions[event.operationId] ?: throw ProtocolException("MISSING_OPERATION")
            val op = ordered[index].operation
            if (op.entityType == "loveGift")
                event // Sealed: never put private text/assets into a review row.
            else {
                val before = Projector.replay(ordered.take(index), context)
                val after = Projector.replay(ordered.take(index + 1), context)
                event.copy(before = values(op, before), after = values(op, after))
            }
        }
    }

    private fun values(op: SyncOperation, s: Snapshot): Map<String, JsonObject> {
        if (op.entityType == "wishItem")
            return s.wishes[op.entityId]?.let {
                mapOf(
                    "title" to LogValue.string(it.title),
                    "description" to LogValue.string(it.description),
                    "status" to LogValue.string(it.status),
                )
            } ?: emptyMap()
        if (op.entityType == "grantAdjustment") {
            val id = op.payload.id("grantId") ?: return emptyMap()
            val grant = s.entities[id] ?: return emptyMap()
            return grant.fields + mapOf("quantity" to LogValue.integer(s.grantTotals[id] ?: 0))
        }
        if (op.entityType in setOf("billRevision", "billOccurrence")) {
            val identity = s.entities[op.entityId]?.fields.orEmpty() + op.payload
            val bill = s.entities[identity.id("billId")] ?: return emptyMap()
            val month = FinanceMonth.from(identity.data("month"))
            val o = FinanceProjection.occurrence(bill, month, s)
            return mapOf(
                "title" to LogValue.string(bill.fields.text("title").orEmpty()),
                "amount" to logData(o.amount.json()),
                "payment" to logData(o.payment.json()),
                "month" to logData(month.json()),
                "active" to LogValue.bool(o.active),
            )
        }
        val entity = s.entities[op.entityId] ?: return emptyMap()
        var fields =
            entity.fields +
                mapOf("deletedAt" to (entity.deletedAt?.let(LogValue::date) ?: LogValue.nil))
        if (op.entityType == "wishGrant")
            fields = fields + mapOf("quantity" to LogValue.integer(s.grantTotals[op.entityId] ?: 0))
        if (op.entityType == "paymentMethod")
            entity.fields.optionalData("card")?.jsonObject?.let { card ->
                fields =
                    mapOf(
                        "bankName" to
                            LogValue.string(card.getValue("bankName").jsonPrimitive.content),
                        "name" to LogValue.string(card.getValue("name").jsonPrimitive.content),
                        "lastFour" to
                            LogValue.string(card.getValue("lastFour").jsonPrimitive.content),
                        "shared" to (entity.fields["shared"] ?: LogValue.bool(true)),
                    )
            }
        return fields
    }
}
