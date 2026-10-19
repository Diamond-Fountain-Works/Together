package com.together.protocol

import java.nio.ByteBuffer
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

@Serializable data class PartnerMember(val descriptor: DeviceDescriptor, val profileName: String)
@Serializable data class PartnerRoute(val routeId: String, val members: List<PartnerMember>, val expiresAt: Long,
    val paired: Boolean, val revoked: Boolean, val confirmed: List<String>, val pairingProtocol: Int? = null)
@Serializable data class PartnerInvitation(val code: String, val routeId: String, val expiresAt: Long)
@Serializable data class PartnerBootstrapFrame(val kind: String, val operations: List<SignedOperation>? = null,
    val checkpoint: Checkpoint? = null, val genesis: SignedGenesis? = null)
data class PartnerPairingState(val stage: String = "idle", val invitation: PartnerInvitation? = null,
    val peer: PartnerMember? = null, val verificationCode: String? = null, val error: String? = null,
    val diagnostic: String? = null)

/** Same CryptoKit-compatible Relay-1 framing already used by the Mac pairing
 * channel. It is limited to native partner-purpose routes, before Protocol 4. */
internal class PartnerSecureChannel(private val identity: DeviceIdentity, ephemeral: ByteArray,
    val local: SignedHello, val remote: SignedHello) {
    val transcript: String
    private val outgoing: ByteArray; private val incoming: ByteArray
    private var sent = 0L; private var received = 0L
    init {
        listOf(local, remote).forEach { hello ->
            val b = hello.body; b.descriptor.validate(); uuid(b.nonce)
            requireProtocol(b.protocolVersion == 1 && b.replicationVersion == null && b.authorizationDigest == null &&
                b.descriptor.protocolVersion in listOf(3, 4) && b.ephemeralKey.unbase64().size == 32 &&
                b.profileName.isNotBlank() && b.profileName.length <= 80 &&
                Crypto.verify(b.descriptor.publicKey.unbase64(), hello.signature.unbase64(), Canonical.encode(b)), "INVALID_RELAY_HELLO")
        }
        requireProtocol(local.body.descriptor == identity.descriptor && local.body.routeId == remote.body.routeId &&
            local.body.ephemeralKey == Crypto.xPublic(ephemeral).b64() &&
            remote.body.descriptor.deviceId != identity.descriptor.deviceId &&
            remote.body.descriptor.userId != identity.descriptor.userId, "INVALID_CHANNEL_IDENTITY")
        transcript = sha256(Canonical.encode(listOf(local, remote).sortedBy { it.body.descriptor.deviceId }))
        val salt = transcript.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val secret = Crypto.xSecret(ephemeral, remote.body.ephemeralKey.unbase64())
        val me = identity.descriptor.deviceId; val peer = remote.body.descriptor.deviceId
        outgoing = Crypto.hkdf(secret, salt, "Together-Relay-1:$me:$peer".toByteArray())
        incoming = Crypto.hkdf(secret, salt, "Together-Relay-1:$peer:$me".toByteArray()); secret.fill(0)
    }
    fun consent() = ConsentBody(transcript, identity.descriptor.deviceId).let { SignedConsent(it, identity.sign(Canonical.encode(it))) }
    fun seal(bytes: ByteArray): RelayPacket {
        requireProtocol(bytes.size < 360_000 && sent < 4_294_967_294L, "ENCRYPTION_BOUNDS")
        val h = CipherHeader(1, transcript, identity.descriptor.deviceId, remote.body.descriptor.deviceId, ++sent)
        val nonce = ByteBuffer.allocate(12).putInt(0).putLong(sent).array()
        return RelayPacket("encrypted", header = h, ciphertext = (nonce + Crypto.aead(true, outgoing, nonce, Canonical.encode(h), bytes)).b64())
    }
    fun open(packet: RelayPacket): ByteArray {
        val h = packet.header ?: throw ProtocolException("MISSING_CIPHER_HEADER")
        val bytes = packet.ciphertext?.unbase64() ?: throw ProtocolException("MISSING_CIPHERTEXT")
        requireProtocol(h.version == 1 && h.sessionId == transcript && h.senderId == remote.body.descriptor.deviceId &&
            h.recipientId == identity.descriptor.deviceId && h.sequence == received + 1 && bytes.size in 28 until 360_032,
            "REPLAY_OR_WRONG_SESSION")
        val clear = Crypto.aead(false, incoming, bytes.copyOfRange(0, 12), Canonical.encode(h), bytes.copyOfRange(12, bytes.size))
        received = h.sequence; return clear
    }
}

