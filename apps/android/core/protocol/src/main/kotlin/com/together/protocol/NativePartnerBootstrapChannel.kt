package com.together.protocol

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

interface NativePartnerHistory : PartnerBootstrapHistory { suspend fun pin(peer: DeviceDescriptor) }

/** Adapter over the existing signed hello, consent and partner bootstrap.
 * Native endpoint/contact verification belongs to the transport before start. */
class NativePartnerBootstrapChannel(private val identity: DeviceIdentity, name: String,
    invitationId: String, private val remote: DeviceDescriptor, parent: CoroutineScope,
    private val history: NativePartnerHistory, private val send: suspend (ByteArray) -> Unit,
    private val complete: suspend (SignedGenesis) -> Unit, private val proposal: (String) -> Unit,
    private val failed: (Exception) -> Unit) {
    private val scope = CoroutineScope(parent.coroutineContext + SupervisorJob(parent.coroutineContext[Job]))
    private val gate = Mutex(); private val sendGate = Mutex()
    private val ephemeral = Crypto.seed()
    private val hello: SignedHello
    private var channel: PartnerSecureChannel? = null
    private var bootstrap: PartnerBootstrapExchange? = null
    private var localApproved = false; private var remoteApproved = false; private var started = false
    var verificationCode: String? = null; private set
    var remoteDisplayName: String? = null; private set
    init {
        uuid(invitationId); remote.validate()
        requireProtocol(remote.deviceId != identity.descriptor.deviceId && remote.userId != identity.descriptor.userId &&
            remote.protocolVersion in listOf(3, 4) && name.isNotBlank() && name.graphemeCount() <= 80, "INVALID_CHANNEL_IDENTITY")
        val body = HelloBody(1, invitationId, identity.descriptor, name, Crypto.xPublic(ephemeral).b64(), uid(), null, null)
        hello = SignedHello(body, identity.sign(Canonical.encode(body)))
    }
    fun stop() { bootstrap?.stop(); scope.cancel(); ephemeral.fill(0) }
    suspend fun start() = gate.withLock {
        requireProtocol(scope.isActive && !started, "PAIRING_ALREADY_STARTED")
        started = true; sendPacket(RelayPacket("hello", hello = hello))
    }
    suspend fun confirm(verified: Boolean) = gate.withLock {
        val c = channel ?: throw ProtocolException("PAIRING_NOT_READY")
        requireProtocol(scope.isActive && verified && !localApproved, "CONFIRMATION_REQUIRED")
        localApproved = true; sendPacket(RelayPacket("consent", consent = c.consent())); beginIfReady()
    }
    suspend fun receive(bytes: ByteArray) = gate.withLock {
        requireProtocol(scope.isActive && started && bytes.size <= 360_032, "PAIRING_NOT_READY")
        val packet = Canonical.parse(bytes).model<RelayPacket>()
        when (packet.kind) {
            "hello" -> {
                val peer = packet.hello ?: throw ProtocolException("INVALID_RELAY_HELLO")
                requireProtocol(channel == null && peer.body.descriptor == remote, "IDENTITY_MISMATCH")
                val c = PartnerSecureChannel(identity, ephemeral, hello, peer); channel = c
                val code = (c.transcript.take(8).toLong(16) % 1_000_000).toString().padStart(6, '0')
                verificationCode = code; remoteDisplayName = peer.body.profileName; proposal(code)
            }
            "consent" -> {
                val c = channel ?: throw ProtocolException("PAIRING_NOT_READY")
                requireProtocol(!remoteApproved, "REPLAYED_CONSENT")
                (packet.consent ?: throw ProtocolException("INVALID_RELAY_CONSENT")).verify(remote, c.transcript)
                remoteApproved = true; beginIfReady()
            }
            "encrypted" -> {
                requireProtocol(localApproved && remoteApproved, "UNAUTHENTICATED_CHANNEL")
                val exchange = bootstrap ?: throw ProtocolException("PAIRING_NOT_READY")
                exchange.receive(Canonical.parse(channel!!.open(packet)).model())
            }
            else -> throw ProtocolException("INVALID_PAIRING_PACKET")
        }
    }
    private suspend fun sendPacket(packet: RelayPacket) = sendGate.withLock { send(Canonical.encode(packet)) }
    private suspend fun beginIfReady() {
        if (!localApproved || !remoteApproved || bootstrap != null) return
        history.pin(remote)
        bootstrap = PartnerBootstrapExchange(identity, remote, scope, history,
            send = { frame -> sendGate.withLock { send(Canonical.encode(channel!!.seal(Canonical.encode(frame)))) } },
            complete = complete, failed = failed).also { it.start() }
    }
}
