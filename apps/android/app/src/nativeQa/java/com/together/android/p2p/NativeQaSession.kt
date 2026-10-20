package com.together.android.p2p

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.AtomicFile
import com.together.android.BuildConfig
import com.together.android.data.*
import com.together.protocol.*
import computer.iroh.*
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*

/** Public factory exists only in nativeQa. C1 binaries contain neither this class nor Iroh. */
class NativeQaSessionFactory : NativeAppSessionFactory {
    override fun create(context: Context, scope: CoroutineScope, repository: NativeAppRepository): NativeAppSession =
        NativeQaSession(context, scope, repository)
}

/** Adapter around existing bootstrap, Replica, AntiEntropy and signed durable ACKs; no second ledger. */
private class NativeQaSession(
    private val context: Context,
    parent: CoroutineScope,
    private val host: NativeAppRepository,
) : NativeAppSession {
    init {
        requireProtocol(BuildConfig.NATIVE_QA && BuildConfig.DEBUG &&
            context.packageName == "com.together.android.qa.native" && BuildConfig.RELAY_URL.isEmpty(),
            "ISOLATED_NATIVE_QA_REQUIRED")
    }
    private val scope = CoroutineScope(parent.coroutineContext + SupervisorJob(parent.coroutineContext[Job]))
    private val _state = MutableStateFlow(NativeAppStatus())
    override val state = _state.asStateFlow()
    private val gate = Mutex()
    private val changed = Channel<Unit>(Channel.CONFLATED)
    private var endpoint: Endpoint? = null
    private var link: AppP2PStream? = null
    private var bootstrap: NativePartnerBootstrapChannel? = null
    private var job: Job? = null
    private var foreground = false
    private var offline = false
    private var closing = false
    private var own: NativePartnerContact? = null
    private var remote: NativePartnerContact? = null
    private var joined = false
    private val seedFile = AtomicFile(File(context.noBackupFilesDir, "native-qa-transport.key"))

    override fun foreground(value: Boolean) {
        foreground = value
        scope.launch { gate.withLock {
            try {
                if (!value) stopConnection()
                else if (!offline && !closing) resume()
            } catch (e: Exception) { fail(e) }
        } }
    }

    private fun fail(error: Exception) {
        if (error is CancellationException) return
        val code = (error as? ProtocolException)?.code ?: "CONNECTION_FAILED"
        android.util.Log.e("TogetherNativeQa", "Native App stage=${_state.value.stage} failure=${error.javaClass.simpleName} code=$code")
        _state.value = _state.value.copy(stage = "error", error = code, path = null)
    }

    private suspend fun resume() {
        if (job?.isActive == true) return
        var saved = host.access { it.store.local("native-binding") }
        if (saved == null) {
            // Same recovery boundary as existing C1 pendingGenesis: both signed roots and
            // the exact durably imported history authorize local activation, never an ACK.
            val prepared = host.access { c ->
                c.store.local("native-prepared-genesis")?.let { Canonical.parse(it).model<SignedGenesis>() }
            }
            if (prepared != null) {
                val contact = host.access { c ->
                    val raw = c.store.local("native-pending-contact") ?: throw ProtocolException("MISSING_NATIVE_BINDING")
                    Canonical.parse(raw).model<NativePartnerContact>()
                }
                contact.verifySignature(); prepared.verify()
                host.access { c ->
                    val pin = c.store.local("partner-peer")?.let { Canonical.parse(it).model<DeviceDescriptor>() }
                    requireProtocol(pin == contact.body.descriptor && prepared.body.roots.toSet() ==
                        setOf(c.identity.descriptor, contact.body.descriptor) && prepared.body.legacyCheckpoint ==
                        checkpoint(c.store.records().map { it.record.entry }), "INVENTORY_CHANGED")
                }
                val binding = Canonical.bytes(buildJsonObject { put("peerContact", contact.json()) })
                host.activate(AuthorizationArchive(prepared, emptyList()), contact.body.descriptor, binding)
                saved = binding
            }
        }
        if (saved != null) {
            val value = Canonical.parse(saved).jsonObject
            val contact = value.getValue("peerContact").model<NativePartnerContact>()
            contact.verifySignature()
            host.access { c ->
                val trust = c.replica?.trust ?: throw ProtocolException("MISSING_AUTHORIZATION")
                requireProtocol(trust.active(contact.body.descriptor) && contact.body.descriptor != c.identity.descriptor,
                    "INVALID_P2P_BINDING")
            }
            remote = contact
            own = contactFor(contact.body.invitationId)
            launchConnection(paired = true)
        } else if (own != null) launchConnection(paired = false)
    }

    private fun checkNetwork() {
        val cm = context.getSystemService(ConnectivityManager::class.java)
        val capabilities = cm.getNetworkCapabilities(cm.activeNetwork)
            ?: throw ProtocolException("CONNECTION_FAILED")
        requireProtocol(capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
            !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN), "VPN_OR_NETWORK_UNAVAILABLE")
    }

    private suspend fun transportSeed(): ByteArray {
        if (seedFile.baseFile.exists()) return seedFile.readFully().also {
            requireProtocol(it.size == 32, "IDENTITY_FILE_UNAVAILABLE")
        }
        val existing = host.access { it.store.local("native-binding") != null }
        requireProtocol(!existing, "IDENTITY_FILE_UNAVAILABLE")
        val key = SecretKey.generate()
        val bytes = try { key.toBytes() } finally { key.close() }
        val out = seedFile.startWrite()
        try { out.write(bytes); seedFile.finishWrite(out) }
        catch (e: Exception) { seedFile.failWrite(out); bytes.fill(0); throw e }
        seedFile.baseFile.setReadable(false, false); seedFile.baseFile.setWritable(false, false)
        seedFile.baseFile.setReadable(true, true); seedFile.baseFile.setWritable(true, true)
        return bytes
    }

    private suspend fun ensureEndpoint(): Endpoint {
        endpoint?.let { return it }
        checkNetwork()
        IrohAndroid.installAndroidContext(context)
        val seed = transportSeed()
        val created = try {
            Endpoint.bind(EndpointOptions(preset = presetN0(), secretKey = seed,
                alpns = listOf(AppP2PStream.alpn), relayMode = RelayMode.defaultMode()))
        } finally { seed.fill(0) }
        endpoint = created
        // addr() is public, bounded and cancellable; do not depend on an uncancellable online() call.
        withTimeoutOrNull(15_000) {
            while (AppP2PAddress.from(created).relayURL == null) delay(100)
        }
        return created
    }

    private suspend fun contactFor(invitationId: String): NativePartnerContact {
        val address = AppP2PAddress.from(ensureEndpoint())
        return host.access { c -> NativePartnerContact.issue(c.identity, invitationId, address.endpointId,
            address.relayURL, address.directAddresses, System.currentTimeMillis()) }
    }

    override suspend fun createInvitation() = gate.withLock {
        requireProtocol(!offline && foreground && !closing, "CONNECTION_FAILED")
        requireProtocol(host.access { it.replica == null }, "ALREADY_PAIRED")
        requireProtocol(host.access { it.store.local("native-prepared-genesis") == null }, "PAIRING_FINISHING")
        requireProtocol(job?.isActive != true, "PAIRING_ALREADY_STARTED")
        stopConnection()
        remote = null; joined = false
        _state.value = NativeAppStatus(stage = "creating")
        try {
            own = contactFor(uid())
            _state.value = NativeAppStatus(stage = "waiting", invitation = Canonical.encode(own!!).toString(Charsets.UTF_8))
            launchConnection(paired = false)
        } catch (e: Exception) { fail(e); throw e }
    }

    override suspend fun joinInvitation(contact: String) = gate.withLock {
        requireProtocol(!offline && foreground && !closing, "CONNECTION_FAILED")
        requireProtocol(host.access { it.replica == null }, "ALREADY_PAIRED")
        requireProtocol(host.access { it.store.local("native-prepared-genesis") == null }, "PAIRING_FINISHING")
        requireProtocol(job?.isActive != true, "PAIRING_ALREADY_STARTED")
        requireProtocol(contact.toByteArray().size in 1..32_768, "INVALID_INVITATION")
        val parsed = Canonical.parse(contact.toByteArray(), 32_768).model<NativePartnerContact>()
        parsed.verify()
        host.access { c -> requireProtocol(parsed.body.descriptor.userId != c.identity.descriptor.userId &&
            parsed.body.descriptor.deviceId != c.identity.descriptor.deviceId, "IDENTITY_MISMATCH") }
        stopConnection()
        _state.value = NativeAppStatus(stage = "connecting")
        try {
            remote = parsed; joined = true
            own = contactFor(parsed.body.invitationId)
            _state.value = NativeAppStatus(stage = "connecting")
            launchConnection(paired = false)
        } catch (e: Exception) { fail(e); throw e }
    }

    override suspend fun confirm(verified: Boolean) {
        requireProtocol(verified, "IDENTITY_CONFIRMATION_REQUIRED")
        requireProtocol(_state.value.stage == "verifying", "PAIRING_NOT_READY")
        val current = bootstrap ?: throw ProtocolException("PAIRING_NOT_READY")
        _state.value = _state.value.copy(stage = "confirming", error = null)
        try { current.confirm(verified) }
        catch (e: Exception) { _state.value = _state.value.copy(stage = "verifying"); throw e }
    }

    override suspend fun cancelInvitation() = gate.withLock {
        requireProtocol(host.access { it.replica == null && it.store.local("partner-pending") == null },
            "PAIRING_FINISHING")
        stopConnection()
        own = null; remote = null; joined = false
        _state.value = NativeAppStatus(offline = offline)
    }

    private fun address(contact: NativePartnerContact) = AppP2PAddress(contact.body.endpointId,
        contact.body.relayURL, contact.body.directAddresses)

    private fun launchConnection(paired: Boolean) {
        if (job?.isActive == true || offline || !foreground || closing) return
        job = scope.launch(Dispatchers.IO) {
            var attempt = 0
            while (isActive && foreground && !offline && !closing) {
                try {
                    val ep = ensureEndpoint()
                    val identity = host.access { it.identity }
                    val isPaired = host.access { it.replica != null }
                    val initiate = if (isPaired) identity.descriptor.deviceId < remote!!.body.descriptor.deviceId else joined
                    if (isPaired) _state.value = _state.value.copy(stage = "connecting", error = null)
                    val connected = if (initiate) withTimeout(45_000) { AppP2PStream.connect(ep, address(remote!!)) }
                        else AppP2PStream.acceptContact(ep)
                    link = connected
                    try {
                        val currentOwn = own ?: throw ProtocolException("INVALID_INVITATION")
                        val peer = if (isPaired) remote!!.also { pinned ->
                            pinned.verifySignature(connectedEndpointId = connected.connection.remoteId().toString())
                        } else {
                            connected.send(Canonical.encode(currentOwn))
                            withTimeout(20_000) { Canonical.parse(connected.receive(), 32_768).model<NativePartnerContact>() }.also {
                                it.verify(System.currentTimeMillis(), currentOwn.body.invitationId, connected.connection.remoteId().toString())
                                if (joined) requireProtocol(it == remote, "IDENTITY_MISMATCH")
                            }
                        }
                        requireProtocol(peer.body.descriptor.userId != identity.descriptor.userId, "IDENTITY_MISMATCH")
                        remote?.let { requireProtocol(it.body.descriptor == peer.body.descriptor &&
                            it.body.endpointId == peer.body.endpointId, "IDENTITY_MISMATCH") }
                        remote = peer
                        _state.value = _state.value.copy(peer = peer.body.descriptor, error = null)
                        val inbox = Incoming()
                        val reader = launch { try { while (isActive) inbox.queue.send(connected.receive()) }
                            catch (e: Throwable) { inbox.queue.close(e) } }
                        try {
                            if (!isPaired) bootstrap(connected, currentOwn, peer, inbox)
                            replicate(connected, peer, inbox)
                        } finally { reader.cancelAndJoin(); inbox.queue.cancel() }
                        attempt = 0
                    } finally { bootstrap?.stop(); bootstrap = null; connected.close(); link = null }
                } catch (e: TimeoutCancellationException) {
                    // A bounded connect/contact timeout belongs to this attempt; it must not
                    // masquerade as explicit foreground/offline lifecycle cancellation.
                    if (!currentCoroutineContext().isActive || !foreground || offline || closing) throw e
                    fail(ProtocolException("P2P_CONNECT_TIMEOUT"))
                } catch (e: CancellationException) { throw e }
                catch (e: Exception) { fail(e) }
                if (host.access { it.replica != null }) {
                    delay(minOf(30_000L, 1000L shl minOf(attempt++, 5)))
                } else break
            }
        }
    }

    private class Incoming {
        val queue = Channel<ByteArray>(8)
        private var pending: ByteArray? = null
        suspend fun receive(): ByteArray = pending?.also { pending = null } ?: queue.receive()
        fun unread(bytes: ByteArray) { check(pending == null); pending = bytes }
    }

    private suspend fun bootstrap(stream: AppP2PStream, own: NativePartnerContact, peer: NativePartnerContact, inbox: Incoming) = coroutineScope {
        val completed = CompletableDeferred<Unit>()
        // Routing metadata remains untrusted until pin + both consent signatures + genesis.
        // Save before prepare so a crash cannot strand a valid co-signed genesis without its route.
        host.access { it.store.local("native-pending-contact", Canonical.encode(peer)) }
        val history = object : NativePartnerHistory {
            override suspend fun pin(peer: DeviceDescriptor) = host.pin(peer)
            override suspend fun ownHistory() = host.access { c -> c.store.records().map { it.record.operation }
                .filter { it.operation.deviceId == c.identity.descriptor.deviceId } }
            override suspend fun importBatch(operations: List<SignedOperation>) {
                host.access { c ->
                    requireProtocol(c.replica == null && operations.size <= 32, "BATCH_BOUNDS")
                    c.store.transaction { operations.forEach { operation ->
                        operation.verify(peer.body.descriptor)
                        val record = ReplicationRecord("legacy", legacy = operation)
                        val previous = c.store.get(operation.operation.operationId)
                        requireProtocol(previous == null || previous.record == record, "CONTENT_COLLISION")
                        c.store.put(StoredRecord(record, true))
                    } }
                }
                host.refreshed()
            }
            override suspend fun checkpoint() = host.access { c -> checkpoint(c.store.records().map { it.record.entry }) }
            override suspend fun prepare(genesis: SignedGenesis) {
                host.access { c -> genesis.verify()
                    requireProtocol(genesis.body.legacyCheckpoint == checkpoint(c.store.records().map { it.record.entry }), "INVENTORY_CHANGED")
                    c.store.local("native-prepared-genesis", Canonical.encode(genesis))
                }
            }
        }
        val identity = host.access { it.identity }
        val name = identity.descriptor.displayName
        val channel = NativePartnerBootstrapChannel(identity, name, own.body.invitationId, peer.body.descriptor,
            this, history, { bytes -> stream.send(bytes) }, { genesis ->
                val binding = buildJsonObject { put("peerContact", peer.json()) }
                host.activate(AuthorizationArchive(genesis, emptyList()), peer.body.descriptor, Canonical.bytes(binding))
                completed.complete(Unit)
            }, { code -> _state.value = _state.value.copy(stage = "verifying", verificationCode = code) },
            { e -> completed.completeExceptionally(e) })
        bootstrap = channel
        try {
            _state.value = _state.value.copy(stage = "authenticating")
            channel.start()
            while (!completed.isCompleted) {
                val packet = select<ByteArray?> {
                    completed.onAwait { null }
                    inbox.queue.onReceive { it }
                }
                if (packet == null) break
                if (completed.isCompleted) { inbox.unread(packet); break }
                val objectValue = Canonical.parse(packet).jsonObject
                if (objectValue["body"]?.jsonObject?.get("authorizationDigest") != null) {
                    // Peer can finish its durable ready callback first. Hold, never authenticate,
                    // the one next-phase binding until our own co-signed activation is complete.
                    withTimeout(20_000) { completed.await() }
                    inbox.unread(packet); break
                }
                channel.receive(packet)
            }
            completed.await()
        } finally { channel.stop(); bootstrap = null }
    }

    private suspend fun replicate(stream: AppP2PStream, peer: NativePartnerContact, inbox: Incoming) = coroutineScope {
        val localBinding = host.access { c -> AppP2PBinding.issue(c.identity,
            AppP2PAddress.from(endpoint!!).endpointId, c.replica!!.trust) }
        stream.send(Canonical.bytes(localBinding.value))
        val remoteBinding = AppP2PBinding.parse(Canonical.parse(inbox.receive()))
        val cipher = host.access { c ->
            val trust = c.replica?.trust ?: throw ProtocolException("MISSING_AUTHORIZATION")
            requireProtocol(remoteBinding.device == peer.body.descriptor, "IDENTITY_MISMATCH")
            AppP2PCipher(c.identity, remoteBinding, stream.connection.remoteId().toString(), trust)
        }
        stream.send(cipher.hello)
        while (!cipher.authenticated) cipher.handshake(inbox.receive())?.let { stream.send(it) }
        val session = host.access { c -> AntiEntropy(c.replica!!, peer.body.descriptor) }
        suspend fun send(frames: List<ReplicationFrame>) {
            for (frame in frames) stream.send(cipher.seal(Canonical.encode(AuthenticatedSyncContent.replication(frame))))
        }
        suspend fun sendMedia(payloads: List<JsonObject>) {
            for (payload in payloads) stream.send(cipher.seal(Canonical.encode(AuthenticatedSyncContent.media(payload))))
        }
        try {
            _state.value = _state.value.copy(stage = "syncing", verificationCode = null, invitation = null, error = null)
            send(host.access { session.start() })
            sendMedia(host.access { it.media?.synchronize(peer.body.descriptor) ?: emptyList() })
            while (isActive) {
                val packet = select<ByteArray?> {
                    inbox.queue.onReceive { it }
                    changed.onReceive { null }
                }
                if (packet == null) {
                    send(host.access { session.localChanged() })
                    sendMedia(host.access { it.media?.synchronize(peer.body.descriptor) ?: emptyList() })
                } else {
                    val content = AuthenticatedSyncContent.decode(cipher.open(packet))
                    when (content.kind) {
                        "replication" -> {
                            send(host.access { session.receive(content.frame!!) })
                            sendMedia(host.access { it.media?.synchronize(peer.body.descriptor) ?: emptyList() })
                        }
                        "media" -> sendMedia(host.access { c ->
                            (c.media ?: throw ProtocolException("MEDIA_UNAVAILABLE")).receive(peer.body.descriptor, content.payload!!)
                        })
                        else -> throw ProtocolException("UNKNOWN_CONTENT")
                    }
                }
                host.refreshed()
                val path = stream.connection.paths().filter { it.isSelected }.let { selected ->
                    when {
                        selected.isNotEmpty() && selected.all { it.isIp && !it.isRelay } -> "direct"
                        selected.isNotEmpty() && selected.all { it.isRelay && !it.isIp } -> "relay"
                        else -> null
                    }
                }
                val durable = host.access { c -> c.store.records().all { c.replica!!.partnerPersisted(it.record.entry) } }
                _state.value = _state.value.copy(stage = if (session.converged && durable) "connected" else "syncing", path = path)
            }
        } finally {
            withContext(NonCancellable) {
                host.access { c -> session.close(); c.media?.disconnected(peer.body.descriptor.deviceId) }
            }
        }
    }

    override fun changed() {
        if (_state.value.stage == "connected") _state.value = _state.value.copy(stage = "syncing")
        changed.trySend(Unit)
    }

    private suspend fun stopConnection() {
        link?.close(); link = null
        job?.cancelAndJoin(); job = null
        bootstrap?.stop(); bootstrap = null
        _state.value = _state.value.copy(stage = "offline", path = null)
    }

    override fun reconnect() {
        scope.launch { gate.withLock {
            stopConnection()
            if (!offline && foreground && !closing) try { resume() } catch (e: Exception) { fail(e) }
        } }
    }

    override suspend fun setOffline(value: Boolean) = gate.withLock {
        offline = value
        stopConnection()
        _state.value = _state.value.copy(offline = value)
        if (!offline && foreground && !closing) resume()
    }

    override suspend fun close() = gate.withLock {
        closing = true
        stopConnection()
        endpoint?.let { it.shutdown(); it.close() }; endpoint = null
        scope.cancel(); changed.close()
        Unit
    }
}
