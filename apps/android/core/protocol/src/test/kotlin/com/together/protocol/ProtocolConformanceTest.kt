package com.together.protocol

import kotlinx.serialization.json.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import org.junit.Assert.*
import org.junit.Test
import java.io.File

fun fixture(name: String) = Canonical.parse(File(System.getProperty("together.fixtures"), name).readBytes()).jsonObject
fun identity(index: Int, user: String = stableId("test-user-$index"), space: String = stableId("test-space-$index")) = DeviceIdentity.create(ByteArray(32) { (index + it).toByte() }, user, space, stableId("test-device-$index"), "Synthetic $index", "Asia/Shanghai")
fun testTrust(a: DeviceIdentity, b: DeviceIdentity): SpaceAuthorization {
    val space = stableId("space:" + listOf(a.descriptor.deviceId, b.descriptor.deviceId).sorted().joinToString(":"))
    val body = GenesisBody(4, space, listOf(a.descriptor.userId, b.descriptor.userId).sorted(), listOf(a.descriptor, b.descriptor).sortedBy { it.deviceId }, listOf(a.descriptor.initialSpaceId, b.descriptor.initialSpaceId, space).distinct().sorted(), "Asia/Shanghai", checkpoint(emptyList()))
    return SpaceAuthorization.restore(AuthorizationArchive(SignedGenesis(body, listOf(a, b).sortedBy { it.descriptor.deviceId }.map { DeviceSignature(it.descriptor.deviceId, it.sign(Canonical.encode(body))) }), emptyList()))
}
class MemoryStore : ReplicaStore {
    val facts = sortedMapOf<String, StoredRecord>(); val locals = mutableMapOf<String, ByteArray>(); val snapshots = mutableMapOf<String, List<InventoryEntry>>()
    override fun <T> transaction(block: () -> T): T { val f = facts.toMap(); val l = locals.toMap(); val s = snapshots.toMap(); try { return block() } catch (e: Throwable) { facts.clear(); facts.putAll(f); locals.clear(); locals.putAll(l); snapshots.clear(); snapshots.putAll(s); throw e } }
    override fun get(id: String) = facts[id]
    override fun sequence(epoch: String, sequence: Long) = facts.values.filter { it.record.authorized?.body?.let { b -> b.epochId == epoch && b.sequence == sequence } == true }
    override fun put(row: StoredRecord) { facts[row.id] = row }
    override fun rows(after: String?, limit: Int, acceptedOnly: Boolean) = facts.values.filter { (after == null || it.id > after) && (!acceptedOnly || it.accepted) }.take(limit)
    override fun local(key: String) = locals[key]
    override fun local(key: String, bytes: ByteArray) { locals[key] = bytes }
    override fun removeLocal(key: String) { locals.remove(key) }
    override fun snapshot(id: String, after: String?, page: List<InventoryEntry>?) { snapshots["$id/$after"] = page!! }
    override fun snapshot(id: String, after: String?) = snapshots["$id/$after"]
    override fun clearSnapshot(id: String) { snapshots.keys.removeAll { it.startsWith("$id/") } }
}
class ProtocolConformanceTest {
    @Test fun swiftProtocol4SignaturesAndExactDigests() {
        val f = fixture("replication-v4.json")
        val trust = SpaceAuthorization.restore(f.getValue("authorization").model())
        assertEquals(f.getValue("authorizationDigest").jsonPrimitive.content, trust.digest)
        val record = f.getValue("record").model<ReplicationRecord>()
        record.authorized!!.verify(trust)
        assertEquals(f.getValue("recordDigest").jsonPrimitive.content, sha256(Canonical.encode(record)))
        assertEquals(f.getValue("inventory"), record.entry.json())
        assertEquals(f.getValue("checkpoint"), checkpoint(listOf(record.entry)).json())
        val receipt = f.getValue("receipt").model<SignedAck>()
        receipt.verify(trust, trust.devices.getValue(receipt.body.deviceId).descriptor)
        f.getValue("frames").jsonArray.forEach { frame -> assertArrayEquals(Canonical.bytes(frame), Canonical.encode(frame.model<ReplicationFrame>())) }
    }
    @Test fun swiftEnrollmentOfferRequestCompletion() {
        val f = fixture("device-enrollment-v1.json")
        val offer = f.getValue("offer").model<EnrollmentOffer>(); val request = f.getValue("request").model<EnrollmentRequest>()
        val completion = f.getValue("completion").model<EnrollmentCompletion>()
        val trust = completion.verify(request, offer)
        assertTrue(trust.active(request.body.device))
        assertEquals(f.getValue("offerDigest").jsonPrimitive.content, offer.digest)
        assertEquals(f.getValue("requestDigest").jsonPrimitive.content, request.digest)
        assertEquals(f.getValue("offerCode").jsonPrimitive.content, offer.code)
        assertEquals(f.getValue("requestCode").jsonPrimitive.content, request.code)
        assertThrows(ProtocolException::class.java) { offer.verify(offer.body.expiresAt) }
        assertThrows(ProtocolException::class.java) { completion.copy(body = completion.body.copy(binding = completion.body.binding.copy(spaceId = uid()))).verify(request, offer) }
    }
    @Test fun legacyBytesRemainVerifiableWithoutPretendingToBeProtocol4() {
        val f = fixture("signed-log-v3.json"); val devices = f.getValue("devices").model<List<DeviceDescriptor>>().associateBy { it.deviceId }
        f.getValue("operations").model<List<SignedOperation>>().forEach { it.verify(devices.getValue(it.operation.deviceId)) }
        val old = f.getValue("operations").jsonArray.first().model<SignedOperation>()
        val a = identity(1); val b = identity(2); val replica = Replica(MemoryStore(), a, testTrust(a, b)).also { it.restore() }
        assertThrows(ProtocolException::class.java) { replica.receive(listOf(ReplicationRecord("legacy", legacy = old))) }
    }
    @Test fun graphemeBudgetsPreserveEmojiAndCombiningUserText() {
        assertEquals(1, "👨‍👩‍👧‍👦".graphemeCount()); assertEquals(1, "e\u0301".graphemeCount()); assertEquals(1, "🇨🇳".graphemeCount())
        assertEquals(2400, ("👨‍👩‍👧‍👦".repeat(400) + "a".repeat(2000)).graphemeCount())
    }
    @Test fun invalidCanonicalInputFailsClosed() {
        listOf("{\"a\":1,\"a\":2}", "{\"a\":1.0}", "[1e3]", "[-0]", "[9000000000000000]", "[\"\\ud800\"]", "[true,]").forEach { raw -> assertThrows(Exception::class.java) { Canonical.parse(raw.toByteArray()) } }
        assertEquals("{\"a\":\"中文 / ♡\\n\",\"b\":1}", Canonical.bytes(Canonical.parse("{\"b\":1,\"a\":\"中文 / ♡\\n\"}".toByteArray())).toString(Charsets.UTF_8))
    }
    @Test fun stableUUIDAndMediaHashFixture() {
        val f = fixture("conformance-v1.json")
        val id = f.getValue("stableID").jsonObject
        assertEquals(id.getValue("uuid").jsonPrimitive.content, stableId(id.getValue("seed").jsonPrimitive.content))
        val media = f.getValue("media").jsonObject
        assertEquals(media.getValue("sha256").jsonPrimitive.content, sha256(media.getValue("base64").jsonPrimitive.content.unbase64()))
    }
    @Test fun duplicateCollisionStagingAndDurableAck() {
        val f = fixture("replication-v4.json"); val trust = SpaceAuthorization.restore(f.getValue("authorization").model())
        val record = f.getValue("record").model<ReplicationRecord>()
        val replica = Replica(MemoryStore(), identity(1), testTrust(identity(1), identity(2))).also { it.restore() }
        val op = SyncOperation(uid(), replica.identity.descriptor.deviceId, replica.identity.descriptor.userId, uid(), "task", "create", 1, mapOf("title" to LogValue.string("Synthetic")), 1791532800000)
        val appended = replica.append(listOf(op)).single(); replica.receive(listOf(appended, appended)); assertEquals(1, replica.store.rows().size)
        val changed = appended.authorized!!.body.copy(signedOperation = replica.identity.sign(op.copy(payload = mapOf("title" to LogValue.string("Changed")))))
        val collision = ReplicationRecord("authorized", authorized = AuthorizedOperation(changed, replica.identity.sign(Canonical.encode(changed))))
        assertThrows(ProtocolException::class.java) { replica.receive(listOf(collision)) }
        assertEquals(1, replica.store.rows().size)
        record.authorized!!.verify(trust)
    }
    @Test fun paginatedBidirectionalSyncBeyondTenThousandAndRestartedAck() {
        val a = identity(11); val b = identity(12); val t = testTrust(a, b)
        val left = Replica(MemoryStore(), a, t).also { it.restore() }; val right = Replica(MemoryStore(), b, t).also { it.restore() }
        // 10,241 facts across both devices, unchanged page/batch limits; no 10k list cap.
        fun fill(r: Replica, n: Int) {
            (0 until n).chunked(32).forEach { indices -> r.append(indices.map { i -> SyncOperation(stableId("${r.identity.descriptor.deviceId}:op:$i"), r.identity.descriptor.deviceId, r.identity.descriptor.userId, stableId("entity-$i"), "task", "create", i + 1L, mapOf("title" to LogValue.string("Synthetic $i")), 1791532800000) }) }
        }
        fill(left, 10_200); fill(right, 41)
        val l = AntiEntropy(left, b.descriptor); val r = AntiEntropy(right, a.descriptor)
        val queue = ArrayDeque<Pair<Boolean, ReplicationFrame>>()
        l.start().forEach { queue.add(false to it) }; r.start().forEach { queue.add(true to it) }
        var steps = 0
        while (queue.isNotEmpty()) { require(++steps < 10000); val (toLeft, frame) = queue.removeFirst(); val response = if (toLeft) l.receive(frame) else r.receive(frame); response.forEach { queue.add(!toLeft to it) } }
        assertEquals(10_241, left.inventoryCheckpoint().count); assertEquals(left.inventoryCheckpoint(), right.inventoryCheckpoint())
        val first = left.store.rows().first().record.entry
        assertTrue(left.partnerPersisted(first))
        val reopened = Replica(left.store, a, t).also { it.restore() }
        assertTrue(reopened.partnerPersisted(first)); assertEquals(left.inventoryCheckpoint(), reopened.inventoryCheckpoint())
        l.close(); r.close()
    }
    @Test fun unauthorizedTamperAndReceiptCannotClaimLaterWrites() {
        val a = identity(5); val b = identity(6); val t = testTrust(a, b)
        val r = Replica(MemoryStore(), a, t).also { it.restore() }
        val c = r.inventoryCheckpoint()
        val body = AckBody(spaceId = t.spaceId, deviceId = b.descriptor.deviceId, epochId = t.devices.getValue(b.descriptor.deviceId).epochId, entries = emptyList(), checkpoint = c)
        val ack = SignedAck(body, b.sign(Canonical.encode(body)))
        assertTrue(r.acceptAck(ack, b.descriptor))
        r.append(listOf(SyncOperation(uid(), a.descriptor.deviceId, a.descriptor.userId, uid(), "task", "create", 1, emptyMap(), 1791532800000)))
        assertFalse(r.acceptAck(ack, b.descriptor)); assertFalse(r.partnerPersisted(r.store.rows().first().record.entry))
        assertThrows(ProtocolException::class.java) { r.acceptAck(ack.copy(signature = a.sign(Canonical.encode(body))), b.descriptor) }
    }
}

