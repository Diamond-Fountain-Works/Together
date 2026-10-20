package com.together.android.p2p

import com.together.protocol.*
import computer.iroh.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.net.URI
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicBoolean

/** Native adapter bundled only into the dedicated, isolated nativeQa application. */
data class AppP2PAddress(val endpointId: String, val relayURL: String?, val directAddresses: List<String>) {
    fun native(): EndpointAddr {
        requireProtocol(Regex("[0-9a-f]{64}").matches(endpointId) && directAddresses.size <= 32 && directAddresses.all { it.toByteArray().size <= 128 }, "INVALID_P2P_ADDRESS")
        relayURL?.let {
            val u = URI(it)
            requireProtocol(it.length <= 2048 && u.scheme == "https" && u.host != null && u.userInfo == null && u.query == null && u.fragment == null, "INVALID_P2P_RELAY")
        }
        return EndpointAddr(EndpointId.fromString(endpointId), relayURL, directAddresses)
    }
    fun json() = buildJsonObject {
        put("endpointId", endpointId); relayURL?.let { put("relayURL", it) }
        put("directAddresses", JsonArray(directAddresses.map(::JsonPrimitive)))
    }
    companion object {
        fun parse(value: JsonElement): AppP2PAddress {
            val o = value.jsonObject
            return AppP2PAddress(o.getValue("endpointId").jsonPrimitive.content,
                o["relayURL"]?.jsonPrimitive?.contentOrNull,
                o.getValue("directAddresses").jsonArray.map { it.jsonPrimitive.content }).also { it.native().close() }
        }
        fun from(endpoint: Endpoint): AppP2PAddress = endpoint.addr().let { a ->
            try { AppP2PAddress(a.id().toString(), a.relayUrl(), a.directAddresses()) } finally { a.close() }
        }
    }
}

/** CanonicalJSON matches Swift PeerTransportBinding exactly; a QUIC certificate is not membership. */
class AppP2PBinding private constructor(val value: JsonObject) {
    val body = value.getValue("body").jsonObject
    val device = body.getValue("device").model<DeviceDescriptor>()
    val endpointId = body.getValue("endpointId").jsonPrimitive.content
    fun verify(connectedId: String, trust: SpaceAuthorization) {
        requireProtocol(body.getValue("version").jsonPrimitive.int == 1 &&
            body.getValue("transport").jsonPrimitive.content == "iroh-quic" &&
            body.getValue("spaceId").jsonPrimitive.content == trust.spaceId &&
            body.getValue("authorizationDigest").jsonPrimitive.content == trust.digest &&
            trust.active(device) && endpointId == connectedId && Regex("[0-9a-f]{64}").matches(endpointId) &&
            trust.devices.values.none { d -> d.descriptor.publicKey.unbase64().joinToString("") { "%02x".format(it) } == endpointId } &&
            Crypto.verify(device.publicKey.unbase64(), value.getValue("signature").jsonPrimitive.content.unbase64(), Canonical.bytes(body)), "INVALID_P2P_BINDING")
    }
    companion object {
        fun parse(o: JsonElement) = AppP2PBinding(o.jsonObject)
        fun issue(identity: DeviceIdentity, id: String, trust: SpaceAuthorization): AppP2PBinding {
            val body = buildJsonObject {
                put("version", 1); put("transport", "iroh-quic"); put("spaceId", trust.spaceId)
                put("device", identity.descriptor.json()); put("endpointId", id); put("authorizationDigest", trust.digest)
            }
            return AppP2PBinding(buildJsonObject { put("body", body); put("signature", identity.sign(Canonical.bytes(body))) }).also { it.verify(id, trust) }
        }
    }
}

class AppP2PCipher(private val identity: DeviceIdentity, private val remote: AppP2PBinding,
    connectedId: String, private val trust: SpaceAuthorization) {
    private val ephemeral = Crypto.seed()
    private val localHello: SignedHello = SecureChannel.hello(identity, ephemeral, trust)
    val hello: ByteArray = Canonical.encode(RelayPacket("hello", hello = localHello))
    private var channel: SecureChannel? = null
    var authenticated = false; private set
    init {
        remote.verify(connectedId, trust)
        requireProtocol(trust.active(identity.descriptor) && remote.device.deviceId != identity.descriptor.deviceId, "UNAUTHORIZED_P2P")
    }
    private fun current() = requireProtocol(trust.active(identity.descriptor) && trust.active(remote.device) &&
        remote.body.getValue("authorizationDigest").jsonPrimitive.content == trust.digest, "STALE_P2P_AUTHORIZATION")
    fun handshake(bytes: ByteArray): ByteArray? {
        current(); requireProtocol(!authenticated && bytes.size <= 16_384, "P2P_HANDSHAKE_BOUNDS")
        val packet = Canonical.parse(bytes).model<RelayPacket>()
        return when (packet.kind) {
            "hello" -> {
                val hello = packet.hello ?: throw ProtocolException("MISSING_P2P_HELLO")
                requireProtocol(channel == null && hello.body.descriptor == remote.device, "P2P_DESCRIPTOR_MISMATCH")
                val c = SecureChannel(identity, ephemeral, localHello, hello, trust); channel = c
                Canonical.encode(RelayPacket("consent", consent = c.consent()))
            }
            "consent" -> {
                val c = channel ?: throw ProtocolException("P2P_EARLY_CONSENT")
                (packet.consent ?: throw ProtocolException("P2P_MISSING_CONSENT")).verify(remote.device, c.transcript)
                authenticated = true; ephemeral.fill(0); null
            }
            else -> throw ProtocolException("INVALID_P2P_HANDSHAKE")
        }
    }
    fun seal(bytes: ByteArray): ByteArray {
        current(); requireProtocol(authenticated, "P2P_NOT_AUTHENTICATED")
        return Canonical.encode(channel!!.seal(bytes))
    }
    fun open(bytes: ByteArray): ByteArray {
        current(); requireProtocol(authenticated && bytes.size <= 524_288, "P2P_NOT_AUTHENTICATED")
        return channel!!.open(Canonical.parse(bytes).model())
    }
}

