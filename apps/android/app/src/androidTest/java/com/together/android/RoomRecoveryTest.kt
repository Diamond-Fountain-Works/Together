package com.together.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.*
import com.together.protocol.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant

@RunWith(AndroidJUnit4::class)
class RoomRecoveryTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun identity(i: Int) = DeviceIdentity.create(ByteArray(32) { (it + i).toByte() }, stableId("room-user-$i"), stableId("room-initial-$i"), stableId("room-device-$i"), "Synthetic Room $i", "Asia/Shanghai")
    private fun trust(a: DeviceIdentity, b: DeviceIdentity): SpaceAuthorization {
        val space = stableId("room-space")
        val body = GenesisBody(4, space, listOf(a.descriptor.userId, b.descriptor.userId).sorted(), listOf(a.descriptor, b.descriptor).sortedBy { it.deviceId }, listOf(space, a.descriptor.initialSpaceId, b.descriptor.initialSpaceId).sorted(), "Asia/Shanghai", checkpoint(emptyList()))
        val genesis = SignedGenesis(body, listOf(a, b).sortedBy { it.descriptor.deviceId }.map { DeviceSignature(it.descriptor.deviceId, it.sign(Canonical.encode(body))) })
        return SpaceAuthorization.restore(AuthorizationArchive(genesis, emptyList()))
    }
    @Test fun factsProofsAckAndStagingSurviveDatabaseReopen() {
        val name = "qa-${uid()}.db"; val a = identity(1); val b = identity(2); val t = trust(a, b)
        var db = TogetherDatabase.open(context, name)
        try {
            var store = RoomReplicaStore(db); var replica = Replica(store, a, t).also { it.restore() }
            val op = SyncOperation(uid(), a.descriptor.deviceId, a.descriptor.userId, uid(), "task", "create", 1, mapOf("title" to LogValue.string("Synthetic Room record")), Instant.parse("2026-10-09T04:00:00Z").toEpochMilli())
            val record = replica.append(listOf(op)).single()
            store.local("authorization", Canonical.encode(t.archive))
            val body = AckBody(spaceId = t.spaceId, deviceId = b.descriptor.deviceId, epochId = t.devices.getValue(b.descriptor.deviceId).epochId, entries = listOf(record.entry))
            assertTrue(replica.acceptAck(SignedAck(body, b.sign(Canonical.encode(body))), b.descriptor))
            db.close(); db = TogetherDatabase.open(context, name); store = RoomReplicaStore(db)
            val reloaded = SpaceAuthorization.restore(Canonical.parse(store.local("authorization")!!).model())
            replica = Replica(store, a, reloaded).also { it.restore() }
            assertEquals(1, replica.inventoryCheckpoint().count); assertTrue(replica.partnerPersisted(record.entry))
            replica.receive(listOf(record)); assertEquals(1, db.dao().count())
            val conflicting = op.copy(payload = mapOf("title" to LogValue.string("Collision")))
            val signed = a.sign(conflicting)
            val alteredBody = record.authorized!!.body.copy(signedOperation = signed)
            val altered = ReplicationRecord("authorized", authorized = AuthorizedOperation(alteredBody, a.sign(Canonical.encode(alteredBody))))
            assertThrows(ProtocolException::class.java) { replica.receive(listOf(altered)) }
            assertEquals(record, store.get(op.operationId)!!.record)
        } finally { db.close(); context.deleteDatabase(name) }
    }
    @Test fun roomTransactionRollsBackBothFactsAndMetadata() {
        val name = "qa-${uid()}.db"; val db = TogetherDatabase.open(context, name)
        try {
            val s = RoomReplicaStore(db)
            assertThrows(IllegalStateException::class.java) { s.transaction { s.local("only-this-test", byteArrayOf(1)); throw IllegalStateException("synthetic failure") } }
            assertNull(s.local("only-this-test")); assertEquals(0, db.dao().count())
        } finally { db.close(); context.deleteDatabase(name) }
    }
    @Test fun androidKeystoreWrapPreservesIndependentIdentity() {
        val slot = "QA-${uid()}"; val owner = uid(); val space = uid()
        val store = AndroidIdentityStore(context); val original = store.create(slot, owner, space, "Synthetic Keystore device", "Asia/Shanghai")
        val message = "Synthetic verification message".toByteArray()
        val reopened = AndroidIdentityStore(context).load(slot)
        assertEquals(original.descriptor, reopened.descriptor)
        assertTrue(Crypto.verify(original.descriptor.publicKey.unbase64(), reopened.sign(message).unbase64(), message))
        assertThrows(ProtocolException::class.java) { store.create(slot, owner, space, "Duplicate", "Asia/Shanghai") }
        assertThrows(ProtocolException::class.java) { store.load("QA-${uid()}") }
    }
}