class DeviceSecurityTest {
    @Test fun enrollmentUsesIndependentKeysAndSameUserSpaceThenRevocationPinsHistory() {
        val a = identity(21); val b = identity(22); val prior = testTrust(a, b)
        val phone = identity(23, a.descriptor.userId, prior.spaceId)
        val eventBody = AuthorizationBody(spaceId = prior.spaceId, ownerId = a.descriptor.userId, revision = 1,
            previousDigest = prior.archive.genesis.digest, authorizerDeviceId = a.descriptor.deviceId, action = "grant", device = phone.descriptor, epochId = uid())
        val grant = AuthorizationEvent(eventBody, a.sign(Canonical.encode(eventBody)))
        val trust = SpaceAuthorization.restore(prior.archive.copy(events = listOf(grant)))
        assertEquals(a.descriptor.userId, phone.descriptor.userId); assertNotEquals(a.descriptor.publicKey, phone.descriptor.publicKey)
        assertEquals(prior.spaceId, trust.spaceId)
        val source = Replica(MemoryStore(), phone, trust).also { it.restore() }
        val proofs = source.append((1L..3L).map { n -> SyncOperation(stableId("phone-op-$n"), phone.descriptor.deviceId, phone.descriptor.userId, uid(), "task", "create", n, emptyMap(), 1791532800000) })
        val cutoff = Frontier(2, proofs[1].authorized!!.digest)
        val revokeBody = eventBody.copy(revision = 2, previousDigest = grant.digest, action = "revoke", cutoff = cutoff)
        val revoke = AuthorizationEvent(revokeBody, a.sign(Canonical.encode(revokeBody)))
        val revoked = SpaceAuthorization.restore(trust.archive.copy(events = listOf(grant, revoke)))
        val receiver = Replica(MemoryStore(), b, revoked).also { it.restore() }
        assertThrows(ProtocolException::class.java) { receiver.receive(listOf(proofs[2])) }
        receiver.receive(listOf(proofs[1])); assertEquals(0, receiver.inventoryCheckpoint().count)
        receiver.receive(listOf(proofs[0])); assertEquals(2, receiver.inventoryCheckpoint().count)
        assertEquals(prior.archive.genesis, revoked.archive.genesis)
        assertThrows(ProtocolException::class.java) { source.updateAuthorization(prior.archive) }
    }
    @Test fun forgedOwnerAndAuthorizationForkFail() {
        val a = identity(31); val b = identity(32); val t = testTrust(a, b); val phone = identity(33, a.descriptor.userId, t.spaceId)
        val body = AuthorizationBody(spaceId = t.spaceId, ownerId = a.descriptor.userId, revision = 1, previousDigest = t.archive.genesis.digest, authorizerDeviceId = a.descriptor.deviceId, action = "grant", device = phone.descriptor, epochId = uid())
        val forged = AuthorizationEvent(body, b.sign(Canonical.encode(body)))
        assertThrows(ProtocolException::class.java) { SpaceAuthorization.restore(t.archive.copy(events = listOf(forged))) }
        val fork = body.copy(revision = 2)
        assertThrows(ProtocolException::class.java) { SpaceAuthorization.restore(t.archive.copy(events = listOf(AuthorizationEvent(fork, a.sign(Canonical.encode(fork)))))) }
    }
    @Test fun encryptedChannelRejectsReplayTamperReflectionAndWrongIdentity() {
        val a = identity(41); val b = identity(42); val t = testTrust(a, b)
        val ae = ByteArray(32) { 71 }; val be = ByteArray(32) { 72 }
        val ah = SecureChannel.hello(a, ae, t); val bh = SecureChannel.hello(b, be, t)
        val left = SecureChannel(a, ae, ah, bh, t); val right = SecureChannel(b, be, bh, ah, t)
        assertEquals(left.transcript, right.transcript); left.consent().verify(a.descriptor, right.transcript)
        val packet = left.seal("synthetic private bytes".toByteArray())
        assertThrows(ProtocolException::class.java) { left.open(packet) }
        val cipher = packet.ciphertext!!.unbase64(); cipher[cipher.lastIndex] = (cipher.last().toInt() xor 1).toByte()
        assertThrows(Exception::class.java) { right.open(packet.copy(ciphertext = cipher.b64())) }
        assertEquals("synthetic private bytes", right.open(packet).toString(Charsets.UTF_8))
        assertThrows(ProtocolException::class.java) { right.open(packet) }
        val unrelated = identity(43); val bad = SecureChannel.hello(unrelated, Crypto.seed(), testTrust(unrelated, b))
        assertThrows(ProtocolException::class.java) { SecureChannel(a, ae, ah, bad, t) }
    }
    @Test fun tamperedLocalCheckpointMembershipCannotClaimPartnerPersisted() {
        val a = identity(51); val b = identity(52); val t = testTrust(a, b)
        val r = Replica(MemoryStore(), a, t).also { it.restore() }
        val record = r.append(listOf(SyncOperation(uid(), a.descriptor.deviceId, a.descriptor.userId, uid(), "task", "create", 1, emptyMap(), 1791532800000))).single()
        val body = AckBody(spaceId = t.spaceId, deviceId = b.descriptor.deviceId, epochId = t.devices.getValue(b.descriptor.deviceId).epochId, entries = emptyList(), checkpoint = r.inventoryCheckpoint())
        r.acceptAck(SignedAck(body, b.sign(Canonical.encode(body))), b.descriptor)
        assertTrue(r.partnerPersisted(record.entry))
        val key = "ack/${b.descriptor.deviceId}/${record.entry.operationId}"
        val membership = Canonical.parse(r.store.local(key)!!).model<AckMembership>()
        r.store.local(key, Canonical.encode(membership.copy(signature = a.sign("unrelated".toByteArray()))))
        assertFalse(r.partnerPersisted(record.entry))
    }
}