/** One reader and serialized bounded writers, exact Swift 4-byte BE frame format. */
class AppP2PStream(val connection: Connection, private val bi: BiStream) {
    private val writer = Mutex()
    private val reader = Mutex()
    private val queuedFrames = AtomicInteger()
    private val queuedBytes = AtomicInteger()
    private val closed = AtomicBoolean()
    var requireRelayPathForQa = false
    private var relayFrameChecks = 0
    private var sentFrames = 0
    private var receivedFrames = 0
    val relayPathEveryFrameVerified get() = requireRelayPathForQa && relayFrameChecks > 0 && sentFrames > 0 && receivedFrames > 0
    private fun verifyRelayPath() {
        if (!requireRelayPathForQa) return
        val selected = connection.paths().filter { it.isSelected }
        requireProtocol(selected.isNotEmpty() && selected.all { it.isRelay && !it.isIp }, "QA_SELECTED_PATH_IS_NOT_RELAY")
        relayFrameChecks++
    }
    suspend fun send(bytes: ByteArray) {
        requireProtocol(bytes.isNotEmpty() && bytes.size <= 524_288, "P2P_FRAME_BOUNDS")
        val frames = queuedFrames.incrementAndGet(); val total = queuedBytes.addAndGet(bytes.size)
        try {
            requireProtocol(frames <= 64 && total <= 8_388_608, "P2P_QUEUE_BOUNDS")
            writer.withLock {
                requireProtocol(!closed.get(), "P2P_CLOSED")
                verifyRelayPath()
                bi.send().writeAll(ByteBuffer.allocate(4 + bytes.size).putInt(bytes.size).put(bytes).array())
                verifyRelayPath(); sentFrames++
            }
        } finally { queuedFrames.decrementAndGet(); queuedBytes.addAndGet(-bytes.size) }
    }
    suspend fun receive(): ByteArray = reader.withLock {
        requireProtocol(!closed.get(), "P2P_CLOSED")
        verifyRelayPath()
        val n = ByteBuffer.wrap(bi.recv().readExact(4u)).int
        requireProtocol(n in 1..524_288, "P2P_FRAME_BOUNDS")
        val bytes = bi.recv().readExact(n.toUInt())
        verifyRelayPath(); receivedFrames++; bytes
    }
    fun paths(): JsonArray = JsonArray(connection.paths().map { p -> buildJsonObject {
        put("selected", p.isSelected); put("direct", p.isIp); put("relayed", p.isRelay); put("rttMilliseconds", p.rttMs.toLong())
    } })
    fun close() {
        if (!closed.compareAndSet(false, true)) return
        try { connection.close(0, byteArrayOf()) }
        finally { try { bi.close() } finally { connection.close() } }
    }
    companion object {
        val alpn = "together/p4/c1-content/1".toByteArray()
        suspend fun connect(endpoint: Endpoint, remote: AppP2PAddress): AppP2PStream {
            val address = remote.native()
            val conn = try { endpoint.connect(address, alpn) } finally { address.close() }
            return try {
                requireProtocol(conn.remoteId().toString() == remote.endpointId && conn.alpn().contentEquals(alpn), "WRONG_P2P_ENDPOINT")
                AppP2PStream(conn, conn.openBi())
            } catch (e: Throwable) { conn.close(1, byteArrayOf()); conn.close(); throw e }
        }
        suspend fun accept(endpoint: Endpoint, remote: AppP2PAddress): AppP2PStream {
            val incoming = endpoint.acceptNext() ?: throw ProtocolException("P2P_CLOSED")
            val conn = incoming.accept().connect()
            return try {
                requireProtocol(conn.remoteId().toString() == remote.endpointId && conn.alpn().contentEquals(alpn), "WRONG_P2P_ENDPOINT")
                AppP2PStream(conn, conn.acceptBi())
            } catch (e: Throwable) { conn.close(1, byteArrayOf()); conn.close(); throw e }
        }
        /** Untrusted first contact: no application facts may be accepted before signed contact + human consent. */
        suspend fun acceptContact(endpoint: Endpoint): AppP2PStream {
            val incoming = endpoint.acceptNext() ?: throw ProtocolException("P2P_CLOSED")
            val conn = incoming.accept().connect()
            return try {
                requireProtocol(conn.alpn().contentEquals(alpn), "WRONG_P2P_ENDPOINT")
                AppP2PStream(conn, conn.acceptBi())
            } catch (e: Throwable) { conn.close(1, byteArrayOf()); conn.close(); throw e }
        }
    }
}
