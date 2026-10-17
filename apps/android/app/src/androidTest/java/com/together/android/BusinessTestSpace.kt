package com.together.android

import android.content.Context
import android.graphics.Bitmap
import com.together.android.data.*
import com.together.domain.*
import com.together.protocol.*
import java.io.File
import java.nio.*
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.*
import org.junit.Assert.*

/** Synthetic identities, a real local Worker, real Room and independent Keystore slots. */
internal class BusinessTestSpace(val context: Context, val base: String) : AutoCloseable {
    val fixture = SyntheticRelaySpace(base)
    val namespace = uid()
    val job = SupervisorJob()
    val scope = CoroutineScope(job + Dispatchers.IO)
    var now = Instant.parse("2026-10-09T04:00:00Z")
    val repo = TogetherRepository(context, scope, namespace, DateProvider { now })
    lateinit var remote: Replica
    lateinit var remoteClient: C1Client
    var remoteJob: Job? = null
    lateinit var remoteMedia: MediaFiles
    val receipts = java.util.concurrent.ConcurrentHashMap<String, JsonObject>()
    @Volatile var holdMediaAfter: Long? = null
    val requestedOffsets = java.util.concurrent.ConcurrentLinkedQueue<Long>()

    suspend fun start() {
        withTimeout(15000) { repo.state.first { it.loaded } }
        assertNull(repo.state.value.error)
        val f = fixture
        val ob =
            OfferBody(
                id = uid(),
                issuerDeviceId = f.a.descriptor.deviceId,
                ownerId = f.a.descriptor.userId,
                archive = f.trust.archive,
                binding = f.binding,
                expiresAt = now.plusSeconds(1800).toEpochMilli(),
            )
        val offer = EnrollmentOffer(ob, f.a.sign(Canonical.encode(ob)))
        val request =
            Canonical.parse(repo.stageOffer(Canonical.encode(offer), "Synthetic Android QA", true))
                .model<EnrollmentRequest>()
        val previous = f.trust.archive.events.last { it.body.ownerId == f.a.descriptor.userId }
        val body =
            AuthorizationBody(
                spaceId = f.trust.spaceId,
                ownerId = f.a.descriptor.userId,
                revision = previous.body.revision + 1,
                previousDigest = previous.digest,
                authorizerDeviceId = f.a.descriptor.deviceId,
                action = "grant",
                device = request.body.device,
                epochId = uid(),
            )
        val updated =
            RelayApi(f.binding, f.a, true)
                .authorize(AuthorizationEvent(body, f.a.sign(Canonical.encode(body))))
                .verify(f.a.descriptor, f.trust)
        val completion =
            CompletionBody(
                requestDigest = request.digest,
                archive = updated.archive,
                binding = f.binding.copy(localDeviceId = request.body.device.deviceId),
            )
        repo.completeEnrollment(
            Canonical.encode(
                EnrollmentCompletion(completion, f.a.sign(Canonical.encode(completion)))
            ),
            true,
        )
        remote = Replica(MemoryStore(), f.b, updated).also { it.restore() }
        remoteMedia =
            MediaFiles(
                File(context.cacheDir, "synthetic-media-$namespace"),
                validateFormat = AndroidMedia::validate,
            )
        val media =
            MediaExchange(
                remoteMedia,
                ::remoteSnapshot,
                f.b,
                { remote.trust.active(it) },
                { _, receipt ->
                    receipts[receipt.getValue("giftId").jsonPrimitive.content] = receipt
                },
            )
        val gatedMedia =
            object : MediaChannel {
                override fun synchronize(remote: DeviceDescriptor) = media.synchronize(remote)

                override fun disconnected(deviceId: String) = media.disconnected(deviceId)

                override fun receive(
                    remote: DeviceDescriptor,
                    payload: JsonObject,
                ): List<JsonObject> {
                    val request = payload["mediaRequest"]?.jsonObject
                    if (request != null) {
                        val offset = request.getValue("_1").jsonPrimitive.long
                        requestedOffsets.add(offset)
                        if (holdMediaAfter?.let { offset >= it } == true) return emptyList()
                    }
                    return media.receive(remote, payload)
                }
            }
        val binding = f.binding.copy(localDeviceId = f.b.descriptor.deviceId)
        remoteClient = C1Client(remote, binding, RelayApi(binding, f.b, true), media = gatedMedia)
        remoteJob = scope.launch { remoteClient.run() }
        repo.foreground(true)
        repo.saveProfile("Synthetic Me", "boyfriend", null)
        writeRemote {
            listOf(
                record(
                    actor,
                    "profile",
                    mapOf(
                        "deviceId" to logId(f.b.descriptor.deviceId),
                        "displayName" to LogValue.string("Synthetic Partner"),
                        "relationshipLabel" to LogValue.string("girlfriend"),
                    ),
                )
            )
        }
        waitFor {
            repo.state.value.snapshot.entities[f.b.descriptor.userId] != null &&
                repo.state.value.connection == "connected"
        }
    }

