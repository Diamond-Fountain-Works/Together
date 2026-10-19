package com.together.domain

import com.together.protocol.*
import java.time.Instant
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class BusinessCommandsTest {
    private val a =
        DeviceIdentity.create(Crypto.seed(), name = "Synthetic A", zone = "Asia/Shanghai")
    private val b =
        DeviceIdentity.create(Crypto.seed(), name = "Synthetic B", zone = "Asia/Shanghai")
    private val space = uid()
    private val c =
        DomainContext(
            space,
            setOf(a.descriptor.userId, b.descriptor.userId),
            setOf(space),
            "Asia/Shanghai",
            a.descriptor.userId,
        )
    private var at = Instant.parse("2026-10-09T04:00:00Z")
    private val facts = mutableListOf<SignedOperation>()

    private fun snapshot() = Projector.replay(facts, c)

    private fun command(
        actor: DeviceIdentity = a,
        build: BusinessCommands.() -> List<PlannedMutation>,
    ) {
        val changes = BusinessCommands(snapshot(), c, actor.descriptor.userId, at).build()
        val additions = changes.mapIndexed { i, m ->
            actor.sign(
                SyncOperation(
                    uid(),
                    actor.descriptor.deviceId,
                    actor.descriptor.userId,
                    m.entityId,
                    m.entityType,
                    m.operationType,
                    facts.size + i + 1L,
                    m.payload,
                    at.toEpochMilli(),
                )
            )
        }
        additions.forEach { it.verify(actor.descriptor) }
        val result = Projector.replay(facts + additions, c)
        assertTrue(
            result.conflicts
                .filter { it.operationId in additions.map { v -> v.operation.operationId } }
                .toString(),
            result.conflicts.none {
                it.operationId in additions.map { v -> v.operation.operationId }
            },
        )
        facts.addAll(additions)
    }

    @Test
    fun unifiedPendingContainsOverdueFutureUndatedAndScheduledWithoutCompletedOrDeleted() {
        command { task(null, "Overdue", "", null, at.minusSeconds(86400).toEpochMilli(), null) }
        command { task(null, "Future", "", null, at.plusSeconds(86400).toEpochMilli(), null) }
        command { task(null, "Undated", "", null, null, null) }
        command { task(null, "Completed", "", null, null, null) }
        command { completion(snapshot.of("task").single { it.fields.text("title") == "Completed" }) }
        command { task(null, "Deleted", "", null, null, null) }
        command { listOf(delete(snapshot.of("task").single { it.fields.text("title") == "Deleted" }.id)) }
        command { task(null, "Flexible", "", null, null, BusinessCommands.Repeat("flexible", zone = "Asia/Shanghai")) }
        command { completion(snapshot.of("task").single { it.fields.text("title") == "Flexible" }, at.plusSeconds(172800).toEpochMilli()) }
        command { RecurrencePlanner.pending(snapshot, context, actor) }
        val pending = BusinessQueries.tasks(snapshot(), "pending", at)
        assertEquals(listOf("Overdue", "Future", "Flexible", "Undated"), pending.map { it.fields.text("title") })
        assertEquals(2, BusinessQueries.tasks(snapshot(), "completed", at).size)
    }

    @Test
    fun groupedTaskRecurringAndFlexibleNextAreCompatibleAndIdempotent() {
        command {
            task(
                null,
                "Synthetic monthly",
                "",
                b.descriptor.userId,
                Instant.parse("2024-01-31T04:00:00Z").toEpochMilli(),
                BusinessCommands.Repeat("regular", "month", 1, "Asia/Shanghai"),
            )
        }
        val task = snapshot().of("task").single()
        command { completion(task) }
        val next = RecurrencePlanner.pending(snapshot(), c, a.descriptor.userId)
        assertEquals(1, next.size)
        assertEquals(
            "2024-02-29T04:00:00Z",
            Instant.ofEpochMilli(next.single().payload.date("dueAt")!!).toString(),
        )
        command { next }
        assertTrue(RecurrencePlanner.pending(snapshot(), c, a.descriptor.userId).isEmpty())
        command {
            task(
                null,
                "Synthetic flexible",
                "",
                null,
                null,
                BusinessCommands.Repeat("flexible", zone = "Asia/Shanghai"),
            )
        }
        val flex = snapshot().of("task").single { it.fields.text("title") == "Synthetic flexible" }
        command { completion(flex) }
        assertTrue(RecurrencePlanner.pending(snapshot(), c, a.descriptor.userId).isEmpty())
        command { listOf(setNext(flex, at.plusSeconds(86400).toEpochMilli())) }
        assertEquals(1, RecurrencePlanner.pending(snapshot(), c, a.descriptor.userId).size)
    }

    @Test
    fun taskEditorBaselinePreservesConcurrentIndependentNotes() {
        command { task(null, "Original", "Original notes", null, null, null) }
        val baseline = snapshot().of("task").single()
        command(b) {
            listOf(
                record(
                    baseline.id,
                    "task",
                    mapOf("notes" to LogValue.string("Remote notes")),
                    false,
                )
            )
        }
        command { task(baseline.id, "Local title", "Original notes", null, null, null, baseline) }
        assertEquals("Remote notes", snapshot().entities[baseline.id]!!.fields.text("notes"))
        assertEquals("Local title", snapshot().entities[baseline.id]!!.fields.text("title"))
    }

    @Test
    fun wishesDirectionsRejectionConfirmationAndAdjustmentRemainAuditable() {
        command {
            listOf(grant(a.descriptor.userId, b.descriptor.userId, 3, CivilDate(2026, 10, 9), ""))
        }
        command {
            listOf(grant(a.descriptor.userId, b.descriptor.userId, 2, CivilDate(2026, 10, 15), ""))
        }
        assertEquals(5, snapshot().grantTotals.values.sum())
        val grant = snapshot().of("wishGrant").first()
        command(b) { listOf(wish(grant.id, "Synthetic wish", "")) }
        val wish = snapshot().wishes.values.single()
        command { listOf(wishAction(wish.id, "requestFulfillment")) }
        command(b) { listOf(wishAction(wish.id, "rejectFulfillment")) }
        assertEquals("open", snapshot().wishes[wish.id]!!.status)
        command { listOf(wishAction(wish.id, "requestFulfillment")) }
        command(b) { listOf(wishAction(wish.id, "confirmFulfillment")) }
        assertEquals(4, snapshot().grantTotals.keys.sumOf { snapshot().remaining(it) })
        command { listOf(adjustment(grant.id, 1, "Synthetic audit correction")) }
        assertEquals(1, snapshot().of("grantAdjustment").size)
        val shuffled = Projector.replay((facts + facts).shuffled(), c)
        assertEquals(snapshot(), shuffled)
    }

    @Test
    fun reservesAAConfirmAndSkippedUseOnlyOneExpense() {
        command {
            listOf(
                deposit(null, Amount.create("100"), a.descriptor.userId, CivilDate(2026, 10, 9), "")
            )
        }
        command {
            listOf(
                expense(
                    null,
                    "Synthetic shared",
                    Amount.create("200.01"),
                    Payment("reserves", emptyList()),
                    CivilDate(2026, 10, 9),
                    "food",
                    "",
                    null,
                )
            )
        }
        command {
            listOf(
                expense(
                    null,
                    "Synthetic AA",
                    Amount.create("9.99"),
                    Payment("equalSplit", c.members.toList()),
                    CivilDate(2026, 10, 9),
                    "food",
                    "",
                    null,
                )
            )
        }
        val stats = FinanceProjection.statistics(snapshot())
        assertEquals(-10001, stats.bookBalance)
        assertEquals(999, stats.personal.values.sum())
        assertEquals(2, snapshot().of("expense").size)
    }

    @Test
    fun defaultsNextMonthAndForecastDoNotMutatePastOrDoubleCount() {
        command {
            listOf(
                bill(
                    "Synthetic bill",
                    Amount.create("68"),
                    Payment("reserves", emptyList()),
                    31,
                    "Asia/Shanghai",
                    "",
                )
            )
        }
        val bill = snapshot().of("recurringBill").single()
        command {
            billDefaults(
                bill.id,
                "Synthetic bill",
                "",
                Amount.create("88"),
                Payment("personal", listOf(a.descriptor.userId)),
            )
        }
        assertEquals(
            6800,
            FinanceProjection.occurrence(bill, FinanceMonth(2026, 10), snapshot())
                .amount
                .finalCNYMinor,
        )
        assertEquals(
            8800,
            FinanceProjection.occurrence(bill, FinanceMonth(2026, 11), snapshot())
                .amount
                .finalCNYMinor,
        )
        at = Instant.parse("2026-10-31T04:00:00Z")
        val pending = BillPlanner.pending(snapshot(), c, a.descriptor.userId, DateProvider { at })
        command { pending }
        assertEquals(1, snapshot().of("expense").size)
        val expense = snapshot().of("expense").single()
        assertEquals(-6800, FinanceProjection.statistics(snapshot()).bookBalance)
        at = at.plusSeconds(86400)
        assertTrue(BusinessQueries.reminders(snapshot(), at).any { it.kind == "review" })
        command { listOf(reviewExpense(expense.id, false, expense)) }
        assertEquals(1, snapshot().of("expense").size)
        assertEquals(-6800, FinanceProjection.statistics(snapshot()).verifiedBalance)
        command {
            listOf(reviewExpense(expense.id, true, snapshot().entities.getValue(expense.id)))
        }
        assertEquals(0, FinanceProjection.statistics(snapshot()).bookBalance)
        assertTrue(
            BillPlanner.pending(snapshot(), c, a.descriptor.userId, DateProvider { at }).isEmpty()
        )
    }

    @Test
    fun plannedDepositAndCycleNeverCreateFundsAndThirtyOneClamps() {
        command { listOf(cycle(a.descriptor.userId, 31, "Asia/Shanghai", 25, 28)) }
        assertTrue(snapshot().of("reserveEntry").isEmpty())
        assertEquals(0, FinanceProjection.statistics(snapshot()).bookBalance)
        assertEquals(
            CivilDate(2024, 2, 29),
            FinancialCalendar.day(FinanceMonth(2024, 2), 31, "Asia/Shanghai"),
        )
    }

    @Test
    fun confirmationFreezesProjectedForecastAndReviewShowsEffectiveAmounts() {
        command {
            listOf(
                bill(
                    "Synthetic bill",
                    Amount.create("68"),
                    Payment("reserves", emptyList()),
                    31,
                    "Asia/Shanghai",
                    "",
                )
            )
        }
        val bill = snapshot().of("recurringBill").single()
        val month = FinanceMonth(2026, 10)
        command {
            listOf(
                forecast(
                    bill.id,
                    month,
                    Amount.create("88"),
                    Payment("personal", listOf(a.descriptor.userId)),
                )
            )
        }
        command {
            billDefaults(
                bill.id,
                "Synthetic bill",
                "",
                Amount.create("98"),
                Payment("reserves", emptyList()),
            )
        }
        val review = ChangeReview.page(facts, c, snapshot(), "finance", 0)
        val forecast = review.single { it.entityType == "billOccurrence" }
        assertEquals(6800, Amount.from(forecast.before.data("amount")).finalCNYMinor)
        assertEquals(8800, Amount.from(forecast.after.data("amount")).finalCNYMinor)
        val revision = review.single { it.entityType == "billRevision" }
        assertEquals(6800, Amount.from(revision.before.data("amount")).finalCNYMinor)
        assertEquals(9800, Amount.from(revision.after.data("amount")).finalCNYMinor)
        at = Instant.parse("2026-10-31T04:00:00Z")
        command { BillPlanner.pending(snapshot(), c, actor, DateProvider { at }) }
        val expense = snapshot().of("expense").single()
        assertEquals(8800, Amount.from(expense.fields.data("amount")).finalCNYMinor)
        command { listOf(reviewExpense(expense.id, false, expense)) }
        val confirmed = snapshot().entities.getValue(expense.id)
        assertEquals(8800, Amount.from(confirmed.fields.data("amount")).finalCNYMinor)
        assertEquals("personal", Payment.from(confirmed.fields.data("payment")).kind)
        assertEquals(0, FinanceProjection.statistics(snapshot()).bookBalance)
        assertEquals(8800, FinanceProjection.statistics(snapshot()).personal.values.sum())
        val changed =
            ChangeReview.page(facts, c, snapshot(), "finance", 0).first {
                it.operationId == facts.last().operation.operationId
            }
        assertEquals(8800, Amount.from(changed.before.data("amount")).finalCNYMinor)
        assertEquals(8800, Amount.from(changed.after.data("amount")).finalCNYMinor)
        assertEquals("provisional", changed.before.text("status"))
        assertEquals("reconciled", changed.after.text("status"))
        val shuffled = Projector.replay((facts + facts).shuffled(), c)
        assertEquals(snapshot(), shuffled)
    }

    @Test
    fun auditAdjustmentUsesTotalAndNeverIncludesGiftContents() {
        command {
            listOf(grant(a.descriptor.userId, b.descriptor.userId, 3, CivilDate(2026, 10, 9), ""))
        }
        val grant = snapshot().of("wishGrant").single()
        command { listOf(adjustment(grant.id, 2, "Synthetic correction")) }
        val adjustment = ChangeReview.page(facts, c, snapshot(), "wish", 0).first()
        assertEquals(3L, adjustment.before.number("quantity"))
        assertEquals(5L, adjustment.after.number("quantity"))
        val id = stableId("gift:$space:${a.descriptor.userId}:2026-10-09")
        command {
            listOf(
                PlannedMutation(
                    id,
                    "loveGift",
                    "create",
                    mapOf(
                        "spaceId" to logId(space),
                        "senderId" to logId(actor),
                        "recipientId" to logId(b.descriptor.userId),
                        "textContent" to LogValue.string("Private sentinel must stay sealed"),
                        "sentAt" to LogValue.date(at.toEpochMilli()),
                        "sentDayKey" to LogValue.string("2026-10-09"),
                        "sharedTimeZoneIdentifier" to LogValue.string("Asia/Shanghai"),
                    ),
                )
            )
        }
        assertFalse(
            ChangeReview.page(facts, c, snapshot(), "gift", 0)
                .toString()
                .contains("Private sentinel")
        )
        assertEquals(emptyList<ChangeEvent>(), ChangeReview.page(facts, c, snapshot(), "all", 1))
    }

    @Test
    fun forecastPatchReviewRetainsBillIdentityAndEffectiveBeforeValue() {
        command {
            listOf(
                bill(
                    "Synthetic forecast",
                    Amount.create("68"),
                    Payment("reserves", emptyList()),
                    31,
                    "Asia/Shanghai",
                    "",
                )
            )
        }
        val id = snapshot().of("recurringBill").single().id
        command {
            listOf(
                forecast(
                    id,
                    FinanceMonth(2026, 10),
                    Amount.create("80"),
                    Payment("reserves", emptyList()),
                )
            )
        }
        command {
            listOf(
                forecast(
                    id,
                    FinanceMonth(2026, 10),
                    Amount.create("81"),
                    Payment("reserves", emptyList()),
                )
            )
        }
        val row = ChangeReview.page(facts, c, snapshot(), "finance", 0).first()
        assertEquals(8000, Amount.from(row.before.data("amount")).finalCNYMinor)
        assertEquals(8100, Amount.from(row.after.data("amount")).finalCNYMinor)
        assertEquals("patch", row.action)
    }

    @Test
    fun flexibleCompletionLaterClearsEarlierProposalWithoutGuessingTime() {
        command {
            task(
                null,
                "Synthetic flexible",
                "",
                null,
                null,
                BusinessCommands.Repeat("flexible", zone = "Asia/Shanghai"),
            )
        }
        val id = snapshot().of("task").single().id
        command {
            listOf(setNext(snapshot().entities.getValue(id), at.plusSeconds(86400).toEpochMilli()))
        }
        command { completion(snapshot().entities.getValue(id)) }
        assertEquals("completed", snapshot().entities.getValue(id).fields.text("status"))
        assertNull(snapshot().entities.getValue(id).fields.date("nextAt"))
        assertTrue(RecurrencePlanner.pending(snapshot(), c, a.descriptor.userId).isEmpty())
    }

    @Test
    fun ruleOnlyEditsRemainVisibleAsTaskChangeReviewWithoutCreationNoise() {
        command {
            task(
                null,
                "Synthetic recurring",
                "",
                null,
                null,
                BusinessCommands.Repeat("regular", "day", 1, "Asia/Shanghai"),
            )
        }
        assertEquals(1, snapshot().changes.size)
        val task = snapshot().of("task").single()
        val rule = snapshot().entities.getValue(task.fields.id("recurrenceRuleId")!!)
        command {
            this.task(
                task.id,
                "Synthetic recurring",
                "",
                null,
                null,
                BusinessCommands.Repeat("regular", "day", 2, "Asia/Shanghai"),
                task,
                rule,
            )
        }
        val change = ChangeReview.page(facts, c, snapshot(), "task", 0).first()
        assertEquals("recurrenceRule", change.entityType)
        assertEquals(1L, change.before.number("interval"))
        assertEquals(2L, change.after.number("interval"))
        assertEquals(snapshot(), Projector.replay((facts + facts).shuffled(), c))
    }

    @Test
    fun deletingGiftUsesGiftProjectionAndDoesNotRefundSlot() {
        val id = stableId("gift:$space:${a.descriptor.userId}:2026-10-09")
        command {
            listOf(
                PlannedMutation(
                    id,
                    "loveGift",
                    "create",
                    mapOf(
                        "spaceId" to logId(space),
                        "senderId" to logId(actor),
                        "recipientId" to logId(b.descriptor.userId),
                        "textContent" to LogValue.string("Synthetic gift"),
                        "sentAt" to LogValue.date(at.toEpochMilli()),
                        "sentDayKey" to LogValue.string("2026-10-09"),
                        "sharedTimeZoneIdentifier" to LogValue.string("Asia/Shanghai"),
                    ),
                )
            )
        }
        command { listOf(delete(id)) }
        assertNotNull(snapshot().gifts[id]!!.entity.deletedAt)
        assertTrue(snapshot().giftUsed(a.descriptor.userId, "2026-10-09"))
    }

    @Test
    fun unknownAndSameRelationshipLabelsDoNotGuessPartner() {
        assertEquals(Relationship.UNKNOWN, Relationship.parse(null))
        assertEquals(Relationship.UNKNOWN, Relationship.parse("future family"))
        assertEquals(Relationship.BOYFRIEND, Relationship.parse(" BOYFRIEND "))
        assertEquals(Relationship.GIRLFRIEND, Relationship.parse("小女友"))
    }
}
