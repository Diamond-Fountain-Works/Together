package com.together.protocol

/** Synthetic test-only adapter, not application persistence. */
class MemoryStore : ReplicaStore {
    val facts = sortedMapOf<String, StoredRecord>()
    val locals = mutableMapOf<String, ByteArray>()
    val snapshots = mutableMapOf<String, List<InventoryEntry>>()

    @Synchronized
    override fun <T> transaction(block: () -> T): T {
        val f = facts.toMap()
        val l = locals.toMap()
        val s = snapshots.toMap()
        try {
            return block()
        } catch (e: Throwable) {
            facts.clear()
            facts.putAll(f)
            locals.clear()
            locals.putAll(l)
            snapshots.clear()
            snapshots.putAll(s)
            throw e
        }
    }

    @Synchronized override fun get(id: String) = facts[id]

    @Synchronized
    override fun sequence(epoch: String, sequence: Long) =
        facts.values.filter {
            it.record.authorized?.body?.let { b -> b.epochId == epoch && b.sequence == sequence } ==
                true
        }

    @Synchronized
    override fun put(row: StoredRecord) {
        facts[row.id] = row
    }

    @Synchronized
    override fun rows(after: String?, limit: Int, acceptedOnly: Boolean) =
        facts.values
            .filter { (after == null || it.id > after) && (!acceptedOnly || it.accepted) }
            .take(limit)

    @Synchronized override fun local(key: String) = locals[key]

    @Synchronized
    override fun local(key: String, bytes: ByteArray) {
        locals[key] = bytes
    }

    @Synchronized
    override fun removeLocal(key: String) {
        locals.remove(key)
    }

    @Synchronized
    override fun snapshot(id: String, after: String?, page: List<InventoryEntry>?) {
        snapshots["$id/$after"] = page!!
    }

    @Synchronized override fun snapshot(id: String, after: String?) = snapshots["$id/$after"]

    @Synchronized
    override fun clearSnapshot(id: String) {
        snapshots.keys.removeAll { it.startsWith("$id/") }
    }
}
