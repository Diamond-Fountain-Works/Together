package com.together.protocol

import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class NativeTransportPartnerTest {
    @Test fun sharedContactFixtureMatchesSwiftAndRejectsTamperExpiryAndEndpointSubstitution() {
        val fixture = Canonical.parse(File(System.getProperty("together.fixtures"), "native-partner-contact-v1.json").readBytes()).jsonObject
        val contact = fixture.getValue("contact").model<NativePartnerContact>()
        val now = fixture.getValue("nowMs").jsonPrimitive.long
        contact.verify(now)
        assertEquals(28_800_000L, contact.body.expiresAt - contact.body.issuedAt)
        assertEquals(fixture.getValue("bodyCanonical").jsonPrimitive.content, Canonical.encode(contact.body).toString(Charsets.UTF_8))
        assertThrows(Exception::class.java) { contact.verify(contact.body.expiresAt) }
        assertThrows(Exception::class.java) { contact.verify(now, expectedInvitationId = uid()) }
        assertThrows(Exception::class.java) { contact.verify(now, connectedEndpointId = "b".repeat(64)) }
        assertThrows(Exception::class.java) { contact.copy(body = contact.body.copy(relayURL = "https://other.invalid/")).verify(now) }
        assertThrows(Exception::class.java) { contact.copy(body = contact.body.copy(expiresAt = Long.MIN_VALUE)).verify(now) }
        contact.verifySignature(connectedEndpointId = contact.body.endpointId)
        val synthetic = DeviceIdentity.create(Crypto.seed(), name = "Synthetic legacy", zone = "Asia/Shanghai")
        val current = NativePartnerContact.issue(synthetic, uid(), "b".repeat(64), "https://relay.example.invalid/", emptyList(), now)
        val oldBody = current.body.copy(expiresAt = current.body.issuedAt + 600_000)
        val legacy = NativePartnerContact(oldBody, synthetic.sign(Canonical.encode(oldBody)))
        legacy.verifySignature()
        assertThrows(Exception::class.java) { legacy.verify(now) }
    }

    @Test fun missingHistoryAckReportsFailureWhileOwnerCancellationDoesNot() = runBlocking {
        val a = DeviceIdentity.create(Crypto.seed(), name = "Synthetic A", zone = "Asia/Shanghai")
        val b = DeviceIdentity.create(Crypto.seed(), name = "Synthetic B", zone = "Asia/Shanghai")
        val operation = a.sign(SyncOperation(uid(), a.descriptor.deviceId, a.descriptor.userId, uid(), "task", "create", 1,
            mapOf("spaceId" to LogValue.string(a.descriptor.initialSpaceId), "createdBy" to LogValue.string(a.descriptor.userId),
                "title" to LogValue.string("Synthetic ACK timeout")), 1_791_532_800_000))
        val history = object : PartnerBootstrapHistory {
            override suspend fun ownHistory() = listOf(operation)
            override suspend fun importBatch(operations: List<SignedOperation>) = Unit
            override suspend fun checkpoint() = checkpoint(listOf(InventoryEntry(operation.operation.operationId, operation.contentDigest)))
        }
        val scope = CoroutineScope(coroutineContext + SupervisorJob())
        val failed = CompletableDeferred<Exception>()
        val exchange = PartnerBootstrapExchange(a, b.descriptor, scope, history, send = {},
            complete = { fail("Missing ACK cannot complete pairing") }, failed = { failed.complete(it) }, acknowledgementTimeoutMillis = 20)
        try {
            exchange.start()
            assertEquals("PARTNER_HISTORY_ACK_TIMEOUT", (withTimeout(2_000) { failed.await() } as ProtocolException).code)
        } finally { exchange.stop() }
        val sent = CompletableDeferred<Unit>(); val cancellationFailure = CompletableDeferred<Exception>()
        val cancelled = PartnerBootstrapExchange(a, b.descriptor, scope, history,
            send = { if (it.kind == "partner-history") sent.complete(Unit) }, complete = {},
            failed = { cancellationFailure.complete(it) })
        try {
            cancelled.start(); withTimeout(2_000) { sent.await() }; cancelled.stop(); delay(150)
            assertFalse("Owner cancellation must not become a protocol failure", cancellationFailure.isCompleted)
        } finally { cancelled.stop(); scope.cancel() }
    }

    @Test fun twoHumanConsentsGateExistingBatchedHistoryAndCoSignedGenesis() = runBlocking {
        fun identity(version: Int): DeviceIdentity {
            val seed = Crypto.seed()
            return DeviceIdentity(DeviceIdentity.create(seed, name = "Synthetic QA", zone = "Asia/Shanghai").descriptor.copy(protocolVersion = version), seed)
        }
        val a = identity(3); val b = identity(4)
        class History(val identity: DeviceIdentity) : NativePartnerHistory {
            val store = MemoryStore(); var peer: DeviceDescriptor? = null; var prepared: SignedGenesis? = null
            init { repeat(65) { n ->
                val op = identity.sign(SyncOperation(uid(), identity.descriptor.deviceId, identity.descriptor.userId, uid(), "task", "create", n + 1L,
                    mapOf("spaceId" to LogValue.string(identity.descriptor.initialSpaceId), "createdBy" to LogValue.string(identity.descriptor.userId), "title" to LogValue.string("Synthetic task $n")), 1_791_532_800_000))
                store.put(StoredRecord(ReplicationRecord("legacy", legacy = op), true))
            } }
            override suspend fun pin(peer: DeviceDescriptor) { requireProtocol(this.peer == null, "ALREADY_PAIRED"); this.peer = peer }
            override suspend fun ownHistory() = store.facts.values.map { it.record.operation }.filter { it.operation.deviceId == identity.descriptor.deviceId }
            override suspend fun importBatch(operations: List<SignedOperation>) { store.transaction { operations.forEach { it.verify(peer!!); store.put(StoredRecord(ReplicationRecord("legacy", legacy = it), true)) } } }
            override suspend fun checkpoint() = checkpoint(store.facts.values.map { it.record.entry })
            override suspend fun prepare(genesis: SignedGenesis) { genesis.verify(); assertEquals(checkpoint(), genesis.body.legacyCheckpoint); prepared = genesis }
        }
        val ah = History(a); val bh = History(b); val invitation = uid()
        val toA = Channel<ByteArray>(Channel.UNLIMITED); val toB = Channel<ByteArray>(Channel.UNLIMITED)
        val scope = CoroutineScope(coroutineContext + SupervisorJob())
        val errors = mutableListOf<Exception>(); val finished = mutableListOf<SignedGenesis>()
        suspend fun completed(history: History, genesis: SignedGenesis) {
            assertEquals(history.prepared, genesis)
            val trust = SpaceAuthorization.restore(AuthorizationArchive(genesis, emptyList()))
            Replica(history.store, history.identity, trust).restore(); finished.add(genesis)
        }
        val left = NativePartnerBootstrapChannel(a, "Synthetic Mac", invitation, b.descriptor, scope, ah,
            send = { toB.send(it) }, complete = { completed(ah, it) }, proposal = {}, failed = { errors.add(it) })
        val right = NativePartnerBootstrapChannel(b, "Synthetic Android", invitation, a.descriptor, scope, bh,
            send = { toA.send(it) }, complete = { completed(bh, it) }, proposal = {}, failed = { errors.add(it) })
        val readers = listOf(scope.launch { for (bytes in toA) left.receive(bytes) }, scope.launch { for (bytes in toB) right.receive(bytes) })
        try {
            left.start(); right.start()
            withTimeout(5_000) { while (left.verificationCode == null || right.verificationCode == null) delay(5) }
            assertEquals(left.verificationCode, right.verificationCode)
            assertEquals("Synthetic Android", left.remoteDisplayName)
            assertTrue(runCatching { left.confirm(false) }.isFailure)
            left.confirm(true); delay(30)
            assertNull(ah.peer); assertNull(bh.peer)
            right.confirm(true)
            withTimeout(10_000) { while (finished.size != 2 && errors.isEmpty()) delay(5) }
            assertTrue(errors.toString(), errors.isEmpty())
            assertEquals(2, finished.size); assertEquals(finished.first(), finished.last())
            assertEquals(130, ah.checkpoint().count); assertEquals(ah.checkpoint(), bh.checkpoint())
            assertEquals(a.descriptor, finished.first().body.roots.single { it.deviceId == a.descriptor.deviceId })
            assertEquals(b.descriptor, finished.first().body.roots.single { it.deviceId == b.descriptor.deviceId })
        } finally { left.stop(); right.stop(); readers.forEach { it.cancelAndJoin() }; scope.cancel(); toA.close(); toB.close() }
    }
}
