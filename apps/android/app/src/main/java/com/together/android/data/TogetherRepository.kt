package com.together.android.data

import android.content.Context
import android.util.AtomicFile
import com.together.domain.*
import com.together.protocol.*
import java.io.File
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*

/** App-private Room/Keystore only. No production Mac path or bundled user store. */
class TogetherRepository(
    private val context: Context,
    private val scope: CoroutineScope,
    private val namespace: String? = null,
    private val clock: DateProvider = systemDateProvider,
    private val serviceURL: String = com.together.android.BuildConfig.RELAY_URL,
) {
    init {
        requireProtocol(!com.together.android.BuildConfig.NATIVE_QA ||
            (context.packageName == "com.together.android.qa.native" && namespace == "NATIVE-APP" && serviceURL.isEmpty()),
            "ISOLATED_NATIVE_QA_REQUIRED")
        requireProtocol(
            namespace == null ||
                (com.together.android.BuildConfig.DEBUG &&
                    Regex("[A-Z0-9-]{1,45}").matches(namespace)),
            "INVALID_WORKSPACE",
        )
    }

    private val workspaceRoot =
        if (namespace == null) context.noBackupFilesDir
        else File(context.noBackupFilesDir, "qa-$namespace").apply { mkdirs() }

    private fun databaseName(value: String) =
        if (namespace == null) value else "qa-$namespace-$value"

    data class State(
        val loaded: Boolean = false,
        val historyReady: Boolean = true,
        val snapshot: Snapshot = Snapshot(),
        val descriptor: DeviceDescriptor? = null,
        val authorization: SpaceAuthorization? = null,
        val connection: String = "offline",
        val error: String? = null,
        val connectionError: String? = null,
        val reviewed: Set<String> = emptySet(),
        val notified: Set<String> = emptySet(),
        val now: Instant = Instant.EPOCH,
        val draft: GiftDraft = GiftDraft(),
        val presentations: Map<String, GiftPresentation> = emptyMap(),
        val staged: Map<String, Asset> = emptyMap(),
        val privateCards: List<JsonObject> = emptyList(),
        val dismissedReminders: Set<String> = emptySet(),
        val transfers: Map<String, Transfer> = emptyMap(),
        val operationStates: Map<String, String> = emptyMap(),
        val autoGifts: List<String> = emptyList(),
        val giftSynced: Set<String> = emptySet(),
        val offer: EnrollmentOffer? = null,
        val request: EnrollmentRequest? = null,
        val partnerPairing: PartnerPairingState = PartnerPairingState(),
        val native: NativeAppStatus? = null,
    ) {
        val canWrite: Boolean
            get() =
                descriptor != null &&
                    historyReady &&
                    (authorization == null || authorization.active(descriptor))
    }

    private val _state = MutableStateFlow(State())
    val state = _state.asStateFlow()
    private val identities = AndroidIdentityStore(context, namespace)
    private val lock = Mutex()
    private val refresh = Channel<Unit>(Channel.CONFLATED)
    private lateinit var db: TogetherDatabase
    private lateinit var store: RoomReplicaStore
    private lateinit var identity: DeviceIdentity
    private var replica: Replica? = null
    private var client: C1Client? = null
    private var partnerClient: PartnerPairingClient? = null
    private var partnerStateJob: Job? = null
    private var partnerPeer: DeviceDescriptor? = null
    private var nativeSession: NativeAppSession? = null
    private var nativeStateJob: Job? = null
    private var nativeGateDiagnostic: String? = null
    private var connectionJob: Job? = null
    private var refreshJob: Job? = null
    private val connectionLock = Mutex()
    @Volatile private var foreground = false
    private var binding: C1Binding? = null
    lateinit var mediaFiles: MediaFiles
        private set

    private var mediaExchange: MediaExchange? = null
    private var cachedInbox: Set<String>? = null
    private var firstSync = false
    private val startupDeadline = clock.now().plusSeconds(15)
    @Volatile private var interacted = false
    private var autoShown = false
    private var tickJob: Job? = null
    private val marker = AtomicFile(File(workspaceRoot, "active-replica.json"))

    init {
        refreshJob =
            scope.launch(Dispatchers.IO) {
                try {
                    lock.withLock {
                        open()
                        reload()
                    }
                } catch (e: Exception) {
                    failed(e)
                }
                tickJob = scope.launch {
                    while (isActive) {
                        delay(30_000)
                        refresh.trySend(Unit)
                    }
                }
                for (ignored in refresh) {
                    delay(100)
                    try {
                        lock.withLock { reload() }
                    } catch (e: Exception) {
                        failed(e)
                    }
                }
            }
    }

    private fun publicJson(o: JsonObject, key: String) =
        o[key]?.jsonPrimitive?.content ?: throw ProtocolException("INVALID_WORKSPACE")

    private fun open() {
        val pointer =
            if (marker.baseFile.exists()) Canonical.parse(marker.readFully(), 4096).jsonObject
            else null
        val slot = pointer?.let { uuid(publicJson(it, "offerId")) } ?: "LOCAL"
        val databaseName =
            databaseName(if (slot == "LOCAL") "together-local.db" else "replica-$slot.db")
        val needsExisting = pointer != null || context.getDatabasePath(databaseName).exists()
        identity =
            if (identities.exists(slot)) identities.load(slot)
            else {
                requireProtocol(!needsExisting, "IDENTITY_FILE_UNAVAILABLE")
                identities.create(
                    slot,
                    uid(),
                    uid(),
                    android.os.Build.MODEL.take(80),
                    ZoneId.systemDefault().id,
                )
            }
        mediaFiles =
            MediaFiles(File(workspaceRoot, "media-$slot"), validateFormat = AndroidMedia::validate)
        db = TogetherDatabase.open(context, databaseName)
        store = RoomReplicaStore(db)
        partnerPeer = store.local("partner-peer")?.let { Canonical.parse(it).model<DeviceDescriptor>() }
        db.dao().clearSnapshots()
        val archive =
            store.local("authorization")?.let { Canonical.parse(it).model<AuthorizationArchive>() }
        if (archive != null) {
            val trust = SpaceAuthorization.restore(archive)
            replica = Replica(store, identity, trust).also { it.restore() }
            if (com.together.android.BuildConfig.NATIVE_QA) {
                requireProtocol(store.local("native-binding") != null, "MISSING_NATIVE_BINDING")
            } else {
                binding =
                    store.local("binding")?.let { Canonical.parse(it).model<C1Binding>() }
                        ?: throw ProtocolException("MISSING_RELAY_BINDING")
                requireProtocol(
                    binding!!.spaceId == trust.spaceId &&
                        binding!!.localDeviceId == identity.descriptor.deviceId,
                    "BINDING_IDENTITY_MISMATCH",
                )
                configureClient()
            }
        } else {
            requireProtocol(pointer == null, "MISSING_AUTHORIZATION")
            // Unpaired private local workspace; not exposed as certified Protocol 4 history.
            val pendingPeer = partnerPeer.takeIf { store.local("partner-pending") != null }
            store.records().forEach {
                val op = it.record.operation
                val signer = if (op.operation.deviceId == identity.descriptor.deviceId) identity.descriptor
                    else pendingPeer ?: throw ProtocolException("UNAUTHORIZED_PENDING_HISTORY")
                op.verify(signer)
            }
        }
        val pending = store.local("pending-enrollment")?.let { Canonical.parse(it).jsonObject }
        _state.update {
            it.copy(
                descriptor = identity.descriptor,
                offer = pending?.get("offer")?.model(),
                request = pending?.get("request")?.model(),
            )
        }
        if (com.together.android.BuildConfig.NATIVE_QA) configureNative()
        else if (replica == null) {
            store.local("partner-route")?.let { bytes ->
                val route = Canonical.parse(bytes).model<PartnerRoute>()
                partnerClient = makePartnerClient().also { it.resume(route.routeId) }
            }
        }
    }

    private fun configureNative() {
        requireProtocol(com.together.android.BuildConfig.NATIVE_QA && namespace == "NATIVE-APP" && binding == null,
            "ISOLATED_NATIVE_QA_REQUIRED")
        replica?.let(::configureMedia)
        val host = object : NativeAppRepository {
            override suspend fun <T> access(block: (NativeRepositoryContext) -> T): T = withContext(Dispatchers.IO) {
                lock.withLock { block(NativeRepositoryContext(identity, store, replica, mediaExchange)) }
            }
            override suspend fun pin(peer: DeviceDescriptor) = withContext(Dispatchers.IO) {
                lock.withLock {
                    requireProtocol(replica == null && peer.userId != identity.descriptor.userId &&
                        (partnerPeer == null || partnerPeer == peer), "IDENTITY_MISMATCH")
                    store.transaction {
                        store.local("partner-peer", Canonical.encode(peer))
                        store.local("partner-pending", byteArrayOf(1))
                    }
                    partnerPeer = peer; reload()
                }
            }
            override suspend fun activate(archive: AuthorizationArchive, peer: DeviceDescriptor, binding: ByteArray) = withContext(Dispatchers.IO) {
                lock.withLock {
                    val trust = SpaceAuthorization.restore(archive)
                    requireProtocol(trust.active(identity.descriptor) && trust.active(peer) &&
                        peer == partnerPeer && archive.genesis.body.legacyCheckpoint == checkpoint(store.records().map { it.record.entry }),
                        "INVENTORY_CHANGED")
                    requireProtocol(replica == null || replica!!.trust.archive == trust.archive, "ALREADY_PAIRED")
                    val next = Replica(store, identity, trust)
                    store.transaction {
                        store.local("authorization", Canonical.encode(trust.archive))
                        store.local("native-binding", binding)
                        next.restore(); store.removeLocal("partner-pending")
                        store.removeLocal("native-pending-contact")
                        store.removeLocal("native-prepared-genesis")
                    }
                    replica = next; configureMedia(next); reload()
                }
            }
            override suspend fun refreshed() = withContext(Dispatchers.IO) {
                lock.withLock { reload() }
            }
        }
        val factory = Class.forName("com.together.android.p2p.NativeQaSessionFactory")
            .getDeclaredConstructor().newInstance() as NativeAppSessionFactory
        val created = factory.create(context, scope, host)
        nativeSession = created
        nativeStateJob = scope.launch {
            created.state.collect { value ->
                android.util.Log.i("TogetherNativeQa", "phase=${value.stage} offline=${value.offline} path=${value.path ?: "unknown"}")
                if (nativeSession === created) _state.update { old ->
                    old.copy(native = value, connection = when (value.stage) {
                        "connected" -> "connected"
                        "syncing" -> "syncing"
                        "connecting", "authenticating", "waiting" -> "connecting"
                        "verifying", "confirming" -> "pairing"
                        else -> "offline"
                    }, connectionError = value.error)
                }
            }
        }
        created.foreground(foreground)
    }

    private fun configureClient() {
        val r = replica ?: return
        val b = binding ?: return
        val api = RelayApi(b, identity, allowLocal = com.together.android.BuildConfig.DEBUG)
        configureMedia(r)
        client = C1Client(r, b, api, onPersisted = { refresh.trySend(Unit) }, media = mediaExchange)
        if (foreground) startConnection()
    }

    private fun configureMedia(r: Replica) {
        mediaExchange =
            MediaExchange(
                mediaFiles,
                ::snapshot,
                identity,
                { r.trust.active(it) },
                { remote, receipt ->
                    val body = buildJsonObject {
                        put("remote", remote.json())
                        put("receipt", receipt)
                    }
                    store.local(
                        "gift-receipt:" + receipt.getValue("giftId").jsonPrimitive.content,
                        Canonical.bytes(identity.signed(body)),
                    )
                },
                { transfer ->
                    _state.update {
                        it.copy(transfers = it.transfers + (transfer.assetId to transfer))
                    }
                    refresh.trySend(Unit)
                },
            )
    }

    private fun domainContext(): DomainContext =
        replica?.trust?.let(DomainContext::from)
            ?: partnerPeer?.let { peer ->
                val roots = listOf(identity.descriptor, peer).sortedBy { it.deviceId }
                val space = stableId("space:" + roots.joinToString(":") { it.deviceId })
                DomainContext(space, roots.map { it.userId }.toSet(),
                    (roots.map { it.initialSpaceId } + space).toSet(),
                    roots.first().initialTimeZoneIdentifier ?: "Etc/UTC", roots.first().userId)
            }
            ?: DomainContext(
                identity.descriptor.initialSpaceId,
                setOf(identity.descriptor.userId),
                setOf(identity.descriptor.initialSpaceId),
                identity.descriptor.initialTimeZoneIdentifier ?: "Etc/UTC",
                identity.descriptor.userId,
            )

    private fun snapshot(): Snapshot =
        if (replica != null && !replica!!.legacyComplete()) Snapshot()
        else Projector.replay(store.records().map { it.record.operation }, domainContext())

    private fun reconcile() {
        if (replica == null && store.local("partner-pending") != null) return
        val r = replica
        if (r != null && !r.legacyComplete()) return
        fun apply() {
            while (true) {
                val old = store.records().map { it.record.operation }
                val current = Projector.replay(old, domainContext())
                val mutations =
                    (RecurrencePlanner.pending(
                            current,
                            domainContext(),
                            identity.descriptor.userId,
                        ) +
                            BillPlanner.pending(
                                current,
                                domainContext(),
                                identity.descriptor.userId,
                                clock,
                            ))
                        .take(32)
                if (mutations.isEmpty()) break
                val clock =
                    r?.nextClock()
                        ?: ((store.local("local-lamport")?.toString(Charsets.UTF_8)?.toLong()
                            ?: 0) + 1)
                val now = this@TogetherRepository.clock.now().toEpochMilli()
                val operations = mutations.mapIndexed { index, m ->
                    SyncOperation(
                        uid(),
                        identity.descriptor.deviceId,
                        identity.descriptor.userId,
                        m.entityId,
                        m.entityType,
                        m.operationType,
                        clock + index,
                        m.payload,
                        now,
                    )
                }
                val signed = operations.map(identity::sign)
                val candidate = Projector.replay(old + signed, domainContext())
                val ids = operations.map { it.operationId }.toSet()
                requireProtocol(
                    candidate.conflicts.none { it.operationId in ids },
                    "INVALID_DOMAIN_OPERATION",
                )
                if (r != null) r.append(operations)
                else {
                    signed.forEach {
                        store.put(StoredRecord(ReplicationRecord("legacy", legacy = it), true))
                    }
                    store.local(
                        "local-lamport",
                        operations.last().lamportClock.toString().toByteArray(),
                    )
                }
            }
        }
        if (r != null) r.atomicCommand { apply() } else store.transaction { apply() }
    }

    private fun reload() {
        val factsBefore = db.dao().count()
        reconcile()
        val reviewed =
            store.local("reviewed")?.let { Canonical.parse(it).model<Set<String>>() } ?: emptySet()
        val projected = snapshot()
        val currentTrust = replica?.trust
        val historyReady = (replica?.legacyComplete() ?: true) && (replica != null || store.local("partner-pending") == null)
        if (com.together.android.BuildConfig.NATIVE_QA) {
            val diagnostic = "paired=${currentTrust != null} historyReady=$historyReady nativeSession=${nativeSession != null}"
            if (diagnostic != nativeGateDiagnostic) {
                nativeGateDiagnostic = diagnostic
                android.util.Log.i("TogetherNativeQa", diagnostic)
            }
        }
        val inbox =
            projected.gifts.values.filter {
                it.effective &&
                    it.entity.deletedAt == null &&
                    it.entity.fields.id("recipientId") == identity.descriptor.userId &&
                    it.entity.fields.id("senderId") != identity.descriptor.userId
            }
        if (cachedInbox == null) cachedInbox = inbox.map { it.id }.toSet()
        if (!firstSync && _state.value.connection == "connected") {
            firstSync = true
            if (!interacted && clock.now() <= startupDeadline)
                cachedInbox = cachedInbox!! + inbox.map { it.id }
        }
        val presentations =
            projected.gifts.keys.associateWith { id ->
                store.local("gift-presentation:$id")?.let {
                    Canonical.parse(it).model<GiftPresentation>()
                } ?: GiftPresentation()
            }
        val autoGifts =
            if (interacted || autoShown) emptyList()
            else
                inbox
                    .filter {
                        it.id in cachedInbox!! &&
                            presentations[it.id]?.hasAutoPresented != true &&
                            presentations[it.id]?.openedAt == null &&
                            giftAssets(it).all { id ->
                                projected.entities[id]
                                    ?.let(Asset::from)
                                    ?.let(mediaFiles::verified) == true
                            }
                    }
                    .sortedByDescending { it.entity.fields.date("sentAt") }
                    .map { it.id }
        val operationStates =
            projected.changes.associate { change ->
                val row = store.get(change.operationId)
                val persisted =
                    row?.let { r -> replica?.persistedDevices(r.record.entry) } ?: emptySet()
                val status =
                    if (
                        change.actorId != identity.descriptor.userId ||
                            change.deviceId != identity.descriptor.deviceId
                    )
                        "remotePersisted"
                    else if (replica == null) "local"
                    else if (row != null && replica!!.partnerPersisted(row.record.entry)) {
                        if (
                            replica!!
                                .trust
                                .devices
                                .values
                                .filter {
                                    it.active &&
                                        it.descriptor.deviceId != identity.descriptor.deviceId
                                }
                                .all { it.descriptor.deviceId in persisted }
                        )
                            "converged"
                        else "remotePersisted"
                    } else "pending"
                change.operationId to status
            }
        val synced =
            projected.gifts.values
                .filter { gift ->
                    store.local("gift-receipt:${gift.id}")?.let { bytes ->
                        runCatching {
                                val signed = Canonical.parse(bytes).jsonObject
                                val body = signed.getValue("body").jsonObject
                                val remote = body.getValue("remote").model<DeviceDescriptor>()
                                Crypto.verify(
                                    identity.descriptor.publicKey.unbase64(),
                                    signed.getValue("signature").jsonPrimitive.content.unbase64(),
                                    Canonical.bytes(body),
                                ) &&
                                    currentTrust?.active(remote) == true &&
                                    remote.userId == gift.entity.fields.id("recipientId") &&
                                    remote.userId != identity.descriptor.userId &&
                                    normalizedReceipt(body.getValue("receipt").jsonObject) ==
                                        expectedReceipt(gift, projected)
                            }
                            .getOrDefault(false)
                    } == true
                }
                .map { it.id }
                .toSet()
        _state.update {
            it.copy(
                loaded = true,
                historyReady = historyReady,
                descriptor = identity.descriptor,
                authorization = currentTrust,
                native = nativeSession?.state?.value ?: it.native,
                snapshot = projected,
                reviewed = reviewed,
                notified = localModel("notified") ?: emptySet(),
                now = clock.now(),
                draft = localModel("gift-draft") ?: GiftDraft(),
                staged =
                    (localModel<List<Asset>>("staged-assets") ?: emptyList()).associateBy {
                        it.assetId
                    },
                privateCards = localModel("private-cards") ?: emptyList(),
                dismissedReminders = localModel("dismissed-reminders") ?: emptySet(),
                presentations = presentations,
                autoGifts = autoGifts,
                operationStates = operationStates,
                giftSynced = synced,
            )
        }
        if (db.dao().count() != factsBefore) { client?.changed(); nativeSession?.changed() }
    }

    private fun failed(e: Exception) {
        connectionJob?.cancel()
        _state.update {
            it.copy(
                loaded = true,
                historyReady = false,
                error = (e as? ProtocolException)?.code ?: "LOCAL_OPERATION_FAILED",
            )
        }
    }

    private suspend fun <T> command(block: () -> T): T =
        withContext(Dispatchers.IO) {
            lock.withLock {
                val before = db.dao().count()
                block().also {
                    reload()
                    if (db.dao().count() != before) { client?.changed(); nativeSession?.changed() }
                }
            }
        }

    suspend fun close() {
        nativeSession?.close(); nativeStateJob?.cancelAndJoin()
        partnerClient?.stop(); partnerStateJob?.cancelAndJoin()
        connectionLock.withLock {
            connectionJob?.cancelAndJoin()
            connectionJob = null
        }
        refreshJob?.cancelAndJoin()
        tickJob?.cancelAndJoin()
        withContext(Dispatchers.IO) {
            lock.withLock { if (::db.isInitialized && db.isOpen) db.close() }
        }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }

    suspend fun localWrite(
        entityId: String,
        type: String,
        action: String,
        fields: Map<String, JsonObject>,
        now: Instant = clock.now(),
    ): String = command {
        requireProtocol(replica != null || store.local("partner-pending") == null, "PAIRING_FINISHING")
        val r = replica
        // SQLite transaction serializes quota validation, candidate projection, facts and Lamport.
        fun write(): String {
            val clock =
                r?.nextClock()
                    ?: ((store.local("local-lamport")?.toString(Charsets.UTF_8)?.toLong() ?: 0L) +
                        1)
            val id = uid()
            val d = identity.descriptor
            val operation =
                SyncOperation(
                    id,
                    d.deviceId,
                    d.userId,
                    uuid(entityId),
                    type,
                    action,
                    clock,
                    fields,
                    now.toEpochMilli(),
                )
            val signed = identity.sign(operation)
            val old = store.records().map { it.record.operation }
            val candidate = Projector.replay(old + signed, domainContext())
            requireProtocol(
                candidate.conflicts.none { it.operationId == id },
                "INVALID_DOMAIN_OPERATION",
            )
            if (r != null) r.append(listOf(operation))
            else {
                signed.verify(d)
                store.put(StoredRecord(ReplicationRecord("legacy", legacy = signed), true))
                store.local("local-lamport", clock.toString().toByteArray())
            }
            return id
        }
        if (r != null) r.atomicCommand { write() } else store.transaction { write() }
    }

    suspend fun saveTask(id: String? = null, title: String, notes: String = "") {
        execute { task(id, title, notes, null, null, null) }
    }

    suspend fun completeTask(entity: ProjectedEntity) {
        execute { completion(entity) }
    }

    suspend fun deleteTask(id: String) {
        execute { listOf(delete(id)) }
    }

    private inline fun <reified T> localModel(key: String): T? =
        store.local(key)?.let { Canonical.parse(it).model<T>() }

    fun noteInteraction() {
        interacted = true
    }

    fun canPresentAutomatically() = !interacted && !autoShown

    suspend fun execute(build: BusinessCommands.() -> List<PlannedMutation>) = command {
        requireProtocol(_state.value.canWrite, "NOT_READY")
        fun write() {
            val old = store.records().map { it.record.operation }
            val c = domainContext()
            val before = Projector.replay(old, c)
            val mutations =
                BusinessCommands(before, c, identity.descriptor.userId, clock.now())
                    .build()
                    .filter { it.operationType != "patch" || it.payload.isNotEmpty() }
            if (mutations.isEmpty()) return
            requireProtocol(mutations.size <= 32, "COMMAND_BOUNDS")
            val next =
                replica?.nextClock()
                    ?: ((store.local("local-lamport")?.toString(Charsets.UTF_8)?.toLong() ?: 0) + 1)
            val operations = mutations.mapIndexed { i, m ->
                SyncOperation(
                    uid(),
                    identity.descriptor.deviceId,
                    identity.descriptor.userId,
                    m.entityId,
                    m.entityType,
                    m.operationType,
                    next + i,
                    m.payload,
                    clock.now().toEpochMilli(),
                )
            }
            val signed = operations.map(identity::sign)
            val projected = Projector.replay(old + signed, c)
            val ids = operations.map { it.operationId }.toSet()
            requireProtocol(
                projected.conflicts.none { it.operationId in ids },
                "INVALID_DOMAIN_OPERATION",
            )
            if (replica != null) replica!!.append(operations)
            else {
                signed.forEach {
                    store.put(StoredRecord(ReplicationRecord("legacy", legacy = it), true))
                }
                store.local(
                    "local-lamport",
                    operations.last().lamportClock.toString().toByteArray(),
                )
            }
        }
        if (replica != null) replica!!.atomicCommand { write() } else store.transaction { write() }
    }

    suspend fun saveDraft(draft: GiftDraft) = command {
        requireProtocol(
            draft.text.graphemeCount() <= 4000 && draft.text.toByteArray().size <= 16000,
            "INVALID_GIFT",
        )
        store.local("gift-draft", Canonical.encode(draft))
    }

    suspend fun sendGift(draft: GiftDraft) {
        execute {
            val partner =
                context.members.singleOrNull { it != actor }
                    ?: throw ProtocolException("NOT_PAIRED")
            val day = dayKey(now, context.zone)
            requireProtocol(!snapshot.giftUsed(actor, day), "GIFT_QUOTA_USED")
            val latest =
                snapshot.gifts.values
                    .filter { it.entity.fields.id("senderId") == actor }
                    .mapNotNull { it.entity.fields.text("sentDayKey") }
                    .maxOrNull()
            requireProtocol(latest == null || day >= latest, "CLOCK_MOVED_BACK")
            val assets = localModel<List<Asset>>("staged-assets") ?: emptyList()
            val ids = listOfNotNull(draft.audioAssetId, draft.photoAssetId)
            val media = ids.map { id ->
                snapshot.entities[id]?.let(Asset::from)
                    ?: assets.firstOrNull { it.assetId == id }
                    ?: throw ProtocolException("UNKNOWN_MEDIA")
            }
            media.forEach {
                requireProtocol(mediaFiles.verified(it) && it.ownerId == actor, "UNVERIFIED_MEDIA")
            }
            val group =
                media
                    .filter { it.assetId !in snapshot.entities }
                    .map { PlannedMutation(it.assetId, "mediaAsset", "create", it.fields()) }
            group +
                PlannedMutation(
                    stableId("gift:${context.spaceId}:$actor:$day"),
                    "loveGift",
                    "create",
                    mapOf(
                        "spaceId" to logId(context.spaceId),
                        "senderId" to logId(actor),
                        "recipientId" to logId(partner),
                        "textContent" to LogValue.string(draft.text),
                        "audioAssetId" to logId(draft.audioAssetId),
                        "photoAssetId" to logId(draft.photoAssetId),
                        "replyToGiftId" to logId(draft.replyToGiftId),
                        "sentAt" to LogValue.date(now.toEpochMilli()),
                        "sentDayKey" to LogValue.string(day),
                        "sharedTimeZoneIdentifier" to LogValue.string(context.zone),
                    ),
                )
        }
        runCatching { saveDraft(GiftDraft()) }
    }

    private data class ImportTarget(val files: MediaFiles, val owner: String, val space: String)

    private suspend fun importTarget() =
        withContext(Dispatchers.IO) {
            lock.withLock {
                ImportTarget(mediaFiles, identity.descriptor.userId, domainContext().spaceId)
            }
        }

    private suspend fun importStaged(
        read: suspend (ImportTarget, MediaImportLease) -> Unit
    ): Asset {
        val target = importTarget()
        val lease = MediaImportLease(target.files)
        try {
            read(target, lease)
            val asset = lease.asset ?: throw ProtocolException("MEDIA_IO_ERROR")
            return command {
                // Never attach a file selected in another workspace to the active identity.
                requireProtocol(
                    mediaFiles === target.files &&
                        identity.descriptor.userId == target.owner &&
                        domainContext().spaceId == target.space,
                    "INVALID_WORKSPACE",
                )
                store.local(
                    "staged-assets",
                    Canonical.encode(
                        (localModel<List<Asset>>("staged-assets") ?: emptyList()) + asset
                    ),
                )
                lease.commit()
                asset
            }
        } finally {
            withContext(NonCancellable + Dispatchers.IO) { lease.close() }
        }
    }

    suspend fun importMedia(uri: android.net.Uri, type: String): Asset =
        importStaged { target, lease ->
            // A document provider controls I/O latency. It must never own the repository mutex.
            AndroidMedia.importDocument(
                context,
                uri,
                target.files,
                type,
                target.owner,
                target.space,
                clock.now().toEpochMilli(),
                onImported = lease::acquired,
            )
        }

    suspend fun importRecorded(file: File): Asset = importOwnedMedia(file, "audio")

    suspend fun importOwnedMedia(file: File, type: String): Asset {
        requireProtocol(
            file.canonicalFile.toPath().startsWith(context.cacheDir.canonicalFile.toPath()),
            "INVALID_MEDIA_PATH",
        )
        return importStaged { target, lease ->
            withContext(Dispatchers.IO) {
                val job = currentCoroutineContext()
                try {
                    runInterruptible {
                        target.files.import(
                            file.inputStream(),
                            file.name,
                            file.extension.lowercase(),
                            type,
                            target.owner,
                            target.space,
                            clock.now().toEpochMilli(),
                            onImported = lease::acquired,
                            checkCancelled = { job.ensureActive() },
                        )
                    }
                } catch (error: Exception) {
                    job.ensureActive()
                    throw error
                }
            }
        }
    }

    suspend fun saveProfile(
        name: String,
        relationship: String,
        avatar: String?,
        baseline: ProjectedEntity? = null,
        clearLegacyAvatar: Boolean = false,
    ) = execute {
        val old = snapshot.entities[actor]
        val asset =
            avatar
                ?.takeIf { baseline == null || baseline.fields.id("avatarAssetId") != it }
                ?.let { id ->
                    snapshot.entities[id]?.let(Asset::from)
                        ?: localModel<List<Asset>>("staged-assets")?.firstOrNull {
                            it.assetId == id
                        }
                        ?: throw ProtocolException("UNKNOWN_MEDIA")
                }
        if (asset != null)
            requireProtocol(
                asset.mediaType == "avatar" && asset.ownerId == actor && mediaFiles.verified(asset),
                "UNVERIFIED_MEDIA",
            )
        val group =
            if (asset != null && asset.assetId !in snapshot.entities)
                listOf(PlannedMutation(asset.assetId, "mediaAsset", "create", asset.fields()))
            else emptyList()
        group +
            record(
                actor,
                "profile",
                mapOf(
                        "displayName" to LogValue.string(name),
                        "relationshipLabel" to
                            LogValue.string(
                                when (Relationship.parse(relationship)) {
                                    Relationship.BOYFRIEND -> "boyfriend"
                                    Relationship.GIRLFRIEND -> "girlfriend"
                                    else -> "unknown"
                                }
                            ),
                        "avatarAssetId" to logId(avatar),
                    )
                    .plus(
                        if (clearLegacyAvatar || old == null || asset != null)
                            mapOf("avatarData" to LogValue.nil)
                        else emptyMap()
                    )
                    .filter {
                        baseline == null || comparisonValue(baseline.fields, it.key) != it.value
                    } +
                    if (old == null) mapOf("deviceId" to logId(identity.descriptor.deviceId))
                    else emptyMap(),
            )
    }

    suspend fun presentedGift(id: String, automatic: Boolean) = command {
        requireProtocol(
            _state.value.snapshot.gifts[id]?.let { g ->
                g.effective &&
                    g.entity.deletedAt == null &&
                    g.entity.fields.id("recipientId") == identity.descriptor.userId &&
                    giftAssets(g).all { a ->
                        _state.value.snapshot.entities[a]
                            ?.let(Asset::from)
                            ?.let(mediaFiles::verified) == true
                    }
            } == true,
            "INVALID_GIFT",
        )
        val old = localModel<GiftPresentation>("gift-presentation:$id") ?: GiftPresentation()
        if (automatic) {
            store.local(
                "gift-presentation:$id",
                Canonical.encode(
                    old.copy(
                        hasAutoPresented = true,
                        autoPresentedAt = old.autoPresentedAt ?: clock.now().toEpochMilli(),
                    )
                ),
            )
            autoShown = true
        }
    }

    suspend fun openedGift(id: String) = command {
        val old = localModel<GiftPresentation>("gift-presentation:$id") ?: GiftPresentation()
        store.local(
            "gift-presentation:$id",
            Canonical.encode(old.copy(openedAt = old.openedAt ?: clock.now().toEpochMilli())),
        )
    }

    suspend fun retryMedia() = command {
        mediaExchange?.retry()
        client?.changed()
        nativeSession?.changed()
    }

    suspend fun dismissReminder(id: String) = command {
        store.local("dismissed-reminders", Canonical.encode(_state.value.dismissedReminders + id))
    }

    suspend fun saveCard(card: JsonObject) = execute {
        requireProtocol(
            card.getValue("ownerId").jsonPrimitive.content == actor &&
                card.getValue("holderId").jsonPrimitive.content in context.members &&
                card.getValue("name").jsonPrimitive.content.isNotBlank() &&
                card.getValue("name").jsonPrimitive.content.length <= 60 &&
                card.getValue("bankName").jsonPrimitive.content.isNotBlank() &&
                card.getValue("bankName").jsonPrimitive.content.length <= 100 &&
                Regex("[0-9]{4}").matches(card.getValue("lastFour").jsonPrimitive.content) &&
                card.getValue("cardKind").jsonPrimitive.content in setOf("debit", "credit") &&
                card["currencyCode"]?.jsonPrimitive?.content?.let { it in Money.precisions } !=
                    false,
            "INVALID_CARD",
        )
        val id = uuid(card.getValue("id").jsonPrimitive.content)
        val shared = card.getValue("isShared").jsonPrimitive.boolean
        val old = localModel<List<JsonObject>>("private-cards") ?: emptyList()
        // Local private archive and any public visibility operation share the same SQLite
        // transaction.
        store.local(
            "private-cards",
            Canonical.encode(
                old.filter { it.getValue("id").jsonPrimitive.content != id } +
                    if (shared) emptyList() else listOf(card)
            ),
        )
        when {
            shared ->
                listOf(
                    record(
                        id,
                        "paymentMethod",
                        mapOf(
                            "ownerId" to logId(actor),
                            "card" to logData(card),
                            "shared" to LogValue.bool(true),
                        ),
                    )
                )
            snapshot.entities[id] != null ->
                listOf(record(id, "paymentMethod", mapOf("shared" to LogValue.bool(false)), false))
            else -> emptyList()
        }
    }

    suspend fun deleteCard(id: String) = execute {
        val card =
            (localModel<List<JsonObject>>("private-cards") ?: emptyList()).firstOrNull {
                it.getValue("id").jsonPrimitive.content == id
            }
        requireProtocol(
            card?.get("ownerId")?.jsonPrimitive?.content == actor ||
                snapshot.entities[id]?.fields?.id("ownerId") == actor,
            "OWNER_ONLY",
        )
        store.local(
            "private-cards",
            Canonical.encode(
                (localModel<List<JsonObject>>("private-cards") ?: emptyList()).filter {
                    it.getValue("id").jsonPrimitive.content != id
                }
            ),
        )
        if (snapshot.entities[id] != null) listOf(delete(id)) else emptyList()
    }

    suspend fun reviewPage(domain: String, page: Int): List<ChangeEvent> {
        val input =
            withContext(Dispatchers.IO) {
                lock.withLock {
                    Triple(store.records().map { it.record.operation }, domainContext(), snapshot())
                }
            }
        return withContext(Dispatchers.Default) {
            ChangeReview.page(input.first, input.second, input.third, domain, page)
        }
    }

    suspend fun markNotified(ids: Set<String>) = command {
        store.local("notified", Canonical.encode(_state.value.notified + ids))
    }

    suspend fun markReviewed(ids: Set<String>) = command {
        store.local("reviewed", Canonical.encode(_state.value.reviewed + ids))
    }

    private fun makePartnerClient(): PartnerPairingClient {
        val origin = store.local("partner-origin")?.toString(Charsets.UTF_8) ?: serviceURL
        val uri = validOrigin(origin, com.together.android.BuildConfig.DEBUG)
        if (namespace != null) requireProtocol(
            uri.host in listOf("127.0.0.1", "localhost", "[::1]") ||
                (uri.scheme == "https" && uri.host == "together-pairing-staging.together-connection-service.workers.dev"),
            "ISOLATED_RELAY_REQUIRED")
        lateinit var created: PartnerPairingClient
        fun current() = requireProtocol(partnerClient === created, "PAIRING_CANCELLED")
        val history = object : PartnerHistory {
            override suspend fun joinRequest(code: String): String = withContext(Dispatchers.IO) {
                lock.withLock {
                    current()
                    val digest = sha256(code.toByteArray())
                    val old = store.local("partner-join-intent")?.let { Canonical.parse(it).jsonObject }
                    if (old?.get("codeDigest")?.jsonPrimitive?.content == digest) old.getValue("requestId").jsonPrimitive.content
                    else uid().also { id -> store.local("partner-join-intent", Canonical.bytes(buildJsonObject { put("codeDigest", digest); put("requestId", id) })) }
                }
            }
            override suspend fun prepare(genesis: SignedGenesis) = withContext(Dispatchers.IO) {
                lock.withLock {
                    current(); genesis.verify()
                    requireProtocol(genesis.body.roots.any { it == identity.descriptor } &&
                        genesis.body.roots.any { it == partnerPeer } &&
                        genesis.body.legacyCheckpoint == checkpoint(store.records().map { it.record.entry }), "INVENTORY_CHANGED")
                    store.local("partner-genesis", Canonical.encode(genesis))
                }
            }
            override suspend fun pendingGenesis(): SignedGenesis? = withContext(Dispatchers.IO) {
                lock.withLock { current(); store.local("partner-genesis")?.let { Canonical.parse(it).model<SignedGenesis>() } }
            }
            override suspend fun rememberRoute(route: PartnerRoute) = withContext(Dispatchers.IO) {
                lock.withLock {
                    current()
                    store.transaction {
                        store.local("partner-route", Canonical.encode(route))
                        store.local("partner-origin", origin.toByteArray())
                    }
                }
            }
            override suspend fun pin(peer: DeviceDescriptor, route: PartnerRoute) = withContext(Dispatchers.IO) {
                lock.withLock {
                    current(); requireProtocol(replica == null, "ALREADY_PAIRED")
                    requireProtocol(peer.userId != identity.descriptor.userId &&
                        (partnerPeer == null || partnerPeer == peer), "IDENTITY_MISMATCH")
                    store.transaction {
                        store.local("partner-peer", Canonical.encode(peer))
                        store.local("partner-route", Canonical.encode(route))
                        store.local("partner-origin", origin.toByteArray())
                        store.local("partner-pending", byteArrayOf(1))
                    }
                    partnerPeer = peer; reload()
                }
            }
            override suspend fun ownHistory(): List<SignedOperation> = withContext(Dispatchers.IO) {
                lock.withLock { current(); store.records().map { it.record.operation }.filter { it.operation.deviceId == identity.descriptor.deviceId } }
            }
            override suspend fun importBatch(operations: List<SignedOperation>) = withContext(Dispatchers.IO) {
                lock.withLock {
                    current(); requireProtocol(replica == null && store.local("partner-pending") != null, "PAIRING_NOT_READY")
                    val peer = partnerPeer ?: throw ProtocolException("PAIRING_NOT_READY")
                    requireProtocol(operations.size <= 32, "BATCH_BOUNDS")
                    store.transaction { operations.forEach { it.verify(peer); store.put(StoredRecord(ReplicationRecord("legacy", legacy = it), true)) } }
                }
            }
            override suspend fun checkpoint(): Checkpoint = withContext(Dispatchers.IO) {
                lock.withLock { current(); checkpoint(store.records().map { it.record.entry }) }
            }
            override suspend fun complete(authorization: AuthorizationArchive, binding: C1Binding) = withContext(Dispatchers.IO) {
                lock.withLock {
                    current(); requireProtocol(replica == null, "ALREADY_PAIRED")
                    val trust = SpaceAuthorization.restore(authorization)
                    requireProtocol(trust.active(identity.descriptor) && partnerPeer?.let(trust::active) == true &&
                        authorization.genesis.body.legacyCheckpoint == checkpoint(store.records().map { it.record.entry }), "INVENTORY_CHANGED")
                    val next = Replica(store, identity, trust)
                    store.transaction {
                        store.local("authorization", Canonical.encode(trust.archive))
                        store.local("binding", Canonical.encode(binding))
                        next.restore(); store.removeLocal("partner-pending")
                    }
                    replica = next; this@TogetherRepository.binding = binding
                    configureClient(); reload()
                }
            }
        }
        val displayName = snapshot().entities[identity.descriptor.userId]?.fields?.text("displayName")
            ?.takeIf { it.isNotBlank() } ?: identity.descriptor.displayName
        created = PartnerPairingClient(origin, identity, displayName.take(80), scope, history,
            com.together.android.BuildConfig.DEBUG, partnerPeer)
        created.foreground(foreground)
        partnerStateJob?.cancel()
        partnerStateJob = scope.launch {
            created.state.collect { value ->
                if (partnerClient === created) _state.update { it.copy(partnerPairing = value) }
            }
        }
        return created
    }

    suspend fun createPartnerInvitation() = withContext(Dispatchers.IO) {
        nativeSession?.let { it.createInvitation(); return@withContext }
        val pairing = lock.withLock {
            requireProtocol(replica == null && partnerPeer == null, "ALREADY_PAIRED")
            partnerClient?.stop(); makePartnerClient().also { partnerClient = it }
        }
        pairing.create()
    }
    suspend fun joinPartnerInvitation(code: String) = withContext(Dispatchers.IO) {
        nativeSession?.let { it.joinInvitation(code); return@withContext }
        val pairing = lock.withLock {
            requireProtocol(replica == null && partnerPeer == null, "ALREADY_PAIRED")
            partnerClient?.stop(); makePartnerClient().also { partnerClient = it }
        }
        pairing.join(code)
    }
    suspend fun confirmPartner(verified: Boolean) = withContext(Dispatchers.IO) {
        requireProtocol(verified, "IDENTITY_CONFIRMATION_REQUIRED")
        nativeSession?.let { it.confirm(verified); return@withContext }
        (partnerClient ?: throw ProtocolException("PAIRING_NOT_READY")).confirm()
    }

    suspend fun stageOffer(bytes: ByteArray, displayName: String, confirmed: Boolean): ByteArray =
        command {
            requireProtocol(confirmed, "IDENTITY_CONFIRMATION_REQUIRED")
            requireProtocol(
                replica == null &&
                    store.records().all { it.record.operation.operation.entityType == "profile" },
                "EXISTING_LOCAL_DATA",
            )
            val offer = Canonical.parse(bytes, 524_288).model<EnrollmentOffer>()
            val trust =
                offer.verify(clock.now().toEpochMilli(), com.together.android.BuildConfig.DEBUG)
            val name = displayName.trim()
            requireProtocol(name.isNotEmpty() && name.length <= 80, "INVALID_DEVICE_NAME")
            val pending = store.local("pending-enrollment")?.let { Canonical.parse(it).jsonObject }
            val request =
                if (pending != null) {
                    requireProtocol(
                        pending.getValue("offer").model<EnrollmentOffer>() == offer,
                        "PENDING_ENROLLMENT_EXISTS",
                    )
                    pending.getValue("request").model<EnrollmentRequest>().also {
                        it.verify(
                            offer,
                            clock.now().toEpochMilli(),
                            com.together.android.BuildConfig.DEBUG,
                        )
                        requireProtocol(
                            identities.load(offer.body.id).descriptor == it.body.device,
                            "IDENTITY_MISMATCH",
                        )
                    }
                } else {
                    val newIdentity =
                        identities.create(
                            offer.body.id,
                            offer.body.ownerId,
                            trust.spaceId,
                            name,
                            trust.archive.genesis.body.sharedTimeZoneIdentifier,
                        )
                    EnrollmentRequest.create(
                        offer,
                        newIdentity,
                        clock.now().toEpochMilli(),
                        com.together.android.BuildConfig.DEBUG,
                    )
                }
            store.local(
                "pending-enrollment",
                Canonical.bytes(
                    buildJsonObject {
                        put("offer", offer.json())
                        put("request", request.json())
                    }
                ),
            )
            _state.update { it.copy(offer = offer, request = request) }
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
                val prior =
                    newStore.local("authorization")?.let {
                        SpaceAuthorization.restore(Canonical.parse(it).model())
                    }
                requireProtocol(prior == null || trust.extends(prior), "STALE_AUTHORIZATION")
                newStore.local("authorization", Canonical.encode(trust.archive))
                newStore.local("binding", Canonical.encode(completion.body.binding))
                newStore.local("enrollment-completion", bytes)
            }
            Replica(newStore, newIdentity, trust).restore()
            val output = marker.startWrite()
            try {
                output.write(Canonical.bytes(buildJsonObject { put("offerId", offer.body.id) }))
                marker.finishWrite(output)
            } catch (e: Exception) {
                marker.failWrite(output)
                throw e
            }
        } finally {
            newDb.close()
        }
        db.close()
        replica = null
        open()
        _state.update { it.copy(offer = null, request = null) }
    }

    suspend fun revoke(deviceId: String) = command {
        val r = replica ?: throw ProtocolException("NOT_PAIRED")
        val trust = r.trust
        val root = trust.root(identity.descriptor.userId) ?: throw ProtocolException("NOT_AN_OWNER")
        requireProtocol(root.deviceId == identity.descriptor.deviceId, "OWNER_ROOT_REQUIRED")
        val device = trust.devices[deviceId] ?: throw ProtocolException("UNKNOWN_DEVICE")
        requireProtocol(
            device.active &&
                deviceId != root.deviceId &&
                device.descriptor.userId == identity.descriptor.userId,
            "INVALID_REVOCATION",
        )
        val events = trust.archive.events.filter { it.body.ownerId == identity.descriptor.userId }
        val head = events.lastOrNull()
        val body =
            AuthorizationBody(
                spaceId = trust.spaceId,
                ownerId = identity.descriptor.userId,
                revision = (head?.body?.revision ?: 0) + 1,
                previousDigest = head?.digest ?: trust.archive.genesis.digest,
                authorizerDeviceId = root.deviceId,
                action = "revoke",
                device = device.descriptor,
                epochId = device.epochId,
                cutoff = r.frontier(deviceId),
            )
        val event = AuthorizationEvent(body, identity.sign(Canonical.encode(body)))
        val state =
            RelayApi(binding!!, identity, com.together.android.BuildConfig.DEBUG).authorize(event)
        val next = state.verify(identity.descriptor, trust)
        r.updateAuthorization(next.archive)
    }

    fun foreground(value: Boolean) {
        nativeSession?.foreground(value)
        partnerClient?.foreground(value)
        foreground = value
        startConnection()
    }

    fun reconnect() {
        nativeSession?.let { it.reconnect(); return }
        scope.launch(Dispatchers.IO) {
            connectionLock.withLock {
                connectionJob?.cancelAndJoin()
                connectionJob = null
            }
            startConnection()
        }
    }

    suspend fun nativeOffline(value: Boolean) {
        val session = nativeSession ?: throw ProtocolException("ISOLATED_NATIVE_QA_REQUIRED")
        session.setOffline(value)
    }

    suspend fun cancelNativeInvitation() {
        (nativeSession ?: throw ProtocolException("ISOLATED_NATIVE_QA_REQUIRED")).cancelInvitation()
    }

    private fun startConnection() {
        scope.launch(Dispatchers.IO) {
            connectionLock.withLock {
                if (!foreground) {
                    connectionJob?.cancelAndJoin()
                    connectionJob = null
                    _state.update { it.copy(connection = "offline") }
                    return@withLock
                }
                if (connectionJob?.isActive == true) return@withLock
                // A cancelled job may still be completing a bounded HTTP request. Join it before
                // another session can observe/mutate the same peer channels or connection state.
                connectionJob?.join()
                val c = client ?: return@withLock
                connectionJob =
                    scope.launch(Dispatchers.IO) {
                        launch {
                            combine(c.state, c.error) { s, e -> s to e }
                                .collect { (s, e) ->
                                    _state.update { old ->
                                        old.copy(
                                            connection = s,
                                            connectionError = e,
                                        )
                                    }
                                }
                        }
                        c.run()
                    }
            }
        }
    }
}
