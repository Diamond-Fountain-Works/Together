package com.together.protocol

import kotlinx.serialization.Serializable

@Serializable data class ReplicationFrame(val kind: String, val hintId: String? = null, val passId: String? = null,
    val requestId: String? = null, val page: InventoryPage? = null, val cursor: String? = null,
    val entries: List<InventoryEntry>? = null, val records: List<ReplicationRecord>? = null,
    val checkpoint: Checkpoint? = null, val receipt: SignedAck? = null)

/** One outstanding bounded request, pinned snapshots, bidirectional pulls. A session
 * is disposable; only facts, authorization, exact ACK proofs and review survive. */
class AntiEntropy(private val replica: Replica, private val remote: DeviceDescriptor) : AutoCloseable {
    private data class Outbound(val checkpoint: Checkpoint, var expectedCursor: String? = null, var advertised: Set<InventoryEntry> = emptySet())
    private data class Pending(val requestId: String, val entries: List<InventoryEntry>)
    private var outbound: Pair<String, Outbound>? = null
    private var pass: String? = null
    private var checkpoint: Checkpoint? = null
    private var after: String? = null
    private var seen = 0
    private var hasher = InventoryHasher()
    private var currentPage: InventoryPage? = null
    private val missing = ArrayDeque<InventoryEntry>()
    private var pending: Pending? = null
    private var requested = false
    private var restartRequested = false
    var converged: Boolean = false; private set
    fun start(): List<ReplicationFrame> {
        if (requested) return emptyList()
        requested = true; pass = uid(); checkpoint = null; after = null; seen = 0; hasher = InventoryHasher(); currentPage = null; pending = null; missing.clear(); converged = false
        return listOf(ReplicationFrame("inventoryStart", passId = pass))
    }
    fun localChanged(): List<ReplicationFrame> { converged = false; return listOf(ReplicationFrame("syncHint", hintId = uid())) }
    fun receive(f: ReplicationFrame): List<ReplicationFrame> {
        requireProtocol(replica.trust.active(remote), "DEVICE_REVOKED")
        return when (f.kind) {
            "syncHint" -> { uuid(f.hintId ?: throw ProtocolException("INVALID_FRAME")); if (requested) { restartRequested = true; emptyList() } else start() }
            "inventoryStart" -> {
                val id = uuid(f.passId ?: throw ProtocolException("INVALID_FRAME"))
                outbound?.let { replica.store.clearSnapshot(it.first) }
                val c = replica.createSnapshot(id); outbound = id to Outbound(c)
                listOf(sendPage(id, null))
            }
            "inventoryNext" -> {
                val o = outbound ?: throw ProtocolException("UNEXPECTED_PASS")
                requireProtocol(o.first == f.passId && f.cursor != null && o.second.expectedCursor == f.cursor, "INVALID_CURSOR")
                listOf(sendPage(o.first, f.cursor))
            }
            "inventoryPage" -> {
                requireProtocol(requested && f.passId == pass && pending == null && currentPage == null, "UNEXPECTED_PAGE")
                val p = f.page ?: throw ProtocolException("INVALID_PAGE"); p.validate()
                requireProtocol(p.after == after && (checkpoint == null || checkpoint == p.checkpoint), "INVENTORY_CHANGED")
                checkpoint = p.checkpoint; p.entries.forEach { hasher.add(it); seen++ }
                requireProtocol(seen <= p.checkpoint.count, "INVALID_INVENTORY_COUNT")
                currentPage = p; missing.addAll(replica.missing(p.entries)); next()
            }
            "operationRequest" -> {
                val o = outbound ?: throw ProtocolException("UNEXPECTED_PASS")
                val e = f.entries ?: throw ProtocolException("INVALID_REQUEST")
                requireProtocol(f.passId == o.first && f.requestId != null && e.isNotEmpty() && e.size <= 32 && e.distinct().size == e.size, "INVALID_REQUEST")
                // Only entries in this pinned inventory may be requested; later writes cannot leak into a pass.
                val result = mutableListOf<ReplicationRecord>()
                for (entry in e) {
                    entry.validate(); requireProtocol(entry in o.second.advertised, "UNADVERTISED_ENTRY")
                    val row = replica.store.get(entry.operationId) ?: throw ProtocolException("INVENTORY_CHANGED")
                    requireProtocol(row.accepted && row.record.entry == entry, "CONTENT_COLLISION")
                    val proposed = result + row.record
                    if (Canonical.encode(proposed).size > 240_000) break
                    result.add(row.record)
                }
                requireProtocol(result.isNotEmpty(), "BATCH_BOUNDS")
                listOf(ReplicationFrame("operationBatch", passId = o.first, requestId = f.requestId, records = result))
            }
            "operationBatch" -> {
                val p = pending ?: throw ProtocolException("UNSOLICITED_OPERATION_BATCH")
                val records = f.records ?: throw ProtocolException("INVALID_BATCH")
                requireProtocol(f.passId == pass && f.requestId == p.requestId && records.isNotEmpty() && records.size <= p.entries.size && records.map { it.entry } == p.entries.take(records.size), "UNEXPECTED_BATCH_CONTENT")
                replica.receive(records) // actual durable transaction before generating ACK
                pending = null
                val rest = p.entries.drop(records.size)
                for (entry in rest.asReversed()) missing.addFirst(entry)
                val ack = replica.receipt(records.map { it.entry })
                (ack?.let { listOf(ReplicationFrame("acknowledgement", receipt = it)) } ?: emptyList()) + next()
            }
            "inventoryFinished" -> {
                val o = outbound ?: throw ProtocolException("UNEXPECTED_PASS")
                requireProtocol(o.first == f.passId && o.second.checkpoint == f.checkpoint, "INVALID_CHECKPOINT")
                val c = f.checkpoint!!
                val ack = replica.convergenceReceipt(c)
                replica.store.clearSnapshot(o.first); outbound = null
                (ack?.let { listOf(ReplicationFrame("acknowledgement", receipt = it)) } ?: listOf(ReplicationFrame("syncHint", hintId = uid())))
            }
            "acknowledgement" -> {
                val ack = f.receipt ?: throw ProtocolException("INVALID_RECEIPT")
                val accepted = replica.acceptAck(ack, remote)
                if (accepted && ack.body.checkpoint != null) converged = true
                emptyList()
            }
            else -> throw ProtocolException("INCOMPATIBLE_REPLICATION_PROTOCOL")
        }
    }
    private fun sendPage(id: String, cursor: String?): ReplicationFrame {
        val o = outbound!!.second
        val e = replica.store.snapshot(id, cursor) ?: throw ProtocolException("INVALID_CURSOR")
        val next = if (e.size == 128 && replica.store.snapshot(id, e.last().operationId)?.isNotEmpty() == true) e.last().operationId else null
        o.expectedCursor = next; o.advertised = e.toSet()
        return ReplicationFrame("inventoryPage", passId = id, page = InventoryPage(o.checkpoint, e, cursor, next))
    }
    private fun next(): List<ReplicationFrame> {
        if (missing.isNotEmpty()) {
            val batch = mutableListOf<InventoryEntry>(); repeat(minOf(32, missing.size)) { batch.add(missing.removeFirst()) }
            pending = Pending(uid(), batch)
            return listOf(ReplicationFrame("operationRequest", passId = pass, requestId = pending!!.requestId, entries = batch))
        }
        val p = currentPage ?: throw ProtocolException("MISSING_PAGE")
        currentPage = null
        if (p.next != null) { after = p.next; return listOf(ReplicationFrame("inventoryNext", passId = pass, cursor = after)) }
        requireProtocol(seen == checkpoint!!.count && hasher.finish() == checkpoint, "INVENTORY_DIGEST_MISMATCH")
        requested = false
        val f = ReplicationFrame("inventoryFinished", passId = pass, checkpoint = checkpoint)
        val ack = replica.convergenceReceipt(checkpoint!!)
        val restart = if (restartRequested) { restartRequested = false; start() } else emptyList()
        return listOf(f) + restart + (ack?.let { listOf(ReplicationFrame("acknowledgement", receipt = it)) } ?: listOf(ReplicationFrame("syncHint", hintId = uid())))
    }
    override fun close() { outbound?.let { replica.store.clearSnapshot(it.first) }; outbound = null; requested = false; pending = null; missing.clear() }
}