/** Persists only after both human consents; adapters serialize their own stores. */
interface PartnerHistory {
    suspend fun joinRequest(code: String): String = uid()
    suspend fun prepare(genesis: SignedGenesis) {}
    suspend fun pendingGenesis(): SignedGenesis? = null
    suspend fun rememberRoute(route: PartnerRoute) {}
    suspend fun pin(peer: DeviceDescriptor, route: PartnerRoute)
    suspend fun ownHistory(): List<SignedOperation>
    suspend fun importBatch(operations: List<SignedOperation>)
    suspend fun checkpoint(): Checkpoint
    suspend fun complete(authorization: AuthorizationArchive, binding: C1Binding)
}

class PartnerPairingClient(private val origin: String, private val identity: DeviceIdentity,
    private val name: String, parent: CoroutineScope, private val history: PartnerHistory,
    private val allowLocal: Boolean = false, private var pinned: DeviceDescriptor? = null) {
    private val scope = CoroutineScope(parent.coroutineContext + SupervisorJob(parent.coroutineContext[Job]))
    private val api = RelayApi.unpaired(origin, identity, allowLocal)
    private val transport: SyncTransport = OkHttpSyncTransport()
    private val gate = Mutex(); private val sendGate = Mutex()
    private val _state = MutableStateFlow(PartnerPairingState())
    val state = _state.asStateFlow()
    private var job: Job? = null; private var historyJob: Job? = null
    private var route: PartnerRoute? = null
    private var ephemeral = Crypto.seed()
    private var hello: SignedHello? = null
    private var channel: PartnerSecureChannel? = null
    private var localApproved = false; private var remoteApproved = false; private var present = false
    private var serverPaired = false; private var started = false
    private var sentHistory = false; private var receivedHistory = false
    private var expectedHistory: Checkpoint? = null; private var receivedHasher = InventoryHasher()
    private var receivedCount = 0; private var lastReceived: String? = null
    private var localGenesis: SignedGenesis? = null; private var remoteGenesis: SignedGenesis? = null
    private var sentReady = false; private var receivedReady = false; private var finished = false
    private var expectedAck: Checkpoint? = null; private var ack: CompletableDeferred<Unit>? = null
    private val seenHellos = mutableSetOf<String>()
    private var foreground = true

    suspend fun create() {
        _state.value = PartnerPairingState("creating")
        try {
            retryNetwork { api.requirePartnerService() }
            val invite = api.request("POST", "/v2/partner-invitations", Canonical.bytes(identityBody())).model<PartnerInvitation>()
            requireProtocol(Regex("[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{12}").matches(invite.code), "INVALID_INVITATION")
            _state.value = PartnerPairingState("waiting", invitation = invite)
            follow(invite.routeId)
        } catch (e: Exception) { failure(e); throw e }
    }
    suspend fun join(code: String) {
        _state.value = PartnerPairingState("joining")
        try {
            val normalized = code.trim().uppercase(java.util.Locale.ROOT).replace(Regex("[\\s-]"), "")
            requireProtocol(Regex("[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{12}").matches(normalized), "INVALID_INVITATION")
            retryNetwork { api.requirePartnerService() }
            val requestId = history.joinRequest(normalized)
            val body = Canonical.bytes(buildJsonObject {
                identityBody().forEach { (k, v) -> put(k, v) }; put("code", normalized); put("joinRequestId", requestId)
            })
            val value = retryNetwork { api.request("POST", "/v2/partner-invitations/join", body).model<PartnerRoute>() }
            validate(value); route = value; follow(value.routeId)
        } catch (e: Exception) { failure(e); throw e }
    }
    fun resume(routeId: String) { follow(uuid(routeId)) }
    fun foreground(value: Boolean) {
        foreground = value
        if (!value) { job?.cancel(); historyJob?.cancel(); transport.disconnect() }
        else if (job?.isActive != true && !finished) (route?.routeId ?: _state.value.invitation?.routeId)?.let(::follow)
    }
    fun stop() { scope.cancel(); transport.disconnect(); ephemeral.fill(0) }
    private fun identityBody() = buildJsonObject { put("descriptor", identity.descriptor.json()); put("profileName", name.trim().take(80)) }
    private fun failure(e: Exception) {
        if (e is CancellationException) return
        val diagnostic = generateSequence<Throwable>(e) { it.cause }.take(4).joinToString("/") { it.javaClass.simpleName }.take(160)
        _state.value = _state.value.copy(stage = "error", error = (e as? ProtocolException)?.code ?: "CONNECTION_FAILED", diagnostic = diagnostic)
    }
    private suspend fun <T> retryNetwork(action: () -> T): T {
        repeat(3) { attempt ->
            try { return action() }
            catch(e: java.io.IOException) { if(attempt==2) throw e; delay(1000L shl attempt) }
        }
        throw ProtocolException("CONNECTION_FAILED")
    }
    private fun validate(r: PartnerRoute) {
        uuid(r.routeId)
        requireProtocol(r.pairingProtocol == 4 && !r.revoked && r.members.size in 1..2 &&
            r.members.count { it.descriptor == identity.descriptor } == 1, "INVALID_PARTNER_ROUTE")
        r.members.forEach { it.descriptor.validate() }
        if (r.members.size == 2) {
            val peer = r.members.single { it.descriptor.deviceId != identity.descriptor.deviceId }.descriptor
            requireProtocol(peer.userId != identity.descriptor.userId && peer.publicKey != identity.descriptor.publicKey, "SAME_DEVICE")
            pinned?.let { requireProtocol(it == peer, "IDENTITY_MISMATCH") }
        }
    }
    private fun follow(routeId: String) {
        if (!foreground) return
        job?.cancel(); job = scope.launch {
            var attempt = 0
            while (isActive && !finished) {
                try {
                    history.pendingGenesis()?.let { genesis -> activate(genesis, routeId); return@launch }
                    var r = api.request("GET", "/v1/routes/$routeId").model<PartnerRoute>(); validate(r)
                    while (r.members.size != 2) {
                        delay(1000); r = api.request("GET", "/v1/routes/$routeId").model(); validate(r)
                    }
                    history.rememberRoute(r)
                    gate.withLock { route = r; resetHandshake(); serverPaired = r.paired }
                    val ticket = api.request("POST", "/v1/routes/$routeId/ticket", "{}".toByteArray(), 16384).model<RelayTicket>()
                    requireProtocol(ticket.routeId == routeId, "INVALID_TICKET")
                    transport.connect(api.partnerSocket(routeId), ticket.ticket)
                    sendPacket(RelayPacket("hello", hello = hello))
                    while (isActive && !finished) {
                        val message = transport.receive()
                        gate.withLock { receive(message) }
                    }
                } catch (e: CancellationException) { throw e }
                catch (e: Exception) { failure(e) }
                finally { historyJob?.cancelAndJoin(); historyJob = null; transport.disconnect() }
                if (!finished) delay(minOf(60_000L, 1000L shl minOf(attempt++, 6)))
            }
        }
    }
    private fun resetHandshake() {
        historyJob?.cancel(); started = false; channel = null; remoteApproved = false
        localApproved = pinned != null; present = false
        ephemeral.fill(0); ephemeral = Crypto.seed(); seenHellos.clear()
        val b = HelloBody(1, route!!.routeId, identity.descriptor, name.trim().take(80), Crypto.xPublic(ephemeral).b64(), uid(), null, null)
        hello = SignedHello(b, identity.sign(Canonical.encode(b)))
        sentHistory = false; receivedHistory = false; expectedHistory = null; receivedHasher = InventoryHasher()
        receivedCount = 0; lastReceived = null; localGenesis = null; remoteGenesis = null
        sentReady = false; receivedReady = false; expectedAck = null; ack = null
    }
    suspend fun confirm() = gate.withLock {
        val c = channel ?: throw ProtocolException("PAIRING_NOT_READY")
        val r = route ?: throw ProtocolException("PAIRING_NOT_READY")
        val confirmed = api.request("POST", "/v1/routes/${r.routeId}/confirm", Canonical.bytes(buildJsonObject { put("transcript", c.transcript) })).model<PartnerRoute>()
        validate(confirmed); serverPaired = confirmed.paired; localApproved = true
        _state.value = _state.value.copy(stage = "confirming")
        sendPacket(RelayPacket("consent", consent = c.consent())); beginIfReady()
    }
    private suspend fun sendPacket(packet: RelayPacket) = sendGate.withLock { transport.send(Canonical.encode(packet)) }
    private suspend fun sendFrame(frame: PartnerBootstrapFrame) = sendGate.withLock {
        val c = channel ?: throw ProtocolException("PAIRING_NOT_READY")
        transport.send(Canonical.encode(c.seal(Canonical.encode(frame))))
    }
    private suspend fun receive(bytes: ByteArray) {
        val value = Canonical.parse(bytes).jsonObject
        if (value["kind"]?.jsonPrimitive?.content == "status") {
            val online = value["online"]?.jsonPrimitive?.booleanOrNull == true
            serverPaired = value["paired"]?.jsonPrimitive?.booleanOrNull == true
            if (!online && present) resetHandshake()
            if (online && !present) sendPacket(RelayPacket("hello", hello = hello))
            present = online; beginIfReady(); return
        }
        if (value["kind"]?.jsonPrimitive?.content == "waiting") return
        val packet = value.model<RelayPacket>()
        when (packet.kind) {
            "hello" -> {
                val remote = packet.hello ?: throw ProtocolException("INVALID_RELAY_HELLO")
                requireProtocol(route!!.members.any { it.descriptor == remote.body.descriptor }, "IDENTITY_MISMATCH")
                if (channel?.remote == remote) return
                requireProtocol(seenHellos.size < 64 && seenHellos.add(sha256(Canonical.encode(remote))), "REPLAYED_HELLO")
                historyJob?.cancel(); started = false
                val c = PartnerSecureChannel(identity, ephemeral, hello!!, remote); channel = c
                remoteApproved = false; localApproved = pinned != null
                val member = route!!.members.single { it.descriptor.deviceId == remote.body.descriptor.deviceId }
                _state.value = _state.value.copy(stage = if (localApproved) "confirming" else "verifying", peer = member,
                    verificationCode = (c.transcript.take(8).toLong(16) % 1_000_000).toString().padStart(6, '0'), error = null)
                if (localApproved) sendPacket(RelayPacket("consent", consent = c.consent()))
                beginIfReady()
            }
            "consent" -> {
                val c = channel ?: throw ProtocolException("PAIRING_NOT_READY")
                packet.consent?.verify(c.remote.body.descriptor, c.transcript) ?: throw ProtocolException("INVALID_RELAY_CONSENT")
                remoteApproved = true; beginIfReady()
            }
            "encrypted" -> {
                requireProtocol(started && localApproved && remoteApproved && serverPaired, "UNAUTHENTICATED_CHANNEL")
                receiveFrame(Canonical.parse(channel!!.open(packet)).model())
            }
            else -> throw ProtocolException("INVALID_PAIRING_PACKET")
        }
    }
    private suspend fun beginIfReady() {
        if (started || !present || !serverPaired || !localApproved || !remoteApproved || channel == null) return
        val peer = channel!!.remote.body.descriptor
        history.pin(peer, route!!); pinned = peer; started = true
        _state.value = _state.value.copy(stage = "syncing", error = null)
        historyJob = scope.launch {
            try {
                val operations = history.ownHistory().sortedBy { it.operation.operationId }
                val initial = checkpoint(operations.map { InventoryEntry(it.operation.operationId, it.contentDigest) })
                sendFrame(PartnerBootstrapFrame("partner-history-start", checkpoint = initial))
                var batch = mutableListOf<SignedOperation>(); var size = 0
                suspend fun flush() {
                    if (batch.isEmpty()) return
                    val current = batch.toList(); val wanted = Checkpoint(current.size, sha256(Canonical.encode(current)))
                    val receipt = CompletableDeferred<Unit>()
                    gate.withLock { expectedAck = wanted; ack = receipt }
                    sendFrame(PartnerBootstrapFrame("partner-history", operations = current))
                    withTimeout(20_000) { receipt.await() }; batch.clear(); size = 0
                }
                for (operation in operations) {
                    val bytes = Canonical.encode(operation).size; requireProtocol(bytes < 230_000, "BATCH_BOUNDS")
                    if (batch.size == 32 || size + bytes > 230_000) flush()
                    batch.add(operation); size += bytes
                }
                flush(); sendFrame(PartnerBootstrapFrame("partner-history-end", checkpoint = initial))
                gate.withLock { sentHistory = true; prepareGenesis() }
            } catch (e: CancellationException) { throw e } catch (e: Exception) { failure(e); transport.disconnect() }
        }
    }
    private suspend fun receiveFrame(f: PartnerBootstrapFrame) {
        when (f.kind) {
            "partner-history-start" -> { requireProtocol(expectedHistory == null, "INVALID_INVENTORY_PAGE"); expectedHistory = f.checkpoint ?: throw ProtocolException("INVALID_CHECKPOINT"); expectedHistory!!.validate() }
            "partner-history" -> {
                val expected = expectedHistory ?: throw ProtocolException("INVALID_INVENTORY_PAGE")
                val operations = f.operations ?: throw ProtocolException("INVALID_RECORD")
                requireProtocol(!receivedHistory && operations.isNotEmpty() && operations.size <= 32 && Canonical.encode(f).size <= 240_000, "BATCH_BOUNDS")
                val peer = channel!!.remote.body.descriptor
                operations.forEach { operation ->
                    operation.verify(peer)
                    requireProtocol(lastReceived == null || lastReceived!! < operation.operation.operationId, "INVALID_INVENTORY_ORDER")
                    receivedHasher.add(InventoryEntry(operation.operation.operationId, operation.contentDigest))
                    lastReceived = operation.operation.operationId; receivedCount++
                }
                requireProtocol(receivedCount <= expected.count, "CONTENT_COLLISION")
                history.importBatch(operations)
                sendFrame(PartnerBootstrapFrame("partner-history-ack", checkpoint = Checkpoint(operations.size, sha256(Canonical.encode(operations)))))
            }
            "partner-history-ack" -> { requireProtocol(f.checkpoint == expectedAck, "INVALID_RECEIPT"); ack?.complete(Unit) ?: throw ProtocolException("INVALID_RECEIPT") }
            "partner-history-end" -> {
                requireProtocol(!receivedHistory && f.checkpoint == expectedHistory && receivedCount == expectedHistory?.count && receivedHasher.finish() == expectedHistory, "CONTENT_COLLISION")
                receivedHistory = true; prepareGenesis()
            }
            "partner-genesis", "partner-ready" -> {
                val genesis = f.genesis ?: throw ProtocolException("INVALID_GENESIS")
                val peer = channel!!.remote.body.descriptor
                val proof = genesis.signatures.singleOrNull { it.deviceId == peer.deviceId } ?: throw ProtocolException("INVALID_GENESIS_SIGNATURES")
                requireProtocol(genesis.signatures.map { it.deviceId }.distinct().size == genesis.signatures.size &&
                    genesis.signatures.all { it.deviceId in listOf(identity.descriptor.deviceId, peer.deviceId) } &&
                    Crypto.verify(peer.publicKey.unbase64(), proof.signature.unbase64(), Canonical.encode(genesis.body)), "INVALID_GENESIS_SIGNATURES")
                requireProtocol(remoteGenesis == null || remoteGenesis!!.body == genesis.body, "CONTENT_COLLISION")
                remoteGenesis = genesis; if (f.kind == "partner-ready") receivedReady = true
                advanceGenesis()
            }
            else -> throw ProtocolException("INVALID_PAIRING_FRAME")
        }
    }
    private suspend fun prepareGenesis() {
        if (!sentHistory || !receivedHistory || localGenesis != null) return
        val roots = listOf(identity.descriptor, channel!!.remote.body.descriptor).sortedBy { it.deviceId }
        val space = stableId("space:" + roots.joinToString(":") { it.deviceId })
        val body = GenesisBody(4, space, roots.map { it.userId }.sorted(), roots,
            (roots.map { it.initialSpaceId } + space).distinct().sorted(), roots.first().initialTimeZoneIdentifier ?: "Etc/UTC", history.checkpoint())
        localGenesis = SignedGenesis(body, listOf(DeviceSignature(identity.descriptor.deviceId, identity.sign(Canonical.encode(body)))))
        sendFrame(PartnerBootstrapFrame("partner-genesis", genesis = localGenesis)); advanceGenesis()
    }
    private suspend fun advanceGenesis() {
        val own = localGenesis ?: return; val other = remoteGenesis ?: return
        requireProtocol(own.body == other.body, "INVENTORY_CHANGED")
        val peer = channel!!.remote.body.descriptor
        val genesis = SignedGenesis(own.body, listOf(own.signatures.single(), other.signatures.single { it.deviceId == peer.deviceId }).sortedBy { it.deviceId })
        genesis.verify()
        history.prepare(genesis)
        if (!sentReady) { sendFrame(PartnerBootstrapFrame("partner-ready", genesis = genesis)); sentReady = true }
        if (!receivedReady || finished) return
        activate(genesis, route!!.routeId)
    }
    private suspend fun activate(genesis: SignedGenesis, routeId: String) {
        genesis.verify()
        requireProtocol(genesis.body.roots.any { it == identity.descriptor } &&
            genesis.body.legacyCheckpoint == history.checkpoint(), "INVENTORY_CHANGED")
        val archive = AuthorizationArchive(genesis, emptyList())
        val space = api.request("POST", "/v2/spaces", Canonical.bytes(buildJsonObject {
            put("legacyRouteId", routeId); put("authorization", archive.json())
        })).model<RelaySpace>()
        space.verify(identity.descriptor, SpaceAuthorization.restore(archive))
        history.complete(space.archive, C1Binding(origin, genesis.body.spaceId, routeId, identity.descriptor.deviceId))
        finished = true; _state.value = _state.value.copy(stage = "paired", invitation = null, error = null)
    }
}
