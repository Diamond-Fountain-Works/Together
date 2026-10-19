package com.together.android

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.*
import com.together.android.p2p.*
import com.together.domain.DomainContext
import com.together.domain.Projector
import com.together.protocol.*
import computer.iroh.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.selects.onTimeout
import kotlinx.coroutines.selects.select
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Physical, test-only protocol acceptance. ADB exchanges public bootstrap credentials only.
 * Business facts and ACKs must cross the QUIC stream. No Relay, VPN, ADB reverse or app UI launch.
 */
@RunWith(AndroidJUnit4::class)
class P2PPublicNetworkTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val args get() = InstrumentationRegistry.getArguments()
    private val context get() = instrumentation.targetContext

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test fun signedPublicReplication() = runBlocking(Dispatchers.IO) {
        val namespace = args.getString("p2pNamespace") ?: error("P2P_NAMESPACE_REQUIRED")
        requireProtocol(Regex("QA-P2P-[A-Z0-9-]{1,32}").matches(namespace), "P2P_NAMESPACE_INVALID")
        val role = args.getString("p2pRole") ?: "acceptor"
        val mode = args.getString("p2pMode") ?: "directOnly"
        requireProtocol(role in setOf("initiator", "acceptor") && mode in setOf("directOnly", "automatic"), "INVALID_P2P_MODE")
        val timeout = (args.getString("p2pDeadlineSeconds")?.toLongOrNull() ?: 240).also {
            requireProtocol(it in 30..300, "INVALID_QA_DEADLINE")
        }
        val root = File(context.getExternalFilesDir(null), "p2p/$namespace").apply { mkdirs() }
        requireProtocol(!File(root, "result.json").exists(), "QA_NAMESPACE_ALREADY_USED")
        var stage = "start"
        val start = SystemClock.elapsedRealtime()
        fun write(name: String, value: JsonElement) {
            val dest = File(root, name); val temp = File(root, "$name.tmp")
            temp.writeBytes(Canonical.bytes(value)); check(temp.renameTo(dest)) { "QA_CONTROL_COMMIT_FAILED" }
        }
        fun mark(name: String) {
            stage = name
            val info = buildJsonObject {
                put("stage", name); put("elapsedMilliseconds", SystemClock.elapsedRealtime() - start)
            }
            write("stage.json", info)
            File(root, "stages.jsonl").appendText(Canonical.bytes(info).toString(Charsets.UTF_8) + "\n")
            android.util.Log.i("TogetherP2pQa", "$name elapsed=${SystemClock.elapsedRealtime() - start}ms")
        }
        suspend fun read(name: String): JsonElement {
            val f = File(root, name)
            while (!f.exists()) delay(100)
            requireProtocol(f.length() in 1..131_072, "QA_CONTROL_BOUNDS")
            return Canonical.parse(f.readBytes(), 131_072)
        }
        fun networkCheck(): JsonObject {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: error("NO_ACTIVE_NETWORK")
            requireProtocol(!caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI), "PUBLIC_CELLULAR_WITHOUT_VPN_REQUIRED")
            return buildJsonObject {
                put("cellular", true); put("wifi", false); put("vpn", false)
                put("validated", caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
            }
        }
        var endpoint: Endpoint? = null
        var stream: P2PStream? = null
        var db: TogetherDatabase? = null
        try {
            withTimeout(timeout * 1000) {
                write("network.json", networkCheck())
                val identities = AndroidIdentityStore(context, namespace)
                requireProtocol(!identities.exists("ROOT"), "QA_IDENTITY_ALREADY_EXISTS")
                val identity = identities.create("ROOT", uid(), uid(), "Synthetic public Samsung", "Asia/Shanghai")
                write("descriptor.json", identity.descriptor.json()); mark("descriptor-published")
                val body = read("genesis-body.json").model<GenesisBody>()
                requireProtocol(body.version == 4 && body.roots.size == 2 &&
                    body.roots.count { it == identity.descriptor } == 1 &&
                    body.memberIds.toSet() == body.roots.map { it.userId }.toSet() &&
                    body.legacyCheckpoint == checkpoint(emptyList()), "INVALID_SYNTHETIC_GENESIS")
                write("signature.json", DeviceSignature(identity.descriptor.deviceId, identity.sign(Canonical.encode(body))).json())
                val archive = read("authorization.json").model<AuthorizationArchive>()
                requireProtocol(archive.genesis.body == body && archive.events.isEmpty(), "QA_GENESIS_CHANGED")
                val trust = SpaceAuthorization.restore(archive)
                val peer = body.roots.single { it.deviceId != identity.descriptor.deviceId }
                mark("authorization-verified")

                IrohAndroid.installAndroidContext(context)
                // A fresh transport seed, never the device-signing private key. Test-local only.
                val transportSeed = SecretKey.generate().let { key -> try { key.toBytes() } finally { key.close() } }
                try {
                    endpoint = Endpoint.bind(EndpointOptions(
                        preset = if (mode == "automatic") presetN0() else presetMinimal(),
                        bindAddr = args.getString("p2pBindAddress"), secretKey = transportSeed,
                        alpns = listOf(P2PStream.alpn),
                        relayMode = if (mode == "automatic") RelayMode.defaultMode() else RelayMode.disabled()))
                } finally { transportSeed.fill(0) }
                val ep = endpoint!!
                if (mode == "automatic") {
                    val online = withTimeoutOrNull(15_000) { ep.online(); true } ?: false
                    write("relay-readiness.json", buildJsonObject { put("online", online) })
                }
                val address = P2PAddress.from(ep)
                write("address.json", address.json())
                val binding = P2PBinding.issue(identity, address.endpointId, trust)
                write("contact.json", buildJsonObject { put("address", address.json()); put("binding", binding.value) })
                mark("contact-published")
                val remote = read("peer-contact.json").jsonObject
                val remoteAddress = P2PAddress.parse(remote.getValue("address"))
                val remoteBinding = P2PBinding.parse(remote.getValue("binding"))
                requireProtocol(remoteBinding.device == peer, "QA_PEER_DESCRIPTOR_MISMATCH")
                remoteBinding.verify(remoteAddress.endpointId, trust)
                mark("connecting-$role")
                stream = if (role == "initiator") P2PStream.connect(ep, remoteAddress) else P2PStream.accept(ep, remoteAddress)
                val link = stream!!
                val cipher = P2PCipher(identity, remoteBinding, link.connection.remoteId().toString(), trust)
                link.send(cipher.hello)
                while (!cipher.authenticated) cipher.handshake(link.receive())?.let { link.send(it) }
                mark("authenticated")
                write("network-connected.json", networkCheck())

                val dbName = "p2p-$namespace.db"
                db = TogetherDatabase.open(context, dbName)
                val store = RoomReplicaStore(db!!)
                val replica = Replica(store, identity, trust).also { it.restore() }
                store.local("authorization", Canonical.encode(archive))
                val fixedDate = 1_791_540_000_000L
                val taskIds = (0 until 129).map { stableId("Together-Public-P2P:${identity.descriptor.deviceId}:$it") }
                for ((index, task) in taskIds.withIndex()) replica.append(listOf(SyncOperation(
                    uid(), identity.descriptor.deviceId, identity.descriptor.userId, task,
                    "task", "create", replica.nextClock(), mapOf(
                        "title" to LogValue.string("Synthetic public Samsung task $index"),
                        "spaceId" to LogValue.string(trust.spaceId),
                        "createdBy" to LogValue.string(identity.descriptor.userId),
                        "createdAt" to LogValue.date(fixedDate),
                        "status" to LogValue.string("pending")), fixedDate)))
                val session = AntiEntropy(replica, peer)
                suspend fun send(frames: List<ReplicationFrame>) {
                    for (frame in frames) link.send(cipher.seal(Canonical.encode(frame)))
                }
                val incoming = Channel<ByteArray>(8)
                val reader = launch {
                    try { while (isActive) incoming.send(link.receive()) }
                    catch (e: Throwable) { incoming.close(e) }
                }
                var deleted = false; var completed = false
                try {
                    send(session.start()); mark("replicating")
                    while (isActive) {
                        // Select atomically: cancelling a timed receive can discard a just-delivered frame.
                        val packet = select<ByteArray?> {
                            incoming.onReceive { it }
                            onTimeout(100) { null }
                        }
                        if (packet != null) send(session.receive(Canonical.parse(cipher.open(packet)).model()))
                        val checkpoint = replica.inventoryCheckpoint()
                        if (!deleted && checkpoint.count == 258 && session.converged) {
                            replica.append(listOf(SyncOperation(uid(), identity.descriptor.deviceId,
                                identity.descriptor.userId, taskIds.first(), "task", "delete", replica.nextClock(),
                                mapOf("deletedAt" to LogValue.date(fixedDate + 1000)), fixedDate + 1000)))
                            deleted = true; send(session.localChanged()); mark("tombstone-created")
                        }
                        if (!completed && deleted && checkpoint.count == 259 && session.converged &&
                            store.records().all { it.accepted && replica.partnerPersisted(it.record.entry) }) {
                            val identityRetained = identities.load("ROOT").descriptor == identity.descriptor
                            val reopened = TogetherDatabase.open(context, dbName)
                            var reopenedAcknowledgements = false
                            var tombstoneRetained = false
                            val reopenedOkay = try {
                                val reopenedStore = RoomReplicaStore(reopened)
                                val r = Replica(reopenedStore, identities.load("ROOT"), trust).also { it.restore() }
                                reopenedAcknowledgements = reopenedStore.records().all { r.partnerPersisted(it.record.entry) }
                                val projected = Projector.replay(reopenedStore.records().filter { it.accepted }.map { it.record.operation }, DomainContext.from(trust))
                                tombstoneRetained = projected.entities[taskIds.first()]?.deletedAt != null &&
                                    projected.of("task").size == 258 && projected.conflicts.isEmpty()
                                r.inventoryCheckpoint() == checkpoint && reopenedAcknowledgements && tombstoneRetained
                            } finally { reopened.close() }
                            requireProtocol(identityRetained && reopenedOkay, "P2P_PERSISTENCE_LOST")
                            write("network-completed.json", networkCheck())
                            val paths = link.paths()
                            requireProtocol(paths.any { it.jsonObject.getValue("selected").jsonPrimitive.boolean }, "P2P_NO_SELECTED_PATH")
                            if (mode == "directOnly") requireProtocol(paths.all { !it.jsonObject.getValue("relayed").jsonPrimitive.boolean }, "P2P_UNEXPECTED_RELAY")
                            write("result.json", buildJsonObject {
                                put("status", "PASS"); put("checkpoint", checkpoint.json())
                                put("partnerPersisted", true); put("paths", paths)
                                put("identityRetained", identityRetained); put("reopenCheckpointRetained", reopenedOkay)
                                put("reopenedAcknowledgementRetained", reopenedAcknowledgements)
                                put("tombstoneRetained", tombstoneRetained); put("operationCount", checkpoint.count)
                                put("processPid", android.os.Process.myPid())
                                put("elapsedMilliseconds", SystemClock.elapsedRealtime() - start)
                            }); completed = true; mark("complete-awaiting-finish")
                        }
                        if (completed && File(root, "finish").exists()) break
                    }
                    assertTrue("Public signed replication did not finish", completed)
                } finally { reader.cancelAndJoin(); session.close(); incoming.cancel() }
            }
        } catch (e: Throwable) {
            write("result.json", buildJsonObject {
                put("status", "FAIL"); put("stage", stage)
                put("error", "${e.javaClass.simpleName}: ${e.message.orEmpty().take(300)}")
                put("elapsedMilliseconds", SystemClock.elapsedRealtime() - start)
            })
            throw e
        } finally {
            stream?.let { runCatching { it.close() } }
            db?.close()
            withContext(NonCancellable) { withTimeoutOrNull(10_000) { endpoint?.shutdown() } }
            endpoint?.close()
        }
    }

    /** A separate am instrument invocation must reopen the already-complete, same QA namespace. */
    @Test fun reopenPersistedPublicReplica() = runBlocking(Dispatchers.IO) {
        val namespace = args.getString("p2pNamespace") ?: error("P2P_NAMESPACE_REQUIRED")
        requireProtocol(Regex("QA-P2P-[A-Z0-9-]{1,32}").matches(namespace), "P2P_NAMESPACE_INVALID")
        val root = File(context.getExternalFilesDir(null), "p2p/$namespace")
        requireProtocol(root.isDirectory, "QA_PRIOR_RUN_REQUIRED")
        fun write(value: JsonElement) {
            val temp = File(root, "reopen-result.json.tmp")
            temp.writeBytes(Canonical.bytes(value))
            check(temp.renameTo(File(root, "reopen-result.json"))) { "QA_CONTROL_COMMIT_FAILED" }
        }
        var db: TogetherDatabase? = null
        try {
            val priorFile = File(root, "result.json")
            requireProtocol(priorFile.isFile && priorFile.length() in 1..131_072, "QA_COMPLETE_RUN_REQUIRED")
            val prior = Canonical.parse(priorFile.readBytes(), 131_072).jsonObject
            requireProtocol(prior.getValue("status").jsonPrimitive.content == "PASS", "QA_COMPLETE_RUN_REQUIRED")
            val expected = prior.getValue("checkpoint").model<Checkpoint>()
            requireProtocol(expected.count == 259 && prior.getValue("processPid").jsonPrimitive.int != android.os.Process.myPid(), "QA_FRESH_PROCESS_REQUIRED")
            val dbName = "p2p-$namespace.db"
            requireProtocol(context.getDatabasePath(dbName).isFile &&
                File(context.noBackupFilesDir, "qa-$namespace/identity/ROOT.json").isFile, "QA_PRIOR_PERSISTENCE_REQUIRED")
            val identity = AndroidIdentityStore(context, namespace).load("ROOT")
            val expectedDescriptor = Canonical.parse(File(root, "descriptor.json").readBytes(), 16_384).model<DeviceDescriptor>()
            requireProtocol(identity.descriptor == expectedDescriptor, "QA_IDENTITY_CHANGED")
            db = TogetherDatabase.open(context, dbName)
            val store = RoomReplicaStore(db!!)
            val archive = Canonical.parse(store.local("authorization") ?: throw ProtocolException("QA_AUTHORIZATION_MISSING"), 131_072).model<AuthorizationArchive>()
            val trust = SpaceAuthorization.restore(archive)
            val replica = Replica(store, identity, trust).also { it.restore() }
            val actual = replica.inventoryCheckpoint()
            val rows = store.records()
            val acknowledged = rows.size == 259 && rows.all { it.accepted && replica.partnerPersisted(it.record.entry) }
            val projected = Projector.replay(rows.filter { it.accepted }.map { it.record.operation }, DomainContext.from(trust))
            val deletedId = stableId("Together-Public-P2P:${identity.descriptor.deviceId}:0")
            val tombstone = projected.entities[deletedId]?.deletedAt != null && projected.of("task").size == 258 && projected.conflicts.isEmpty()
            requireProtocol(actual == expected && acknowledged && tombstone, "QA_REOPEN_STATE_MISMATCH")
            write(buildJsonObject {
                put("status", "PASS"); put("checkpoint", actual.json()); put("operationCount", actual.count)
                put("identityRetained", true); put("partnerPersisted", acknowledged)
                put("reopenCheckpointRetained", true); put("reopenedAcknowledgementRetained", acknowledged)
                put("tombstoneRetained", tombstone); put("processPid", android.os.Process.myPid())
                put("priorProcessPid", prior.getValue("processPid")); put("networkUsed", false)
            })
        } catch (e: Throwable) {
            write(buildJsonObject {
                put("status", "FAIL"); put("error", "${e.javaClass.simpleName}: ${e.message.orEmpty().take(300)}")
                put("processPid", android.os.Process.myPid())
            })
            throw e
        } finally { db?.close() }
    }
}
