package com.together.android.data

import android.content.Context
import android.util.AtomicFile
import com.together.domain.*
import com.together.protocol.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import java.io.File
import java.time.Instant
import java.time.ZoneId

/** App-private Room/Keystore only. No production Mac path, bundled real store or Relay origin. */
class TogetherRepository(private val context: Context, private val scope: CoroutineScope,
    private val namespace: String? = null, private val clock: DateProvider = systemDateProvider) {
    init { requireProtocol(namespace == null || (com.together.android.BuildConfig.DEBUG && Regex("[A-Z0-9-]{1,45}").matches(namespace)), "INVALID_WORKSPACE") }
    private val workspaceRoot = if (namespace == null) context.noBackupFilesDir else File(context.noBackupFilesDir, "qa-$namespace").apply { mkdirs() }
    private fun databaseName(value: String) = if (namespace == null) value else "qa-$namespace-$value"
    data class State(val loaded: Boolean = false, val historyReady: Boolean = true, val snapshot: Snapshot = Snapshot(), val descriptor: DeviceDescriptor? = null,
        val authorization: SpaceAuthorization? = null, val connection: String = "offline", val error: String? = null,
        val reviewed: Set<String> = emptySet(), val offer: EnrollmentOffer? = null, val request: EnrollmentRequest? = null) {
        val canWrite: Boolean get() = descriptor != null && historyReady && (authorization == null || authorization.active(descriptor))
    }
    private val _state = MutableStateFlow(State()); val state = _state.asStateFlow()
    private val identities = AndroidIdentityStore(context, namespace)
    private val lock = Mutex(); private val refresh = Channel<Unit>(Channel.CONFLATED)
    private lateinit var db: TogetherDatabase; private lateinit var store: RoomReplicaStore; private lateinit var identity: DeviceIdentity
    private var replica: Replica? = null; private var client: C1Client? = null; private var connectionJob: Job? = null
    private var refreshJob: Job? = null
    private var foreground = false; private var binding: C1Binding? = null
    private val marker = AtomicFile(File(workspaceRoot, "active-replica.json"))
    init {
        refreshJob = scope.launch(Dispatchers.IO) {
            try { lock.withLock { open(); reload() } } catch (e: Exception) { failed(e) }
            for (ignored in refresh) { delay(100); try { lock.withLock { reload() } } catch (e: Exception) { failed(e) } }
        }
    }
    private fun publicJson(o: JsonObject, key: String) = o[key]?.jsonPrimitive?.content ?: throw ProtocolException("INVALID_WORKSPACE")
    private fun open() {
        val pointer = if (marker.baseFile.exists()) Canonical.parse(marker.readFully(), 4096).jsonObject else null
        val slot = pointer?.let { uuid(publicJson(it, "offerId")) } ?: "LOCAL"
        val databaseName = databaseName(if (slot == "LOCAL") "together-local.db" else "replica-$slot.db")
        val needsExisting = pointer != null || context.getDatabasePath(databaseName).exists()
        identity = if (identities.exists(slot)) identities.load(slot) else {
            requireProtocol(!needsExisting, "IDENTITY_FILE_UNAVAILABLE")
            identities.create(slot, uid(), uid(), android.os.Build.MODEL.take(80), ZoneId.systemDefault().id)
        }
        db = TogetherDatabase.open(context, databaseName); store = RoomReplicaStore(db); db.dao().clearSnapshots()
        val archive = store.local("authorization")?.let { Canonical.parse(it).model<AuthorizationArchive>() }
        if (archive != null) {
            val trust = SpaceAuthorization.restore(archive)
            replica = Replica(store, identity, trust).also { it.restore() }
            binding = store.local("binding")?.let { Canonical.parse(it).model<C1Binding>() } ?: throw ProtocolException("MISSING_RELAY_BINDING")
            requireProtocol(binding!!.spaceId == trust.spaceId && binding!!.localDeviceId == identity.descriptor.deviceId, "BINDING_IDENTITY_MISMATCH")
            configureClient()
        } else {
            requireProtocol(pointer == null, "MISSING_AUTHORIZATION")
            // Unpaired private local workspace; not exposed as certified Protocol 4 history.
            store.records().forEach { it.record.operation.verify(identity.descriptor) }
        }
        val pending = store.local("pending-enrollment")?.let { Canonical.parse(it).jsonObject }
        _state.value = _state.value.copy(descriptor = identity.descriptor, offer = pending?.get("offer")?.model(), request = pending?.get("request")?.model())
    }
    private fun configureClient() {
        val r = replica ?: return
        val b = binding ?: return
        val api = RelayApi(b, identity, allowLocal = com.together.android.BuildConfig.DEBUG)
        client = C1Client(r, b, api) { refresh.trySend(Unit) }
        if (foreground) startConnection()
    }
    private fun domainContext(): DomainContext = replica?.trust?.let(DomainContext::from)
        ?: DomainContext(identity.descriptor.initialSpaceId, setOf(identity.descriptor.userId), setOf(identity.descriptor.initialSpaceId), identity.descriptor.initialTimeZoneIdentifier ?: "Etc/UTC", identity.descriptor.userId)
    private fun snapshot(): Snapshot = if (replica != null && !replica!!.legacyComplete()) Snapshot() else Projector.replay(store.records().map { it.record.operation }, domainContext())
    private fun reconcile() {
        val r = replica
        if (r != null && !r.legacyComplete()) return
        fun apply() {
            while (true) {
                val old = store.records().map { it.record.operation }; val current = Projector.replay(old, domainContext())
                val mutations = (RecurrencePlanner.pending(current, domainContext(), identity.descriptor.userId) + BillPlanner.pending(current, domainContext(), identity.descriptor.userId, clock)).take(32)
                if (mutations.isEmpty()) break
                val clock = r?.nextClock() ?: ((store.local("local-lamport")?.toString(Charsets.UTF_8)?.toLong() ?: 0) + 1)
                val now = this@TogetherRepository.clock.now().toEpochMilli()
                val operations = mutations.mapIndexed { index, m -> SyncOperation(uid(), identity.descriptor.deviceId, identity.descriptor.userId, m.entityId, m.entityType, m.operationType, clock + index, m.payload, now) }
                val signed = operations.map(identity::sign); val candidate = Projector.replay(old + signed, domainContext())
                val ids = operations.map { it.operationId }.toSet()
                requireProtocol(candidate.conflicts.none { it.operationId in ids }, "INVALID_DOMAIN_OPERATION")
                if (r != null) r.append(operations) else { signed.forEach { store.put(StoredRecord(ReplicationRecord("legacy", legacy = it), true)) }; store.local("local-lamport", operations.last().lamportClock.toString().toByteArray()) }
            }
        }
        if (r != null) r.atomicCommand { apply() } else store.transaction { apply() }
    }
    private fun reload() {
        reconcile()
        val reviewed = store.local("reviewed")?.let { Canonical.parse(it).model<Set<String>>() } ?: emptySet()
        _state.value = _state.value.copy(loaded = true, historyReady = replica?.legacyComplete() ?: true, descriptor = identity.descriptor, authorization = replica?.trust, snapshot = snapshot(), reviewed = reviewed)
    }
    private fun failed(e: Exception) { _state.value = _state.value.copy(loaded = true, historyReady = false, error = (e as? ProtocolException)?.code ?: "LOCAL_OPERATION_FAILED") }
    private suspend fun <T> command(block: () -> T): T = withContext(Dispatchers.IO) { lock.withLock { block().also { reload(); client?.changed() } } }
    suspend fun close() {
        connectionJob?.cancelAndJoin(); refreshJob?.cancelAndJoin()
        withContext(Dispatchers.IO) { lock.withLock { if (::db.isInitialized) db.close() } }
    }
    fun clearError() { _state.value = _state.value.copy(error = null) }
    suspend fun localWrite(entityId: String, type: String, action: String, fields: Map<String, JsonObject>, now: Instant = clock.now()): String = command {
        val r = replica
        // SQLite transaction serializes quota validation, candidate projection, facts and Lamport.
        fun write(): String {
            val clock = r?.nextClock() ?: ((store.local("local-lamport")?.toString(Charsets.UTF_8)?.toLong() ?: 0L) + 1)
            val id = uid(); val d = identity.descriptor
            val operation = SyncOperation(id, d.deviceId, d.userId, uuid(entityId), type, action, clock, fields, now.toEpochMilli())
            val signed = identity.sign(operation); val old = store.records().map { it.record.operation }
            val candidate = Projector.replay(old + signed, domainContext())
            requireProtocol(candidate.conflicts.none { it.operationId == id }, "INVALID_DOMAIN_OPERATION")
            if (r != null) r.append(listOf(operation)) else {
                signed.verify(d); store.put(StoredRecord(ReplicationRecord("legacy", legacy = signed), true)); store.local("local-lamport", clock.toString().toByteArray())
            }
            return id
        }
        if (r != null) r.atomicCommand { write() } else store.transaction { write() }
    }
    suspend fun saveTask(id: String? = null, title: String, notes: String = "") {
        requireProtocol(title.isNotBlank() && title.graphemeCount() <= 200 && notes.length <= 10_000, "INVALID_TASK")
        val c = state.value.descriptor ?: throw ProtocolException("NOT_READY")
        val space = state.value.authorization?.spaceId ?: c.initialSpaceId
        val fields = mutableMapOf("title" to LogValue.string(title.trim()), "notes" to LogValue.string(notes))
        if (id == null) { fields["spaceId"] = LogValue.string(space); fields["createdBy"] = LogValue.string(c.userId) }
        localWrite(id ?: uid(), "task", if (id == null) "create" else "patch", fields)
    }
    suspend fun completeTask(entity: ProjectedEntity) { localWrite(entity.id, "task", if (entity.fields.text("status") == "completed") "reopenTask" else "completeTask", emptyMap()) }
    suspend fun deleteTask(id: String) { localWrite(id, "task", "delete", emptyMap()) }
    suspend fun markReviewed(ids: Set<String>) = command { store.local("reviewed", Canonical.encode(_state.value.reviewed + ids)) }
    suspend fun stageOffer(bytes: ByteArray, displayName: String, confirmed: Boolean): ByteArray = command {
        requireProtocol(confirmed, "IDENTITY_CONFIRMATION_REQUIRED")
        requireProtocol(replica == null && store.records().all { it.record.operation.operation.entityType == "profile" }, "EXISTING_LOCAL_DATA")
        val offer = Canonical.parse(bytes, 524_288).model<EnrollmentOffer>()
        val trust = offer.verify(clock.now().toEpochMilli(), com.together.android.BuildConfig.DEBUG)
        val name = displayName.trim(); requireProtocol(name.isNotEmpty() && name.length <= 80, "INVALID_DEVICE_NAME")
        val pending = store.local("pending-enrollment")?.let { Canonical.parse(it).jsonObject }
        val request = if (pending != null) {
            requireProtocol(pending.getValue("offer").model<EnrollmentOffer>() == offer, "PENDING_ENROLLMENT_EXISTS")
            pending.getValue("request").model<EnrollmentRequest>().also { it.verify(offer, clock.now().toEpochMilli(), com.together.android.BuildConfig.DEBUG); requireProtocol(identities.load(offer.body.id).descriptor == it.body.device, "IDENTITY_MISMATCH") }
        } else {
            val newIdentity = identities.create(offer.body.id, offer.body.ownerId, trust.spaceId, name, trust.archive.genesis.body.sharedTimeZoneIdentifier)
            EnrollmentRequest.create(offer, newIdentity, clock.now().toEpochMilli(), com.together.android.BuildConfig.DEBUG)
        }
        store.local("pending-enrollment", Canonical.bytes(buildJsonObject { put("offer", offer.json()); put("request", request.json()) }))
        _state.value = _state.value.copy(offer = offer, request = request)
        Canonical.encode(request)
    }
    suspend fun completeEnrollment(bytes: ByteArray, confirmed: Boolean) = command {
        requireProtocol(confirmed, "IDENTITY_CONFIRMATION_REQUIRED")
        val offer = _state.value.offer ?: throw ProtocolException("NO_PENDING_ENROLLMENT")
        val request = _state.value.request ?: throw ProtocolException("NO_PENDING_ENROLLMENT")
        val completion = Canonical.parse(bytes).model<EnrollmentCompletion>()
        val trust = completion.verify(request, offer, com.together.android.BuildConfig.DEBUG)
        val newIdentity = identities.load(offer.body.id)
        requireProtocol(newIdentity.descriptor == request.body.device, "IDENTITY_MISMATCH")
        val newDb = TogetherDatabase.open(context, databaseName("replica-${offer.body.id}.db"))
        val newStore = RoomReplicaStore(newDb)
        try {
            newStore.transaction {
                val prior = newStore.local("authorization")?.let { SpaceAuthorization.restore(Canonical.parse(it).model()) }
                requireProtocol(prior == null || trust.extends(prior), "STALE_AUTHORIZATION")
                newStore.local("authorization", Canonical.encode(trust.archive)); newStore.local("binding", Canonical.encode(completion.body.binding))
                newStore.local("enrollment-completion", bytes)
            }
            Replica(newStore, newIdentity, trust).restore()
            val output = marker.startWrite()
            try { output.write(Canonical.bytes(buildJsonObject { put("offerId", offer.body.id) })); marker.finishWrite(output) } catch (e: Exception) { marker.failWrite(output); throw e }
        } finally { newDb.close() }
        db.close(); replica = null; open(); _state.value = _state.value.copy(offer = null, request = null)
    }
    suspend fun revoke(deviceId: String) = command {
        val r = replica ?: throw ProtocolException("NOT_PAIRED"); val trust = r.trust
        val root = trust.root(identity.descriptor.userId) ?: throw ProtocolException("NOT_AN_OWNER")
        requireProtocol(root.deviceId == identity.descriptor.deviceId, "OWNER_ROOT_REQUIRED")
        val device = trust.devices[deviceId] ?: throw ProtocolException("UNKNOWN_DEVICE")
        requireProtocol(device.active && deviceId != root.deviceId && device.descriptor.userId == identity.descriptor.userId, "INVALID_REVOCATION")
        val events = trust.archive.events.filter { it.body.ownerId == identity.descriptor.userId }
        val head = events.lastOrNull()
        val body = AuthorizationBody(spaceId = trust.spaceId, ownerId = identity.descriptor.userId, revision = (head?.body?.revision ?: 0) + 1,
            previousDigest = head?.digest ?: trust.archive.genesis.digest, authorizerDeviceId = root.deviceId, action = "revoke", device = device.descriptor, epochId = device.epochId, cutoff = r.frontier(deviceId))
        val event = AuthorizationEvent(body, identity.sign(Canonical.encode(body)))
        val state = RelayApi(binding!!, identity, com.together.android.BuildConfig.DEBUG).authorize(event)
        val next = state.verify(identity.descriptor, trust); r.updateAuthorization(next.archive)
    }
    fun foreground(value: Boolean) {
        foreground = value
        if (value) startConnection() else { connectionJob?.cancel(); connectionJob = null }
    }
    private fun startConnection() {
        if (connectionJob?.isActive == true) return
        val c = client ?: return
        connectionJob = scope.launch(Dispatchers.IO) {
            launch { combine(c.state, c.error) { s, e -> s to e }.collect { (s, e) -> _state.value = _state.value.copy(connection = s, error = e ?: _state.value.error) } }
            c.run()
        }
    }
}
