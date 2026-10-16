package com.together.protocol

/** Calls are serialized by Replica; Android adapter executes them on Dispatchers.IO.
 * Facts and metadata commit atomically. Projections/cache may always be rebuilt. */
interface ReplicaStore {
    fun <T> transaction(block: () -> T): T
    fun get(id: String): StoredRecord?
    fun sequence(epoch: String, sequence: Long): List<StoredRecord>
    fun put(row: StoredRecord)
    fun rows(after: String? = null, limit: Int = 128, acceptedOnly: Boolean = true): List<StoredRecord>
    fun local(key: String): ByteArray?
    fun local(key: String, bytes: ByteArray)
    fun removeLocal(key: String)
    fun snapshot(id: String, after: String?, page: List<InventoryEntry>?)
    fun snapshot(id: String, after: String?): List<InventoryEntry>?
    fun clearSnapshot(id: String)
}
data class StoredRecord(val record: ReplicationRecord, val accepted: Boolean) {
    val id get() = record.operation.operation.operationId
}

/** Immutable signed facts; unlinked authorized/legacy records remain durable staging.
 * No wall-clock authorization or last-Lamport completeness shortcut. */
class Replica(val store: ReplicaStore, val identity: DeviceIdentity, trust: SpaceAuthorization) {
    var trust: SpaceAuthorization = trust; private set
    init { requireProtocol(trust.active(identity.descriptor), "DEVICE_NOT_AUTHORIZED") }
    @Synchronized fun updateAuthorization(archive: AuthorizationArchive) {
        val next = SpaceAuthorization.restore(archive)
        requireProtocol(next.extends(trust), "STALE_AUTHORIZATION")
        if (next.archive == trust.archive) { store.transaction { store.local("authorization", Canonical.encode(next.archive)) }; return }
        store.transaction {
            store.local("authorization", Canonical.encode(next.archive))
            // Reclassify every proof, including revoked forks; history is kept, never destroyed.
            forEachRow(false) { store.put(it.copy(accepted = false)) }; next.devices.values.forEach { store.local("head/${it.epochId}", Canonical.encode(Frontier())) }
            val old = trust; trust = next
            try { promote() } catch (e: Exception) { trust = old; throw e }
        }
    }
    @Synchronized fun restore() { store.transaction {
        forEachRow(false) { row ->
            val r = row.record
            if (r.kind == "legacy") {
                val root = trust.archive.genesis.body.roots.singleOrNull { it.deviceId == r.operation.operation.deviceId } ?: throw ProtocolException("INVALID_LEGACY_DEVICE")
                r.operation.verify(root)
            } else {
                // A revoked beyond-frontier fact is retained but hidden after trust updates.
                val d = trust.devices[r.operation.operation.deviceId] ?: throw ProtocolException("UNAUTHORIZED_DEVICE")
                if (d.revokedAt == null || r.authorized!!.body.sequence <= d.revokedAt.sequence) r.authorized!!.verify(trust)
            }
            store.put(row.copy(accepted = false))
        }
        trust.devices.values.forEach { store.local("head/${it.epochId}", Canonical.encode(Frontier())) }
        store.removeLocal("legacy-seal"); promote()
    } }
    @Synchronized fun receive(records: List<ReplicationRecord>) {
        requireProtocol(records.size <= 32 && Canonical.encode(records).size <= 240_000, "BATCH_BOUNDS")
        store.transaction {
            records.forEach { r ->
                val op = r.operation.operation
                if (r.kind == "legacy") {
                    val root = trust.archive.genesis.body.roots.singleOrNull { it.deviceId == op.deviceId } ?: throw ProtocolException("INVALID_LEGACY_DEVICE")
                    r.operation.verify(root)
                    requireProtocol(op.actorId == root.userId, "INVALID_LEGACY_ACTOR")
                } else {
                    r.authorized!!.verify(trust)
                    val sameSequence = store.sequence(r.authorized.body.epochId, r.authorized.body.sequence)
                    requireProtocol(sameSequence.all { it.record == r }, "DEVICE_SEQUENCE_FORK")
                }
                val old = store.get(op.operationId)
                requireProtocol(old == null || old.record == r, "CONTENT_COLLISION")
                if (old == null) store.put(StoredRecord(r, false))
                val max = maxOf(localLong("lamport"), op.lamportClock); store.local("lamport", max.toString().toByteArray())
            }
            promote()
        }
    }
    @Synchronized fun append(operations: List<SyncOperation>): List<ReplicationRecord> = store.transaction {
        requireProtocol(trust.active(identity.descriptor) && legacyComplete(), "HISTORY_NOT_READY")
        var head = frontier(identity.descriptor.deviceId)
        val device = trust.devices.getValue(identity.descriptor.deviceId)
        val result = operations.map { op ->
            requireProtocol(store.get(op.operationId) == null, "DUPLICATE_LOCAL_ID")
            val signed = identity.sign(op); signed.verify(device.descriptor)
            requireProtocol(head.sequence < 8_999_999_999_999_999L, "SEQUENCE_EXHAUSTED")
            val b = AuthorizedBody(spaceId = trust.spaceId, epochId = device.epochId, sequence = head.sequence + 1, previousDigest = head.digest, signedOperation = signed)
            val a = AuthorizedOperation(b, identity.sign(Canonical.encode(b)))
            val record = ReplicationRecord("authorized", authorized = a)
            requireProtocol(Canonical.encode(listOf(record)).size <= 240_000, "BATCH_BOUNDS")
            store.put(StoredRecord(record, true)); head = Frontier(b.sequence, a.digest)
            store.local("lamport", maxOf(op.lamportClock, localLong("lamport")).toString().toByteArray()); record
        }
        store.local("head/${device.epochId}", Canonical.encode(head)); result
    }
    @Synchronized fun <T> atomicCommand(block: () -> T): T = store.transaction(block)
    @Synchronized fun nextClock(): Long = Math.addExact(localLong("lamport"), 1).also { requireProtocol(it < 9_000_000_000_000_000L, "CLOCK_EXHAUSTED") }
    private fun localLong(key: String) = store.local(key)?.toString(Charsets.UTF_8)?.toLong() ?: 0
    @Synchronized fun legacyComplete(): Boolean = store.local("legacy-seal")?.toString(Charsets.UTF_8) == trust.archive.genesis.body.legacyCheckpoint.digest
    @Synchronized fun frontier(deviceId: String): Frontier {
        val device = trust.devices[deviceId] ?: throw ProtocolException("UNKNOWN_DEVICE")
        return store.local("head/${device.epochId}")?.let { Canonical.parse(it).model<Frontier>().also { f -> f.validate() } } ?: Frontier()
    }
    private fun forEachRow(acceptedOnly: Boolean, block: (StoredRecord) -> Unit) {
        var cursor: String? = null
        while (true) {
            val rows = store.rows(cursor, 128, acceptedOnly); if (rows.isEmpty()) return
            rows.forEach(block); cursor = rows.last().id
        }
    }
    private fun promote() {
        if (!legacyComplete()) {
            val legacy = mutableListOf<StoredRecord>()
            forEachRow(false) { if (it.record.kind == "legacy") legacy.add(it) }
            val wanted = trust.archive.genesis.body.legacyCheckpoint
            requireProtocol(legacy.size <= wanted.count, "LEGACY_CHECKPOINT_MISMATCH")
            if (legacy.size == wanted.count) {
                requireProtocol(checkpoint(legacy.map { it.record.entry }) == wanted, "LEGACY_CHECKPOINT_MISMATCH")
                legacy.forEach { store.put(it.copy(accepted = true)) }
                store.local("legacy-seal", wanted.digest.toByteArray())
            }
        }
        if (!legacyComplete()) return
        trust.devices.values.forEach { d ->
            var head = frontier(d.descriptor.deviceId)
            if (d.revokedAt != null) {
                if (head == d.revokedAt) return@forEach
                var cursor = d.revokedAt; val chain = mutableListOf<StoredRecord>()
                while (cursor!!.sequence > 0) {
                    val row = store.sequence(d.epochId, cursor.sequence).singleOrNull { it.record.authorized!!.digest == cursor!!.digest } ?: break
                    row.record.authorized!!.verify(trust)
                    chain.add(row); cursor = Frontier(cursor.sequence - 1, row.record.authorized.body.previousDigest)
                }
                if (cursor == Frontier()) { chain.forEach { store.put(it.copy(accepted = true)) }; head = d.revokedAt }
            } else {
                while (true) {
                    val candidates = store.sequence(d.epochId, head.sequence + 1)
                    requireProtocol(candidates.size <= 1, "DEVICE_SEQUENCE_FORK")
                    val row = candidates.singleOrNull() ?: break
                    val a = row.record.authorized!!
                    requireProtocol(a.body.previousDigest == head.digest, "DEVICE_SEQUENCE_FORK")
                    store.put(row.copy(accepted = true)); head = Frontier(a.body.sequence, a.digest)
                }
            }
            store.local("head/${d.epochId}", Canonical.encode(head))
        }
    }
    @Synchronized fun missing(entries: List<InventoryEntry>): List<InventoryEntry> = entries.filter { e ->
        e.validate(); val found = store.get(e.operationId)
        requireProtocol(found == null || found.record.entry == e, "CONTENT_COLLISION")
        found == null
    }
    @Synchronized fun accepted(entries: List<InventoryEntry>): List<InventoryEntry> = entries.filter { e -> store.get(e.operationId)?.let { it.accepted && it.record.entry == e } == true }
    @Synchronized fun inventoryCheckpoint(): Checkpoint {
        val h = InventoryHasher(); forEachRow(true) { h.add(it.record.entry) }; return h.finish()
    }
    @Synchronized fun createSnapshot(id: String): Checkpoint = store.transaction {
        val pages = mutableListOf<InventoryEntry>(); var cursor: String? = null; val h = InventoryHasher()
        forEachRow(true) { row ->
            val entry = row.record.entry; h.add(entry); pages.add(entry)
            if (pages.size == 128) { store.snapshot(id, cursor, pages.toList()); cursor = pages.last().operationId; pages.clear() }
        }
        store.snapshot(id, cursor, pages.toList()); h.finish()
    }
    @Synchronized fun receipt(entries: List<InventoryEntry>): SignedAck? {
        requireProtocol(trust.active(identity.descriptor) && entries.size <= 32, "INVALID_RECEIPT")
        val persisted = accepted(entries); if (persisted.isEmpty()) return null
        val b = AckBody(spaceId = trust.spaceId, deviceId = identity.descriptor.deviceId, epochId = trust.devices.getValue(identity.descriptor.deviceId).epochId, entries = persisted.sortedBy { it.operationId })
        return SignedAck(b, identity.sign(Canonical.encode(b)))
    }
    @Synchronized fun convergenceReceipt(c: Checkpoint): SignedAck? {
        if (inventoryCheckpoint() != c || !trust.active(identity.descriptor)) return null
        val b = AckBody(spaceId = trust.spaceId, deviceId = identity.descriptor.deviceId, epochId = trust.devices.getValue(identity.descriptor.deviceId).epochId, entries = emptyList(), checkpoint = c)
        return SignedAck(b, identity.sign(Canonical.encode(b)))
    }
    @Synchronized fun acceptAck(receipt: SignedAck, remote: DeviceDescriptor): Boolean = store.transaction {
        receipt.verify(trust, remote)
        val b = receipt.body
        if (b.checkpoint != null && inventoryCheckpoint() != b.checkpoint) return@transaction false
        if (b.checkpoint == null) requireProtocol(accepted(b.entries).size == b.entries.size, "INVALID_RECEIPT")
        store.local("ack-proof/${receipt.digest}", Canonical.encode(receipt))
        fun save(entry: InventoryEntry) {
            val body = AckMembershipBody(localDeviceId = identity.descriptor.deviceId, remoteDeviceId = remote.deviceId, entry = entry, receiptDigest = receipt.digest)
            store.local("ack/${remote.deviceId}/${entry.operationId}", Canonical.encode(AckMembership(body, identity.sign(Canonical.encode(body)))))
        }
        if (b.checkpoint != null) forEachRow(true) { save(it.record.entry) } else b.entries.forEach(::save)
        true
    }
    @Synchronized fun persistedDevices(entry: InventoryEntry): Set<String> = trust.devices.values.filter { d ->
        if (!d.active) return@filter false
        val raw = store.local("ack/${d.descriptor.deviceId}/${entry.operationId}") ?: return@filter false
        val m = Canonical.parse(raw).model<AckMembership>()
        if (m.body.localDeviceId != identity.descriptor.deviceId || m.body.remoteDeviceId != d.descriptor.deviceId || m.body.purpose != "Together-Android-Ack-Membership-1" || !Crypto.verify(identity.descriptor.publicKey.unbase64(), m.signature.unbase64(), Canonical.encode(m.body))) return@filter false
        val proof = store.local("ack-proof/${m.body.receiptDigest}")?.let { Canonical.parse(it).model<SignedAck>() } ?: return@filter false
        if (runCatching { proof.verify(trust, d.descriptor) }.isFailure || m.body.entry != entry || proof.digest != m.body.receiptDigest) return@filter false
        // Checkpoint membership is bound to the immutable local entry at acceptance. Android's
        // signed local membership protects this cache; remote proofs remain independently verified.
        proof.body.checkpoint != null || entry in proof.body.entries
    }.map { it.descriptor.deviceId }.toSet()
    @Synchronized fun partnerPersisted(entry: InventoryEntry) = persistedDevices(entry).any { trust.devices[it]?.descriptor?.userId != identity.descriptor.userId }
}
@kotlinx.serialization.Serializable data class AckMembershipBody(val purpose: String = "Together-Android-Ack-Membership-1", val localDeviceId: String, val remoteDeviceId: String, val entry: InventoryEntry, val receiptDigest: String)
@kotlinx.serialization.Serializable data class AckMembership(val body: AckMembershipBody, val signature: String)