    fun remoteSnapshot(): Snapshot {
        val all = mutableListOf<SignedOperation>()
        var cursor: String? = null
        do {
            val page = remote.store.rows(cursor, 128, true)
            all.addAll(page.map { it.record.operation })
            cursor = page.lastOrNull()?.id
        } while (cursor != null)
        return Projector.replay(all, DomainContext.from(remote.trust))
    }

    fun writeRemote(build: BusinessCommands.() -> List<PlannedMutation>) {
        remote.atomicCommand {
            val next = remote.nextClock()
            val mutations =
                BusinessCommands(
                        remoteSnapshot(),
                        DomainContext.from(remote.trust),
                        fixture.b.descriptor.userId,
                        now,
                    )
                    .build()
            remote.append(
                mutations.mapIndexed { i, m ->
                    SyncOperation(
                        uid(),
                        fixture.b.descriptor.deviceId,
                        fixture.b.descriptor.userId,
                        m.entityId,
                        m.entityType,
                        m.operationType,
                        next + i,
                        m.payload,
                        now.toEpochMilli(),
                    )
                }
            )
        }
        remoteClient.changed()
    }

    suspend fun grantToMe(count: Long = 3): String {
        writeRemote {
            listOf(
                grant(
                    fixture.b.descriptor.userId,
                    fixture.a.descriptor.userId,
                    count,
                    CivilDate(2026, 10, 9),
                    "Synthetic grant",
                )
            )
        }
        waitFor { repo.state.value.snapshot.of("wishGrant").isNotEmpty() }
        return repo.state.value.snapshot.of("wishGrant").last().id
    }

    fun samples(): Pair<File, File> {
        val photo = File(context.cacheDir, "synthetic-$namespace.png")
        val bitmap = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
        val random = java.util.Random(7)
        val pixels = IntArray(256 * 256) { random.nextInt() or (0xff shl 24) }
        bitmap.setPixels(pixels, 0, 256, 0, 0, 256, 256)
        photo.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        val samples = 48000
        val wav = ByteBuffer.allocate(44 + samples * 2).order(ByteOrder.LITTLE_ENDIAN)
        wav.put("RIFF".toByteArray())
        wav.putInt(36 + samples * 2)
        wav.put("WAVEfmt ".toByteArray())
        wav.putInt(16)
        wav.putShort(1)
        wav.putShort(1)
        wav.putInt(16000)
        wav.putInt(32000)
        wav.putShort(2)
        wav.putShort(16)
        wav.put("data".toByteArray())
        wav.putInt(samples * 2)
        repeat(samples) {
            wav.putShort((kotlin.math.sin(it.toDouble() / 20) * 1500).toInt().toShort())
        }
        val audio = File(context.cacheDir, "synthetic-$namespace.wav")
        audio.writeBytes(wav.array())
        return photo to audio
    }

    suspend fun receivedGift(waitForMedia: Boolean = true): String {
        val (p, a) = samples()
        val photo =
            remoteMedia.import(
                p.inputStream(),
                p.name,
                "png",
                "photo",
                fixture.b.descriptor.userId,
                remote.trust.spaceId,
                now.toEpochMilli(),
            )
        val audio =
            remoteMedia.import(
                a.inputStream(),
                a.name,
                "wav",
                "audio",
                fixture.b.descriptor.userId,
                remote.trust.spaceId,
                now.toEpochMilli(),
            )
        val id = stableId("gift:${remote.trust.spaceId}:${fixture.b.descriptor.userId}:2026-10-09")
        writeRemote {
            listOf(
                PlannedMutation(photo.assetId, "mediaAsset", "create", photo.fields()),
                PlannedMutation(audio.assetId, "mediaAsset", "create", audio.fields()),
                PlannedMutation(
                    id,
                    "loveGift",
                    "create",
                    mapOf(
                        "spaceId" to logId(context.spaceId),
                        "senderId" to logId(actor),
                        "recipientId" to logId(fixture.a.descriptor.userId),
                        "textContent" to LogValue.string("Synthetic private gift sentinel"),
                        "photoAssetId" to logId(photo.assetId),
                        "audioAssetId" to logId(audio.assetId),
                        "sentAt" to LogValue.date(now.toEpochMilli()),
                        "sentDayKey" to LogValue.string("2026-10-09"),
                        "sharedTimeZoneIdentifier" to LogValue.string("Asia/Shanghai"),
                    ),
                ),
            )
        }
        waitFor { repo.state.value.snapshot.gifts[id] != null }
        if (waitForMedia)
            waitFor {
                repo.state.value.snapshot.gifts[id]?.let { g ->
                    giftAssets(g).all { asset ->
                        repo.state.value.snapshot.entities[asset]
                            ?.let(Asset::from)
                            ?.let(repo.mediaFiles::verified) == true
                    }
                } == true
            }
        return id
    }

    suspend fun waitFor(condition: () -> Boolean) =
        withTimeout(60000) { while (!condition()) delay(100) }

    override fun close() {
        runBlocking {
            repo.close()
            remoteJob?.cancelAndJoin()
        }
        job.cancel()
        fixture.close()
    }
}
