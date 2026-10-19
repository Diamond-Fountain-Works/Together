package com.together.protocol

import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import okio.ByteString
import okio.ByteString.Companion.toByteString
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@Serializable data class RelaySpace(val schemaVersion: Int, val legacyRouteId: String, val spaceId: String, val archive: AuthorizationArchive, val authorizationDigest: String) {
    fun verify(local: DeviceDescriptor, prior: SpaceAuthorization): SpaceAuthorization {
        val t = SpaceAuthorization.restore(archive)
        requireProtocol(schemaVersion == 2 && t.spaceId == spaceId && spaceId == prior.spaceId && t.digest == authorizationDigest && t.active(local) && t.extends(prior), "STALE_OR_UNAUTHORIZED_SPACE")
        return t
    }
}
@Serializable private data class Challenge(val id: String, val nonce: String, val expiresAt: Long)
@Serializable data class RelayTicket(val ticket: String, val routeId: String, val expiresAt: Long)
class RelayApi(val binding: C1Binding, private val identity: DeviceIdentity, allowLocal: Boolean = false,
    val client: OkHttpClient = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).callTimeout(20, TimeUnit.SECONDS).build()) {
    // Request-only unpaired client. The initial IDs are never saved as a paired binding.
    companion object {
        fun unpaired(origin: String, identity: DeviceIdentity, allowLocal: Boolean = false) = RelayApi(
            C1Binding(origin, identity.descriptor.initialSpaceId, identity.descriptor.initialSpaceId, identity.descriptor.deviceId), identity, allowLocal)
    }
    private val base = validOrigin(binding.serviceURL, allowLocal).toString().trimEnd('/')
    fun requirePartnerService() {
        val health = Canonical.parse(response(Request.Builder().url("$base/health").build(), 16384)).jsonObject
        requireProtocol(health["partnerPairing"]?.jsonPrimitive?.intOrNull == 1, "PARTNER_SERVICE_UPGRADE_REQUIRED")
    }
    fun partnerSocket(route: String) = base.replaceFirst("https://", "wss://").replaceFirst("http://", "ws://") + "/v1/socket/${uuid(route)}"
    private fun response(request: Request, maximum: Int): ByteArray = client.newCall(request).execute().use { response ->
        val body = response.body ?: throw ProtocolException("SERVICE_UNAVAILABLE")
        requireProtocol(body.contentLength() <= maximum, "RESPONSE_BOUNDS")
        val source = body.source(); val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) { val n = source.read(buffer, 0, minOf(buffer.size, maximum + 1 - out.size())); if (n < 0) break; out.write(buffer, 0, n); requireProtocol(out.size() <= maximum, "RESPONSE_BOUNDS") }
        val bytes = out.toByteArray()
        requireProtocol(response.isSuccessful, runCatching { Canonical.parse(bytes).jsonObject["error"]?.jsonPrimitive?.content }.getOrNull()?.takeIf { Regex("[A-Z_]{1,80}").matches(it) } ?: "SERVICE_UNAVAILABLE")
        bytes
    }
    fun request(method: String, path: String, body: ByteArray = byteArrayOf(), maximum: Int = 131_072): JsonElement {
        // Native first-partner bootstrap uses the existing, scoped route API.
        // Keep all other legacy paths inaccessible to the Protocol 4 client.
        val partnerRoute = Regex("/v1/routes/[0-9A-F-]{36}(/(ticket|confirm))?").matches(path)
        requireProtocol((path.startsWith("/v2/") || partnerRoute) && !path.contains("?"), "INVALID_API_PATH")
        val challengePath = if (partnerRoute) "/v1/challenge" else "/v2/challenge"
        val challenge = Canonical.parse(response(Request.Builder().url(base + challengePath).build(), 16_384)).model<Challenge>()
        uuid(challenge.id); requireProtocol(challenge.nonce.length in 1..256, "INVALID_CHALLENGE")
        val text = listOf("Together-Auth-1", challenge.nonce, method, path, sha256(body), identity.descriptor.deviceId).joinToString("\n")
        val r = Request.Builder().url(base + path).header("Content-Type", "application/json")
            .header("X-Together-Key", identity.descriptor.publicKey).header("X-Together-Device", identity.descriptor.deviceId)
            .header("X-Together-Challenge", challenge.id).header("X-Together-Signature", identity.sign(text.toByteArray()))
            .method(method, if (method == "GET") null else body.toRequestBody("application/json".toMediaType())).build()
        return Canonical.parse(response(r, maximum), maximum)
    }
    fun space(): RelaySpace = request("GET", "/v2/spaces/${binding.spaceId}").model()
    fun ticket(): RelayTicket = request("POST", "/v2/spaces/${binding.spaceId}/ticket", "{}".toByteArray(), 16_384).model<RelayTicket>().also { requireProtocol(it.routeId == binding.spaceId && it.ticket.length <= 4096, "INVALID_TICKET") }
    fun authorize(event: AuthorizationEvent): RelaySpace = request("POST", "/v2/spaces/${binding.spaceId}/devices", Canonical.bytes(buildJsonObject { put("event", event.json()) })).model()
    val socketURL get() = base.replaceFirst("https://", "wss://").replaceFirst("http://", "ws://") + "/v2/socket/${binding.spaceId}"
}
interface SyncTransport {
    val state: StateFlow<String>
    suspend fun connect(url: String, ticket: String)
    suspend fun receive(): ByteArray
    suspend fun send(bytes: ByteArray)
    fun disconnect()
}
class OkHttpSyncTransport(private val client: OkHttpClient = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).pingInterval(20, TimeUnit.SECONDS).build()) : SyncTransport {
    private val _state = MutableStateFlow("offline"); override val state = _state.asStateFlow()
    private var socket: WebSocket? = null
    private var inbound = Channel<ByteArray>(16)
    override suspend fun connect(url: String, ticket: String) {
        disconnect(); inbound = Channel(16); val queue = inbound
        _state.value = "connecting"
        suspendCancellableCoroutine<Unit> { c ->
            val ws = client.newWebSocket(Request.Builder().url(url).header("Authorization", "Bearer $ticket").build(), object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) { if (c.isActive) { _state.value = "connected"; c.resume(Unit) } else webSocket.cancel() }
                private fun offer(webSocket: WebSocket, bytes: ByteArray) {
                    if (bytes.size > 524_288 || queue.trySend(bytes).isFailure) { queue.close(ProtocolException("FRAME_OR_QUEUE_BOUNDS")); webSocket.cancel() }
                }
                override fun onMessage(webSocket: WebSocket, bytes: ByteString) { offer(webSocket, bytes.toByteArray()) }
                override fun onMessage(webSocket: WebSocket, text: String) { offer(webSocket, text.toByteArray()) }
                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { if (inbound !== queue) return; _state.value = "offline"; queue.close(t); if (c.isActive) c.resumeWithException(t) }
                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) { webSocket.close(code, null) }
                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { if (inbound !== queue) return; _state.value = "offline"; queue.close() }
            })
            socket = ws; c.invokeOnCancellation { ws.cancel() }
        }
    }
    override suspend fun receive(): ByteArray = inbound.receive()
    override suspend fun send(bytes: ByteArray) {
        requireProtocol(bytes.size <= 524_288 && (socket?.queueSize() ?: Long.MAX_VALUE) < 8_388_608, "SEND_QUEUE_BOUNDS")
        requireProtocol(socket?.send(bytes.toByteString()) == true, "SOCKET_NOT_CONNECTED")
        delay(6) // Under the Relay's 200 frames/second bound; this is not a delivery ACK.
    }
    override fun disconnect() { socket?.cancel(); socket = null; inbound.close(); _state.value = "offline" }
}
@Serializable private data class Directed(val kind: String = "relay4", val senderDeviceId: String, val recipientDeviceId: String, val packet: RelayPacket)
@Serializable private data class Presence(val kind: String, val spaceId: String, val devices: List<String>, val authorizationDigest: String)
@Serializable private data class Content(val kind: String, val frame: ReplicationFrame? = null, val payload: JsonObject? = null)

