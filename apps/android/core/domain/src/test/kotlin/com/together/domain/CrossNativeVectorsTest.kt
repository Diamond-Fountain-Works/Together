package com.together.domain

import com.together.protocol.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.Instant

/** Generated once under an explicit export flag. Public signatures only; deterministic
 * synthetic keys below have never represented any user, device or service credential. */
class CrossNativeVectorsTest {
    @Test fun kotlinAndSwiftShareSignedBusinessAndEncryptionVectors() {
        val target = File(System.getProperty("together.fixtures"), "android-phase-a-v4.json")
        if (System.getenv("TOGETHER_EXPORT_ANDROID_VECTORS") == "1") target.writeBytes(Canonical.bytes(generate()))
        val v = Canonical.parse(target.readBytes()).jsonObject
        assertTrue(v.getValue("synthetic").jsonPrimitive.boolean)
        val t = SpaceAuthorization.restore(v.getValue("authorization").model())
        val records = v.getValue("records").model<List<ReplicationRecord>>()
        records.forEach { it.authorized!!.verify(t) }
        val s = Projector.replay(records.map { it.operation }, DomainContext.from(t))
        val expected = v.getValue("expected").jsonObject
        assertEquals(expected.getValue("title").jsonPrimitive.content, s.entities.getValue(stableId("android-vector-task")).fields.text("title"))
        assertEquals(4L, s.grantTotals.keys.sumOf { s.remaining(it) })
        assertEquals(71400L, FinanceProjection.statistics(s).bookBalance)
        assertEquals(28701L, FinanceProjection.statistics(s).total)
        assertEquals(1, s.gifts.values.count { it.effective }); assertTrue(s.conflicts.isEmpty())
        val me = v.getValue("androidDevice").model<DeviceDescriptor>()
        val signer = DeviceIdentity(me, ByteArray(32) { (it + 70).toByte() })
        val left = SecureChannel(signer, ByteArray(32) { 91 }, v.getValue("androidHello").model(), v.getValue("swiftHello").model(), t)
        assertEquals(v.getValue("encryptedFromKotlin"), left.seal("Synthetic cross-native encrypted payload".toByteArray()).json())
        val response = System.getenv("TOGETHER_ANDROID_RESPONSE_PATH")?.let(::File)
        if (response != null && response.exists()) assertEquals("Synthetic CryptoKit response", left.open(Canonical.parse(response.readBytes()).model()).toString(Charsets.UTF_8))
    }
    private fun generate(): JsonObject {
        fun device(i: Int, user: String = stableId("android-vector-user-$i"), space: String = stableId("android-vector-initial-$i")) = DeviceIdentity.create(ByteArray(32) { (it + i).toByte() }, user, space, stableId("android-vector-device-$i"), "Synthetic $i", "Asia/Shanghai")
        val a = device(50); val b = device(60)
        val space = stableId("android-vector-frozen-space")
        val body = GenesisBody(4, space, listOf(a.descriptor.userId, b.descriptor.userId).sorted(), listOf(a.descriptor, b.descriptor).sortedBy { it.deviceId }, listOf(space, a.descriptor.initialSpaceId, b.descriptor.initialSpaceId).sorted(), "Asia/Shanghai", checkpoint(emptyList()))
        val genesis = SignedGenesis(body, listOf(a, b).sortedBy { it.descriptor.deviceId }.map { DeviceSignature(it.descriptor.deviceId, it.sign(Canonical.encode(body))) })
        val phone = device(70, a.descriptor.userId, space)
        val grantBody = AuthorizationBody(spaceId = space, ownerId = a.descriptor.userId, revision = 1, previousDigest = genesis.digest, authorizerDeviceId = a.descriptor.deviceId, action = "grant", device = phone.descriptor, epochId = stableId("android-vector-phone-epoch"))
        val grant = AuthorizationEvent(grantBody, a.sign(Canonical.encode(grantBody)))
        val t = SpaceAuthorization.restore(AuthorizationArchive(genesis, listOf(grant)))
        val ops = mutableListOf<SignedOperation>(); var clock = 0L
        val now = Instant.parse("2026-10-09T04:00:00Z").toEpochMilli()
        fun data(v: JsonElement) = LogValue.data(Canonical.bytes(v))
        fun add(id: String, type: String, action: String, p: Map<String, JsonObject>, who: DeviceIdentity = phone): SignedOperation {
            val f = p.toMutableMap()
            if (action == "create" && type !in setOf("wishItem", "loveGift")) { f["spaceId"] = LogValue.string(space); f["createdBy"] = LogValue.string(who.descriptor.userId) }
            val o = SyncOperation(stableId("android-vector-operation-${++clock}"), who.descriptor.deviceId, who.descriptor.userId, stableId(id), type, action, clock, f, now)
            return who.sign(o).also(ops::add)
        }
        add("android-vector-task", "task", "create", mapOf("title" to LogValue.string("Synthetic original")))
        add("android-vector-task", "task", "patch", mapOf("notes" to LogValue.string("Synthetic independent field")))
        add("android-vector-task", "task", "patch", mapOf("title" to LogValue.string("Synthetic partner edit")), b)
        for ((id, quantity, date) in listOf(Triple("g1", 3L, "2026-10-09"), Triple("g2", 2L, "2026-10-15"))) add(id, "wishGrant", "create", mapOf("fulfillerId" to LogValue.string(phone.descriptor.userId), "beneficiaryId" to LogValue.string(b.descriptor.userId), "quantity" to LogValue.integer(quantity), "grantedOn" to LogValue.string(date)))
        add("wish", "wishItem", "create", mapOf("grantId" to LogValue.string(stableId("g1")), "createdBy" to LogValue.string(b.descriptor.userId), "title" to LogValue.string("Synthetic wish")), b)
        add("wish", "wishItem", "requestFulfillment", emptyMap())
        add("wish", "wishItem", "confirmFulfillment", emptyMap(), b)
        val date = data(CivilDate(2026, 10, 9).json())
        add("reserve", "reserveEntry", "create", mapOf("kind" to data(JsonPrimitive("deposit")), "amount" to data(Amount.create("1000").json()), "depositedBy" to LogValue.string(phone.descriptor.userId), "date" to date))
        fun expense(id: String, amount: String, payment: Payment) = add(id, "expense", "create", mapOf("title" to LogValue.string("Synthetic expense"), "amount" to data(Amount.create(amount).json()), "payment" to data(payment.json()), "date" to date, "zone" to LogValue.string("Asia/Shanghai"), "status" to LogValue.string("reconciled")))
        expense("expense", "218", Payment("reserves", emptyList()))
        expense("aa", "1.01", Payment("equalSplit", listOf(phone.descriptor.userId, b.descriptor.userId).sorted()))
        add("bill", "recurringBill", "create", mapOf("title" to LogValue.string("Synthetic bill"), "amount" to data(Amount.create("68").json()), "payment" to data(Payment("reserves", emptyList()).json()), "day" to LogValue.integer(31), "zone" to LogValue.string("Asia/Shanghai"), "startMonth" to data(FinanceMonth(2026, 10).json())))
        add("revision", "billRevision", "create", mapOf("billId" to LogValue.string(stableId("bill")), "month" to data(FinanceMonth(2026, 11).json()), "amount" to data(Amount.create("88").json())))
        val snapshot = Projector.replay(ops, DomainContext.from(t))
        val planned = BillPlanner.pending(snapshot, DomainContext.from(t), phone.descriptor.userId, DateProvider { Instant.parse("2026-11-01T00:00:00Z") }).single()
        val generated = add("generated", "expense", "create", planned.payload)
        ops[ops.lastIndex] = phone.sign(generated.operation.copy(entityId = planned.entityId))
        add("gift", "loveGift", "create", mapOf("spaceId" to LogValue.string(space), "senderId" to LogValue.string(phone.descriptor.userId), "recipientId" to LogValue.string(b.descriptor.userId), "textContent" to LogValue.string("Synthetic private gift"), "sentAt" to LogValue.date(now), "sentDayKey" to LogValue.string("2026-10-09"), "sharedTimeZoneIdentifier" to LogValue.string("Asia/Shanghai")))
        val heads = mutableMapOf<String, Frontier>()
        val records = ops.map { op ->
            val signer = if (op.operation.deviceId == phone.descriptor.deviceId) phone else b
            val epoch = t.devices.getValue(signer.descriptor.deviceId).epochId; val head = heads[epoch] ?: Frontier()
            val ab = AuthorizedBody(spaceId = space, epochId = epoch, sequence = head.sequence + 1, previousDigest = head.digest, signedOperation = op)
            val proof = AuthorizedOperation(ab, signer.sign(Canonical.encode(ab))); heads[epoch] = Frontier(ab.sequence, proof.digest)
            ReplicationRecord("authorized", authorized = proof)
        }
        fun hello(signer: DeviceIdentity, ephemeral: Int, nonce: String): SignedHello {
            val h = SecureChannel.hello(signer, ByteArray(32) { ephemeral.toByte() }, t).body.copy(nonce = stableId(nonce))
            return SignedHello(h, signer.sign(Canonical.encode(h)))
        }
        val ah = hello(phone, 91, "android-vector-nonce-a"); val bh = hello(b, 92, "android-vector-nonce-b")
        val channel = SecureChannel(phone, ByteArray(32) { 91 }, ah, bh, t)
        return buildJsonObject {
            put("synthetic", true); put("authorization", t.archive.json()); put("androidDevice", phone.descriptor.json()); put("records", records.json())
            put("androidHello", ah.json()); put("swiftHello", bh.json()); put("encryptedFromKotlin", channel.seal("Synthetic cross-native encrypted payload".toByteArray()).json())
            put("expected", buildJsonObject { put("title", "Synthetic partner edit"); put("wishRemaining", "4"); put("bookBalance", "71400"); put("totalExpenses", "28701") })
        }
    }
}