class ClientLifecycleTest {
    @Test fun concurrentForegroundRunsCannotOpenTwoSessionsDuringHTTP() = kotlinx.coroutines.runBlocking {
        val server = okhttp3.mockwebserver.MockWebServer()
        server.start()
        val a = identity(81); val b = identity(82); val t = testTrust(a, b)
        val challenge = "{\"id\":\"${uid()}\",\"nonce\":\"synthetic-nonce\",\"expiresAt\":1791532800000}"
        server.enqueue(okhttp3.mockwebserver.MockResponse().setBody(challenge).setHeadersDelay(1, java.util.concurrent.TimeUnit.SECONDS))
        server.enqueue(okhttp3.mockwebserver.MockResponse().setResponseCode(403).setBody("{\"error\":\"SERVICE_UNAVAILABLE\"}"))
        val r = Replica(MemoryStore(), a, t).also { it.restore() }
        val binding = C1Binding(server.url("/").toString().trimEnd('/'), t.spaceId, uid(), a.descriptor.deviceId)
        val client = C1Client(r, binding, RelayApi(binding, a, true))
        val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.IO)
        val first = scope.launch { client.run() }
        try {
            kotlinx.coroutines.withTimeout(5000) { while (server.requestCount == 0) kotlinx.coroutines.delay(10) }
            val second = scope.launch { client.run() }
            try {
                kotlinx.coroutines.delay(200)
                assertEquals(1, server.requestCount)
            } finally { second.cancel(); second.join() }
        } finally { first.cancel(); first.join(); scope.cancel(); server.shutdown() }
    }
}