/** Foreground-owned coroutine. New challenge/ticket/ephemeral on every connection;
 * cancelling the foreground scope closes sockets without discarding local facts. */
class C1Client(private val replica: Replica, private val binding: C1Binding, private val api: RelayApi,
    private val transport: SyncTransport = OkHttpSyncTransport(), private val media: MediaChannel? = null,
    private val onPersisted: () -> Unit = {}) {
    private val _state = MutableStateFlow("offline"); val state = _state.asStateFlow()
    private val _error = MutableStateFlow<String?>(null); val error = _error.asStateFlow()
    private data class Peer(val device: DeviceDescriptor, val ephemeral: ByteArray, val hello: SignedHello,
        var secure: SecureChannel? = null, var approved: Boolean = false, var sync: AntiEntropy? = null,
        val seenHellos: MutableSet<String> = mutableSetOf())
    private val peers = mutableMapOf<String, Peer>()
    private val runLock = Mutex()
    private val changes = Channel<Unit>(Channel.CONFLATED)
    private sealed interface Event { data class Bytes(val value: ByteArray) : Event; data object Changed : Event }
    private var attempt = 0
    fun changed() { changes.trySend(Unit) }
    suspend fun run() = runLock.withLock { withContext(Dispatchers.IO.limitedParallelism(1)) { coroutineScope {
        try {
            while (isActive) {
                try {
                    _state.value = "connecting"; val space = api.space(); requireProtocol(space.legacyRouteId == binding.legacyRouteId, "ROUTE_MISMATCH")
                    currentCoroutineContext().ensureActive(); val trust = space.verify(replica.identity.descriptor, replica.trust); replica.updateAuthorization(trust.archive)
                    val ticket = api.ticket(); currentCoroutineContext().ensureActive()
                    transport.connect(api.socketURL, ticket.ticket); _state.value = "waiting"; _error.value = null
                    coroutineScope {
                        val events = Channel<Event>(16)
                        val receiver = launch { try { while (isActive) events.send(Event.Bytes(transport.receive())) } catch (e: Exception) { events.close(e) } }
                        val sender = launch { for (ignored in changes) events.send(Event.Changed) }
                        try {
                            for (event in events) when (event) {
                                is Event.Bytes -> receive(event.value)
                                Event.Changed -> { if (peers.values.any { it.approved }) _state.value = "syncing"; for (p in peers.values.filter { it.approved }) { p.sync!!.localChanged().forEach { sendContent(p, it) }; media?.synchronize(p.device)?.forEach { sendMedia(p, it) } } }
                            }
                        } finally { receiver.cancelAndJoin(); sender.cancelAndJoin(); events.close() }
                    }
                    attempt = 0
                } catch (e: CancellationException) { throw e }
                catch (e: Exception) { currentCoroutineContext().ensureActive(); _state.value = "offline"; _error.value = (e as? ProtocolException)?.code ?: "CONNECTION_FAILED" }
                finally { peers.values.forEach { media?.disconnected(it.device.deviceId); it.sync?.close(); it.ephemeral.fill(0) }; peers.clear(); transport.disconnect() }
                delay(minOf(60_000L, 1000L shl minOf(attempt++, 6)))
            }
        } finally { _state.value = "offline"; transport.disconnect() }
    }
    }
    }
    private suspend fun send(p: Peer, packet: RelayPacket) = transport.send(Canonical.encode(Directed(senderDeviceId = replica.identity.descriptor.deviceId, recipientDeviceId = p.device.deviceId, packet = packet)))
    private suspend fun sendContent(p: Peer, f: ReplicationFrame) { requireProtocol(p.approved, "UNAUTHENTICATED_CHANNEL"); send(p, p.secure!!.seal(Canonical.encode(Content("replication", frame = f)))) }
    private suspend fun sendMedia(p: Peer, payload: JsonObject) {
        requireProtocol(p.approved, "UNAUTHENTICATED_CHANNEL"); send(p, p.secure!!.seal(Canonical.encode(Content("media", payload = payload))))
    }
    private suspend fun receive(bytes: ByteArray) {
        val objectValue = Canonical.parse(bytes).jsonObject
        when (objectValue["kind"]?.jsonPrimitive?.content) {
            "waiting4" -> { _state.value = "waiting"; return }
            "status4" -> {
                val s = objectValue.model<Presence>(); val trust = replica.trust
                requireProtocol(s.spaceId == trust.spaceId && s.devices.size <= 32 && s.devices.distinct().size == s.devices.size && s.authorizationDigest == trust.digest, "AUTHORIZATION_CHANGED")
                val online = s.devices.toSet() - replica.identity.descriptor.deviceId
                (peers.keys - online).forEach { peers.remove(it)?.let { p -> media?.disconnected(p.device.deviceId); p.sync?.close(); p.ephemeral.fill(0) } }
                for (id in online.sorted()) if (id !in peers) {
                    val d = trust.devices[id]?.takeIf { it.active }?.descriptor ?: throw ProtocolException("UNAUTHORIZED_DEVICE")
                    val ephemeral = Crypto.seed(); val p = Peer(d, ephemeral, SecureChannel.hello(replica.identity, ephemeral, trust)); peers[id] = p
                    send(p, RelayPacket("hello", hello = p.hello))
                }
                if (peers.isEmpty()) _state.value = "waiting"
                return
            }
        }
        val d = objectValue.model<Directed>()
        requireProtocol(d.kind == "relay4" && d.recipientDeviceId == replica.identity.descriptor.deviceId, "WRONG_RECIPIENT")
        val p = peers[d.senderDeviceId] ?: throw ProtocolException("UNKNOWN_SENDER")
        requireProtocol(replica.trust.active(p.device), "DEVICE_REVOKED")
        when (d.packet.kind) {
            "hello" -> {
                val remote = d.packet.hello ?: throw ProtocolException("MISSING_HELLO")
                requireProtocol(remote.body.descriptor.deviceId == p.device.deviceId, "SENDER_MISMATCH")
                if (p.secure?.remote == remote) return
                val digest = sha256(Canonical.encode(remote)); requireProtocol(p.seenHellos.size < 64 && p.seenHellos.add(digest), "REPLAYED_HELLO")
                if (p.secure != null) { p.approved = false; p.sync?.close(); p.sync = null; send(p, RelayPacket("hello", hello = p.hello)) }
                p.secure = SecureChannel(replica.identity, p.ephemeral, p.hello, remote, replica.trust)
                send(p, RelayPacket("consent", consent = p.secure!!.consent()))
            }
            "consent" -> {
                val secure = p.secure ?: throw ProtocolException("MISSING_HANDSHAKE")
                d.packet.consent?.verify(p.device, secure.transcript) ?: throw ProtocolException("MISSING_CONSENT")
                if (p.approved) return
                p.approved = true; p.sync = AntiEntropy(replica, p.device); _state.value = "syncing"
                p.sync!!.start().forEach { sendContent(p, it) }; media?.synchronize(p.device)?.forEach { sendMedia(p, it) }
            }
            "encrypted" -> {
                requireProtocol(p.approved, "UNAUTHENTICATED_CHANNEL")
                val content = Canonical.parse(p.secure!!.open(d.packet)).model<Content>()
                when (content.kind) {
                    "replication" -> {
                        p.sync!!.receive(content.frame ?: throw ProtocolException("MISSING_FRAME")).forEach { sendContent(p, it) }
                        onPersisted(); media?.synchronize(p.device)?.forEach { sendMedia(p, it) }
                        if (p.sync!!.converged) { attempt = 0; _state.value = "connected"; _error.value = null }
                    }
                    "media" -> {
                        val payload = content.payload ?: throw ProtocolException("MISSING_MEDIA_PAYLOAD")
                        media?.receive(p.device, payload)?.forEach { sendMedia(p, it) }; onPersisted()
                    }
                    else -> throw ProtocolException("UNKNOWN_CONTENT")
                }
            }
            else -> throw ProtocolException("UNKNOWN_RELAY_PACKET")
        }
    }
}
