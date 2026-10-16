package com.together.domain

import com.together.protocol.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.Instant

private fun fixture(name: String) = Canonical.parse(File(System.getProperty("together.fixtures"), name).readBytes()).jsonObject
private val a = "00000000-0000-0000-0000-000000000101"
private val b = "00000000-0000-0000-0000-000000000102"
private val space = "00000000-0000-0000-0000-000000000200"
private val context = DomainContext(space, setOf(a, b), setOf(space), "Asia/Shanghai", a)
private val now = Instant.parse("2026-10-09T04:00:00Z")
private fun op(id: String, type: String, action: String, clock: Long, fields: Map<String, JsonObject>, actor: String = a, at: Instant = now) = SignedOperation(SyncOperation(stableId("op-$id-$action-$clock-$actor"), actor, actor, stableId(id), type, action, clock, fields, at.toEpochMilli()), "")
private fun identityFields(actor: String = a) = mapOf("spaceId" to LogValue.string(space), "createdBy" to LogValue.string(actor))
private fun data(v: JsonElement) = LogValue.data(Canonical.bytes(v))
private fun replay(vararg ops: SignedOperation) = Projector.replay(ops.toList(), context)
private fun billFields(amount: String = "68", day: Long = 31) = identityFields() + mapOf("title" to LogValue.string("Synthetic bill"), "amount" to data(Amount.create(amount).json()), "payment" to data(Payment("reserves", emptyList()).json()), "day" to LogValue.integer(day), "zone" to LogValue.string("Asia/Shanghai"), "startMonth" to data(FinanceMonth(2026, 10).json()))
class DomainConformanceTest {
    @Test fun sameMoneyFixturesAsSwift() {
        for (v in fixture("conformance-v1.json").getValue("money").jsonArray) {
            val m = v.jsonObject; val amount = Amount.create(m.getValue("original").jsonPrimitive.content, m.getValue("currency").jsonPrimitive.content, m["actualCNY"]?.jsonPrimitive?.content)
            assertEquals(m.getValue("originalMinor").jsonPrimitive.content, amount.originalMinor.toString()); assertEquals(m.getValue("cnyMinor").jsonPrimitive.content, amount.finalCNYMinor.toString())
        }
        val snapshot = fixture("dto-snapshots-v3.json").getValue("samples").jsonObject.getValue("FinanceAmount")
        assertEquals(snapshot, Amount.from(snapshot).json())
    }
    @Test fun exactCNYRoundingNoFloatAndReferenceFreeze() {
        assertEquals(101L, Money.minor("1.005", "CNY", true)); assertEquals(-101L, Money.minor("-1.005", "CNY", true))
        assertThrows(ArithmeticException::class.java) { Money.minor("1.1", "JPY") }
        assertThrows(ProtocolException::class.java) { Money.minor("1", "FAKE") }
        assertEquals(30L, Money.sum(listOf(Money.minor("0.1", "CNY"), Money.minor("0.2", "CNY"))))
        assertThrows(ArithmeticException::class.java) { Money.sum(listOf(Long.MAX_VALUE, 1)) }
        val rate = buildJsonObject { put("cnyPerOriginalUnit", "7.0007"); put("source", "Synthetic reference"); put("quotedOn", CivilDate(2026, 10, 9).json()) }
        val amount = Amount.create("100", "USD", exchangeRate = rate)
        assertEquals(70007L, amount.finalCNYMinor)
        assertEquals(60000L, Amount.create("100", "USD", "600", rate).finalCNYMinor)
        assertThrows(ProtocolException::class.java) { amount.copy(finalCNYMinor = 70008).validate() }
    }
    @Test fun fourPaymentMethodsAndAA() {
        val payment = Payment("equalSplit", listOf(b, a)); payment.validate(context.members)
        assertEquals(mapOf(a to 51L, b to 50L), payment.allocations(101))
        assertEquals(emptyMap<String, Long>(), Payment("reserves", emptyList()).allocations(101))
        assertEquals(mapOf(a to 101L), Payment("personal", listOf(a)).allocations(101))
        assertEquals(mapOf(b to 101L), Payment("personal", listOf(b)).allocations(101))
        assertThrows(ProtocolException::class.java) { Payment("equalSplit", listOf(a, a)).validate(context.members) }
    }
    @Test fun monthly31AndFinancialCycleFixture() {
        val f = fixture("conformance-v1.json")
        f.getValue("monthly31").jsonArray.forEach { v -> val p = v.jsonObject; assertEquals(p.getValue("date").jsonPrimitive.content, FinancialCalendar.day(FinanceMonth.parse(p.getValue("month").jsonPrimitive.content), 31, p.getValue("zone").jsonPrimitive.content).iso) }
        val c = f.getValue("cycle").jsonObject
        val (start, end) = FinancialCalendar.cycle(Instant.parse(c.getValue("instant").jsonPrimitive.content), c.getValue("startDay").jsonPrimitive.int, c.getValue("zone").jsonPrimitive.content)
        assertEquals(Instant.parse(c.getValue("start").jsonPrimitive.content), start); assertEquals(Instant.parse(c.getValue("end").jsonPrimitive.content), end)
        assertEquals(end, FinancialCalendar.cycle(end, 31, "Asia/Shanghai").first)
    }
    @Test fun sharedDayKeyAcrossDeviceTimeZones() {
        val t = fixture("conformance-v1.json").getValue("time").jsonObject
        val instant = Instant.parse(t.getValue("instant").jsonPrimitive.content)
        assertEquals(t.getValue("dayKey").jsonPrimitive.content, dayKey(instant, t.getValue("sharedZone").jsonPrimitive.content))
        assertNotEquals(dayKey(instant, "America/Los_Angeles"), dayKey(instant, "Asia/Shanghai"))
        val midnight = Instant.parse("2026-10-09T16:00:00Z")
        assertEquals("2026-10-09", dayKey(midnight.minusMillis(1), "Asia/Shanghai")); assertEquals("2026-10-10", dayKey(midnight, "Asia/Shanghai"))
    }
    @Test fun signedLogMergeFixtureAndTombstone() {
        val f = fixture("signed-log-v3.json"); val signed = f.getValue("operations").model<List<SignedOperation>>()
        val devices = f.getValue("devices").model<List<DeviceDescriptor>>(); signed.forEach { it.verify(devices.single { d -> d.deviceId == it.operation.deviceId }) }
        val c = context.copy(spaceId = signed.first().operation.payload.id("spaceId")!!, aliases = setOf(signed.first().operation.payload.id("spaceId")!!))
        val s = Projector.replay(signed.reversed() + signed, c)
        val task = s.of("task").single(); assertNotNull(task.deletedAt); assertEquals("INDEPENDENT_FIELD", task.fields.text("notes"))
        val before = Projector.replay(signed.take(3).shuffled(), c).of("task").single(); assertEquals("RIGHT", before.fields.text("title"))
    }
    @Test fun tasksCRUDOutOfOrderAndProfileOwnership() {
        val create = op("task", "task", "create", 1, identityFields() + mapOf("title" to LogValue.string("Original")))
        val patch = op("task", "task", "patch", 2, mapOf("notes" to LogValue.string("Independent")), b)
        val complete = op("task", "task", "completeTask", 3, emptyMap())
        val reopen = op("task", "task", "reopenTask", 4, emptyMap(), b)
        assertEquals("pending", replay(reopen, patch, create, complete).of("task").single().fields.text("status"))
        assertEquals("Independent", replay(reopen, patch, create, complete).of("task").single().fields.text("notes"))
        val profile = SignedOperation(SyncOperation(stableId("pcreate"), a, a, a, "profile", "create", 1, mapOf("deviceId" to LogValue.string(a), "displayName" to LogValue.string("Synthetic")), now.toEpochMilli()), "")
        val illegal = profile.copy(operation = profile.operation.copy(operationId = stableId("ppatch"), deviceId = b, actorId = b, operationType = "patch", lamportClock = 2, payload = mapOf("displayName" to LogValue.string("Attacker"))))
        val s = replay(profile, illegal); assertEquals("Synthetic", s.entities[a]!!.fields.text("displayName")); assertEquals(1, s.conflicts.size)
    }
    @Test fun regularAndFlexibleRecurrenceStableNoDuplicate() {
        val rule = op("rule", "recurrenceRule", "create", 1, identityFields() + mapOf("mode" to LogValue.string("regular"), "unit" to LogValue.string("month"), "interval" to LogValue.integer(1), "anchorAt" to LogValue.date(Instant.parse("2024-01-31T04:00:00Z").toEpochMilli()), "timeZoneIdentifier" to LogValue.string("Asia/Shanghai")))
        val task = op("task", "task", "create", 2, identityFields() + mapOf("title" to LogValue.string("Synthetic recurring"), "recurrenceRuleId" to LogValue.string(stableId("rule"))))
        val completed = op("task", "task", "completeTask", 3, emptyMap())
        val s = replay(rule, task, completed); val mutations = RecurrencePlanner.pending(s, context, a)
        assertEquals(1, mutations.size); assertEquals("2024-02-29T04:00:00Z", Instant.ofEpochMilli(mutations.single().payload.date("dueAt")!!).toString())
        val next = op("ignored", "task", "create", 4, mutations.single().payload).let { it.copy(operation = it.operation.copy(entityId = mutations.single().entityId)) }
        assertTrue(RecurrencePlanner.pending(replay(rule, task, completed, next), context, a).isEmpty())
        val flexible = rule.copy(operation = rule.operation.copy(payload = rule.operation.payload + ("mode" to LogValue.string("flexible"))))
        assertTrue(RecurrencePlanner.pending(replay(flexible, task, completed), context, a).isEmpty())
        val setNext = op("task", "task", "patch", 4, mapOf("nextAt" to LogValue.date(now.plusSeconds(86400).toEpochMilli())))
        assertEquals(Recurrence.flexibleId(stableId("task")), RecurrencePlanner.pending(replay(flexible, task, completed, setNext), context, a).single().entityId)
    }
    @Test fun dailyCalendarRecurrenceAcrossDST() {
        val before = Instant.parse("2024-03-09T15:00:00Z")
        assertEquals(Instant.parse("2024-03-10T14:00:00Z"), Recurrence.date(before, "day", 1, 1, "America/New_York"))
        assertNull(Recurrence.date(before, "day", 1, 1, "America/New_York", "flexible"))
    }
    @Test fun wishesHistoryAndExactlyOneConfirmation() {
        fun grant(id: String, q: Long, day: String, clock: Long) = op(id, "wishGrant", "create", clock, identityFields() + mapOf("fulfillerId" to LogValue.string(a), "beneficiaryId" to LogValue.string(b), "quantity" to LogValue.integer(q), "grantedOn" to LogValue.string(day)))
        val g1 = grant("g1", 3, "2026-10-09", 1); val g2 = grant("g2", 2, "2026-10-15", 2)
        val wish = op("wish", "wishItem", "create", 3, mapOf("grantId" to LogValue.string(stableId("g1")), "createdBy" to LogValue.string(b), "title" to LogValue.string("Synthetic wish")), b)
        val request = op("wish", "wishItem", "requestFulfillment", 4, emptyMap())
        val confirm = op("wish", "wishItem", "confirmFulfillment", 5, emptyMap(), b)
        val s = replay(g1, g2, wish, request, confirm, confirm)
        assertEquals(2, s.of("wishGrant").size); assertEquals(5L, s.grantTotals.values.sum()); assertEquals(4L, s.grantTotals.keys.sumOf { s.remaining(it) })
        val illegal = op("over", "wishItem", "create", 6, wish.operation.payload, a)
        assertEquals(1, replay(g1, g2, wish, illegal).conflicts.size)
    }
    @Test fun wishesOverAllocationAndAdjustmentsAreDiagnosed() {
        val g = op("g", "wishGrant", "create", 1, identityFields() + mapOf("fulfillerId" to LogValue.string(a), "beneficiaryId" to LogValue.string(b), "quantity" to LogValue.integer(1), "grantedOn" to LogValue.string("2026-10-09")))
        fun wish(id: String, clock: Long) = op(id, "wishItem", "create", clock, mapOf("grantId" to LogValue.string(stableId("g")), "createdBy" to LogValue.string(b), "title" to LogValue.string("Synthetic")), b)
        val s = replay(g, wish("w1", 2), wish("w2", 3)); assertEquals(1, s.conflicts.size); assertEquals(1, s.wishes.values.count { it.status == "conflict" })
        val adjust = op("adj", "grantAdjustment", "create", 4, mapOf("grantId" to LogValue.string(stableId("g")), "delta" to LogValue.integer(-1), "notes" to LogValue.string("Synthetic correction")))
        assertEquals(1L, replay(g, wish("w1", 2), adjust).grantTotals.getValue(stableId("g")))
    }
    @Test fun financeProvisionalConfirmSkipOneLedgerAndNegativeBalance() {
        val deposit = op("deposit", "reserveEntry", "create", 1, identityFields() + mapOf("kind" to data(JsonPrimitive("deposit")), "depositedBy" to LogValue.string(a), "amount" to data(Amount.create("100").json()), "date" to data(CivilDate(2026, 10, 9).json())))
        val expense = op("expense", "expense", "create", 2, identityFields() + mapOf("title" to LogValue.string("Synthetic"), "amount" to data(Amount.create("218").json()), "payment" to data(Payment("reserves", emptyList()).json()), "date" to data(CivilDate(2026, 10, 9).json()), "zone" to LogValue.string("Asia/Shanghai"), "status" to LogValue.string("provisional")))
        val s = replay(expense, deposit, expense); val stats = FinanceProjection.statistics(s)
        assertEquals(-11800L, stats.bookBalance); assertEquals(10000L, stats.verifiedBalance); assertEquals(21800L, stats.provisional); assertTrue(stats.personal.isEmpty())
        val confirm = op("expense", "expense", "patch", 3, mapOf("status" to LogValue.string("reconciled")))
        assertEquals(-11800L, FinanceProjection.statistics(replay(deposit, expense, confirm)).bookBalance)
        val skip = op("expense", "expense", "patch", 4, mapOf("status" to LogValue.string("skipped")))
        assertEquals(10000L, FinanceProjection.statistics(replay(deposit, expense, confirm, skip)).bookBalance)
    }
    @Test fun recurringBillsDefaultsNextMonthTemporaryOverrideAndStableInstance() {
        val bill = op("bill", "recurringBill", "create", 1, billFields())
        val rev = op("revision", "billRevision", "create", 2, identityFields() + mapOf("billId" to LogValue.string(stableId("bill")), "month" to data(FinanceMonth(2026, 11).json()), "amount" to data(Amount.create("88").json()), "payment" to data(Payment("personal", listOf(b)).json())))
        val s = replay(rev, bill); val projected = s.entities.getValue(stableId("bill"))
        assertEquals(6800L, FinanceProjection.occurrence(projected, FinanceMonth(2026, 10), s).amount.finalCNYMinor)
        assertEquals(8800L, FinanceProjection.occurrence(projected, FinanceMonth(2026, 11), s).amount.finalCNYMinor)
        assertEquals(listOf(b), FinanceProjection.occurrence(projected, FinanceMonth(2026, 11), s).payment.userIds)
        assertTrue(BillPlanner.pending(Snapshot(), context, a, DateProvider { now }).isEmpty())
        val planned = BillPlanner.pending(s, context, a, DateProvider { Instant.parse("2026-11-01T01:00:00Z") }).single()
        val generated = op("unused", "expense", "create", 3, planned.payload).let { it.copy(operation = it.operation.copy(entityId = planned.entityId)) }
        val secondDevice = generated.copy(operation = generated.operation.copy(operationId = stableId("concurrent-bill"), actorId = b, deviceId = b, payload = generated.operation.payload + ("createdBy" to LogValue.string(b))))
        val all = replay(bill, rev, generated, secondDevice); assertEquals(1, all.of("expense").size); assertEquals(-6800L, FinanceProjection.statistics(all).bookBalance)
        val currentMonthBad = rev.copy(operation = rev.operation.copy(payload = rev.operation.payload + ("month" to data(FinanceMonth(2026, 10).json()))))
        assertEquals(1, replay(bill, currentMonthBad).conflicts.size)
    }
    @Test fun dailyGiftQuotaImmutableDeleteNoRefundAndSealedReview() {
        fun gift(id: String, clock: Long, text: String) = op(id, "loveGift", "create", clock, mapOf("spaceId" to LogValue.string(space), "senderId" to LogValue.string(a), "recipientId" to LogValue.string(b), "textContent" to LogValue.string(text), "sentAt" to LogValue.date(now.toEpochMilli()), "sentDayKey" to LogValue.string("2026-10-09"), "sharedTimeZoneIdentifier" to LogValue.string("Asia/Shanghai")))
        val one = gift("gift1", 1, "PRIVATE SYNTHETIC TEXT"); val two = gift("gift2", 2, "SECOND SYNTHETIC TEXT")
        val delete = op("gift1", "loveGift", "delete", 3, emptyMap())
        val s = replay(two, delete, one, one)
        assertEquals(1, s.gifts.values.count { it.effective }); assertTrue(s.giftUsed(a, "2026-10-09")); assertEquals(1, s.conflicts.size)
        assertFalse(s.changes.toString().contains("PRIVATE SYNTHETIC TEXT")); assertNotNull(s.gifts.getValue(stableId("gift1")).entity.deletedAt)
    }
    @Test fun photoOnlyGiftValidatesOwnerManifest() {
        val assetId = stableId("photo")
        val photo = op("photo", "mediaAsset", "create", 1, mapOf("spaceId" to LogValue.string(space), "ownerId" to LogValue.string(a), "mediaType" to LogValue.string("photo"), "originalFilename" to LogValue.string("Synthetic.png"), "fileExtension" to LogValue.string("png"), "sha256" to LogValue.string("a".repeat(64)), "byteCount" to LogValue.integer(90000000)))
        val gift = op("photo-gift", "loveGift", "create", 2, mapOf("spaceId" to LogValue.string(space), "senderId" to LogValue.string(a), "recipientId" to LogValue.string(b), "photoAssetId" to LogValue.string(assetId), "sentAt" to LogValue.date(now.toEpochMilli()), "sentDayKey" to LogValue.string("2026-10-09"), "sharedTimeZoneIdentifier" to LogValue.string("Asia/Shanghai")))
        assertTrue(replay(gift, photo).gifts.values.single().effective)
        val wrong = photo.copy(operation = photo.operation.copy(actorId = b, deviceId = b, payload = photo.operation.payload + ("ownerId" to LogValue.string(b))))
        assertTrue(replay(gift, wrong).gifts.isEmpty())
    }
}
