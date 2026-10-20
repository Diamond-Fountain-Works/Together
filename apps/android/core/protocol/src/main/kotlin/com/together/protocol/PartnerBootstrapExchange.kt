package com.together.protocol

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Storage boundary shared by the existing C1 and native transport adapters. */
interface PartnerBootstrapHistory {
    suspend fun prepare(genesis: SignedGenesis) {}
    suspend fun ownHistory(): List<SignedOperation>
    suspend fun importBatch(operations: List<SignedOperation>)
    suspend fun checkpoint(): Checkpoint
}

/** The existing partner-history/genesis exchange, extracted without wire changes.
 * It starts only after both signed human consents have been verified. */
internal class PartnerBootstrapExchange(private val identity: DeviceIdentity, private val remote: DeviceDescriptor,
    parent: CoroutineScope, private val history: PartnerBootstrapHistory,
    private val send: suspend (PartnerBootstrapFrame) -> Unit,
    private val complete: suspend (SignedGenesis) -> Unit, private val failed: (Exception) -> Unit,
    private val acknowledgementTimeoutMillis: Long = 20_000L) {
    init { requireProtocol(acknowledgementTimeoutMillis in 1..20_000L, "INVALID_ACK_TIMEOUT") }
    private val scope = CoroutineScope(parent.coroutineContext + SupervisorJob(parent.coroutineContext[Job]))
    private val gate = Mutex()
    private var job: Job? = null
    private var sentHistory = false; private var receivedHistory = false
    private var expectedHistory: Checkpoint? = null; private var receivedHasher = InventoryHasher()
    private var receivedCount = 0; private var lastReceived: String? = null
    private var localGenesis: SignedGenesis? = null; private var remoteGenesis: SignedGenesis? = null
    private var sentReady = false; private var receivedReady = false; private var finished = false
    private var expectedAck: Checkpoint? = null; private var ack: CompletableDeferred<Unit>? = null

    fun stop() { scope.cancel() }
    fun start() {
        requireProtocol(job == null, "PAIRING_ALREADY_STARTED")
        job = scope.launch {
            try {
                val operations = history.ownHistory().sortedBy { it.operation.operationId }
                val initial = checkpoint(operations.map { InventoryEntry(it.operation.operationId, it.contentDigest) })
                send(PartnerBootstrapFrame("partner-history-start", checkpoint = initial))
                val batch = mutableListOf<SignedOperation>(); var size = 0
                suspend fun flush() {
                    if (batch.isEmpty()) return
                    val current = batch.toList(); val wanted = Checkpoint(current.size, sha256(Canonical.encode(current)))
                    val receipt = CompletableDeferred<Unit>()
                    gate.withLock { expectedAck = wanted; ack = receipt }
                    send(PartnerBootstrapFrame("partner-history", operations = current))
                    // Expiry of our receipt deadline is a protocol failure, not
                    // cancellation of the App/session owner. Preserve parent cancellation.
                    val persisted = withTimeoutOrNull(acknowledgementTimeoutMillis) { receipt.await(); true }
                    requireProtocol(persisted == true, "PARTNER_HISTORY_ACK_TIMEOUT")
                    batch.clear(); size = 0
                }
                for (operation in operations) {
                    val bytes = Canonical.encode(operation).size; requireProtocol(bytes < 230_000, "BATCH_BOUNDS")
                    if (batch.size == 32 || size + bytes > 230_000) flush()
                    batch.add(operation); size += bytes
                }
                flush(); send(PartnerBootstrapFrame("partner-history-end", checkpoint = initial))
                gate.withLock { sentHistory = true; prepareGenesis() }
            } catch (e: CancellationException) { throw e } catch (e: Exception) { failed(e) }
        }
    }
    suspend fun receive(f: PartnerBootstrapFrame) = gate.withLock {
        requireProtocol(scope.isActive, "PAIRING_CANCELLED")
        if (finished) return@withLock
        when (f.kind) {
            "partner-history-start" -> { requireProtocol(expectedHistory == null, "INVALID_INVENTORY_PAGE"); expectedHistory = f.checkpoint ?: throw ProtocolException("INVALID_CHECKPOINT"); expectedHistory!!.validate() }
            "partner-history" -> {
                val expected = expectedHistory ?: throw ProtocolException("INVALID_INVENTORY_PAGE")
                val operations = f.operations ?: throw ProtocolException("INVALID_RECORD")
                requireProtocol(!receivedHistory && operations.isNotEmpty() && operations.size <= 32 && Canonical.encode(f).size <= 240_000, "BATCH_BOUNDS")
                operations.forEach { operation ->
                    operation.verify(remote)
                    requireProtocol(lastReceived == null || lastReceived!! < operation.operation.operationId, "INVALID_INVENTORY_ORDER")
                    receivedHasher.add(InventoryEntry(operation.operation.operationId, operation.contentDigest))
                    lastReceived = operation.operation.operationId; receivedCount++
                }
                requireProtocol(receivedCount <= expected.count, "CONTENT_COLLISION")
                history.importBatch(operations)
                send(PartnerBootstrapFrame("partner-history-ack", checkpoint = Checkpoint(operations.size, sha256(Canonical.encode(operations)))))
            }
            "partner-history-ack" -> { requireProtocol(f.checkpoint == expectedAck, "INVALID_RECEIPT"); ack?.complete(Unit) ?: throw ProtocolException("INVALID_RECEIPT") }
            "partner-history-end" -> {
                requireProtocol(!receivedHistory && f.checkpoint == expectedHistory && receivedCount == expectedHistory?.count && receivedHasher.finish() == expectedHistory, "CONTENT_COLLISION")
                receivedHistory = true; prepareGenesis()
            }
            "partner-genesis", "partner-ready" -> {
                val genesis = f.genesis ?: throw ProtocolException("INVALID_GENESIS")
                val proof = genesis.signatures.singleOrNull { it.deviceId == remote.deviceId } ?: throw ProtocolException("INVALID_GENESIS_SIGNATURES")
                requireProtocol(genesis.signatures.map { it.deviceId }.distinct().size == genesis.signatures.size &&
                    genesis.signatures.all { it.deviceId in listOf(identity.descriptor.deviceId, remote.deviceId) } &&
                    Crypto.verify(remote.publicKey.unbase64(), proof.signature.unbase64(), Canonical.encode(genesis.body)), "INVALID_GENESIS_SIGNATURES")
                requireProtocol(remoteGenesis == null || remoteGenesis!!.body == genesis.body, "CONTENT_COLLISION")
                remoteGenesis = genesis; if (f.kind == "partner-ready") receivedReady = true
                advanceGenesis()
            }
            else -> throw ProtocolException("INVALID_PAIRING_FRAME")
        }
    }
    private suspend fun prepareGenesis() {
        if (!sentHistory || !receivedHistory || localGenesis != null) return
        val roots = listOf(identity.descriptor, remote).sortedBy { it.deviceId }
        val space = stableId("space:" + roots.joinToString(":") { it.deviceId })
        val body = GenesisBody(4, space, roots.map { it.userId }.sorted(), roots,
            (roots.map { it.initialSpaceId } + space).distinct().sorted(), roots.first().initialTimeZoneIdentifier ?: "Etc/UTC", history.checkpoint())
        localGenesis = SignedGenesis(body, listOf(DeviceSignature(identity.descriptor.deviceId, identity.sign(Canonical.encode(body)))))
        send(PartnerBootstrapFrame("partner-genesis", genesis = localGenesis)); advanceGenesis()
    }
    private suspend fun advanceGenesis() {
        val own = localGenesis ?: return; val other = remoteGenesis ?: return
        requireProtocol(own.body == other.body, "INVENTORY_CHANGED")
        val genesis = SignedGenesis(own.body, listOf(own.signatures.single(), other.signatures.single { it.deviceId == remote.deviceId }).sortedBy { it.deviceId })
        genesis.verify(); history.prepare(genesis)
        if (!sentReady) { send(PartnerBootstrapFrame("partner-ready", genesis = genesis)); sentReady = true }
        if (!receivedReady || finished) return
        finished = true; complete(genesis)
    }
}
