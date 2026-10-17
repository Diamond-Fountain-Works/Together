package com.together.domain

import com.together.protocol.*
import java.awt.image.BufferedImage
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import javax.imageio.ImageIO
import javax.sound.sampled.AudioSystem
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Actual unchanged Swift C1 peers plus the Kotlin client over a loopback Worker. */
class NativeBridgeIntegrationTest {
    @Test
    fun swiftAndKotlinConvergeBusinessAndVerifiedOriginalsOverActualC1() = runBlocking {
        assumeTrue(
            "Native Swift interoperability NOT RUN without explicit macOS opt-in",
            System.getenv("TOGETHER_RUN_SWIFT_ANDROID") == "1",
        )
        val base =
            System.getenv("TOGETHER_LOCAL_RELAY_URL")
                ?: throw AssertionError("Local Worker required")
        val root = File(System.getProperty("together.fixtures")).parentFile.parentFile
        val dir = Files.createTempDirectory("together-b-swift-").toFile()
        dir.setReadable(false, false)
        dir.setReadable(true, true)
        dir.setWritable(false, false)
        dir.setWritable(true, true)
        dir.setExecutable(false, false)
        dir.setExecutable(true, true)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        var process: Process? = null
        var connection: Job? = null
        try {
            SyntheticRelaySpace(base).use { f ->
                val image = BufferedImage(256, 256, BufferedImage.TYPE_INT_RGB)
                val random = java.util.Random(7)
                for (y in 0..255) for (x in 0..255) image.setRGB(x, y, random.nextInt())
                ImageIO.write(image, "png", dir.resolve("synthetic.png"))
                assertTrue(dir.resolve("synthetic.png").length() > 65536)
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
                dir.resolve("synthetic.wav").writeBytes(wav.array())
                dir.resolve("launch.json")
                    .writeBytes(
                        Canonical.bytes(
                            buildJsonObject {
                                put("ownerA", f.a.descriptor.userId)
                                put("ownerB", f.b.descriptor.userId)
                                put("space", f.trust.spaceId)
                                put("base", base)
                                put("route", f.binding.legacyRouteId)
                            }
                        )
                    )
                val log =
                    File(root, "qa/results/android-phase-b/native-bridge.log").apply {
                        parentFile.mkdirs()
                    }
                process =
                    ProcessBuilder(
                            "/usr/bin/swift",
                            "test",
                            "--package-path",
                            File(root, "packages/together-core-swift").absolutePath,
                            "--filter",
                            "AndroidBusinessBridgeTests",
                        )
                        .directory(root)
                        .redirectErrorStream(true)
                        .redirectOutput(log)
                        .apply {
                            environment()["TOGETHER_RUN_ANDROID_BRIDGE"] = "1"
                            environment()["TOGETHER_ANDROID_BRIDGE_DIR"] = dir.absolutePath
                        }
                        .start()
                suspend fun waitFile(name: String): File {
                    val path = dir.resolve(name)
                    withTimeout(120_000) {
                        while (!path.exists()) {
                            if (process?.isAlive != true)
                                throw AssertionError("Native process exited; see " + log)
                            delay(100)
                        }
                    }
                    return path
                }
                val descriptors =
                    Canonical.parse(waitFile("descriptors.json").readBytes())
                        .jsonObject
                        .getValue("descriptors")
                        .model<List<DeviceDescriptor>>()
                var trust = f.trust
                for ((i, device) in descriptors.withIndex()) {
                    val owner = if (i == 0) f.a else f.b
                    val previous =
                        trust.archive.events
                            .filter { it.body.ownerId == owner.descriptor.userId }
                            .maxByOrNull { it.body.revision }
                    val body =
                        AuthorizationBody(
                            spaceId = trust.spaceId,
                            ownerId = owner.descriptor.userId,
                            revision = (previous?.body?.revision ?: 0) + 1,
                            previousDigest = previous?.digest ?: trust.archive.genesis.digest,
                            authorizerDeviceId = owner.descriptor.deviceId,
                            action = "grant",
                            device = device,
                            epochId = uid(),
                        )
                    val api =
                        RelayApi(
                            f.binding.copy(localDeviceId = owner.descriptor.deviceId),
                            owner,
                            true,
                        )
                    trust =
                        api.authorize(AuthorizationEvent(body, owner.sign(Canonical.encode(body))))
                            .verify(owner.descriptor, trust)
                }
                dir.resolve("authorization.json")
                    .writeBytes(
                        Canonical.bytes(buildJsonObject { put("archive", trust.archive.json()) })
                    )
                val r = Replica(MemoryStore(), f.phone, trust).also { it.restore() }
                val date = Instant.parse("2026-10-09T04:00:00Z")
                fun history(): List<SignedOperation> {
                    val out = mutableListOf<SignedOperation>()
                    var cursor: String? = null
                    do {
                        val page = r.store.rows(cursor, 128, true)
                        out.addAll(page.map { it.record.operation })
                        cursor = page.lastOrNull()?.id
                    } while (cursor != null)
                    return out
                }
                fun snapshot() = Projector.replay(history(), DomainContext.from(r.trust))
                fun write(build: BusinessCommands.() -> List<PlannedMutation>) {
                    r.atomicCommand {
                        val mutations =
                            BusinessCommands(
                                    snapshot(),
                                    DomainContext.from(r.trust),
                                    f.phone.descriptor.userId,
                                    date,
                                )
                                .build()
                        val clock = r.nextClock()
                        r.append(
                            mutations.mapIndexed { i, m ->
                                SyncOperation(
                                    uid(),
                                    f.phone.descriptor.deviceId,
                                    f.phone.descriptor.userId,
                                    m.entityId,
                                    m.entityType,
                                    m.operationType,
                                    clock + i,
                                    m.payload,
                                    date.toEpochMilli(),
                                )
                            }
                        )
                    }
                }
                val media =
                    MediaFiles(dir.resolve("kotlin-media")) { file, type ->
                        if (type == "audio")
                            AudioSystem.getAudioInputStream(file).use {
                                requireProtocol(it.format.sampleRate > 0, "INVALID_AUDIO")
                            }
                        else requireProtocol(ImageIO.read(file) != null, "INVALID_IMAGE")
                    }
                val receipts = ConcurrentHashMap<String, JsonObject>()
                val exchange =
                    MediaExchange(
                        media,
                        ::snapshot,
                        f.phone,
                        { r.trust.active(it) },
                        { _, receipt ->
                            receipts[receipt.getValue("giftId").jsonPrimitive.content] = receipt
                        },
                    )
                val binding = f.binding.copy(localDeviceId = f.phone.descriptor.deviceId)
                val client =
                    C1Client(r, binding, RelayApi(binding, f.phone, true), media = exchange)
                write { task(null, "Synthetic Kotlin task", "", null, null, null) }
                connection = scope.launch { client.run() }
                val created =
                    Canonical.parse(waitFile("native-created.json").readBytes()).jsonObject
                val nativeTask = created.getValue("task").jsonPrimitive.content
                val grant = created.getValue("grant").jsonPrimitive.content
                val gift = created.getValue("gift").jsonPrimitive.content
                withTimeout(90_000) {
                    while (
                        snapshot().entities[nativeTask] == null ||
                            snapshot().entities[grant] == null ||
                            snapshot().gifts[gift] == null
                    ) delay(100)
                }
                write {
                    listOf(
                        wish(grant, "Synthetic Kotlin wish", ""),
                        expense(
                            null,
                            "Synthetic AA",
                            Amount.create("9.99"),
                            Payment("equalSplit", trust.members.toList()),
                            CivilDate(2026, 10, 9),
                            "food",
                            "",
                            null,
                        ),
                        expense(
                            null,
                            "Synthetic shared expense",
                            Amount.create("12.34"),
                            Payment("reserves", emptyList()),
                            CivilDate(2026, 10, 9),
                            "food",
                            "",
                            null,
                        ),
                    )
                }
                client.changed()
                val p =
                    media.import(
                        dir.resolve("synthetic.png").inputStream(),
                        "synthetic.png",
                        "png",
                        "photo",
                        f.phone.descriptor.userId,
                        trust.spaceId,
                        date.toEpochMilli(),
                    )
                val a =
                    media.import(
                        dir.resolve("synthetic.wav").inputStream(),
                        "synthetic.wav",
                        "wav",
                        "audio",
                        f.phone.descriptor.userId,
                        trust.spaceId,
                        date.toEpochMilli(),
                    )
                val ownGift =
                    stableId("gift:${trust.spaceId}:${f.phone.descriptor.userId}:2026-10-09")
                write {
                    listOf(
                        PlannedMutation(p.assetId, "mediaAsset", "create", p.fields()),
                        PlannedMutation(a.assetId, "mediaAsset", "create", a.fields()),
                        PlannedMutation(
                            ownGift,
                            "loveGift",
                            "create",
                            mapOf(
                                "spaceId" to logId(trust.spaceId),
                                "senderId" to logId(f.phone.descriptor.userId),
                                "recipientId" to logId(f.b.descriptor.userId),
                                "textContent" to LogValue.string("Synthetic Kotlin sealed gift"),
                                "audioAssetId" to logId(a.assetId),
                                "photoAssetId" to logId(p.assetId),
                                "sentAt" to LogValue.date(date.toEpochMilli()),
                                "sentDayKey" to LogValue.string("2026-10-09"),
                                "sharedTimeZoneIdentifier" to LogValue.string("Asia/Shanghai"),
                            ),
                        ),
                    )
                }
                client.changed()
                withTimeout(90_000) {
                    while (
                        snapshot().wishes.values.none { it.status == "completionRequested" } ||
                            snapshot().gifts[gift]?.let { g ->
                                giftAssets(g).all { id ->
                                    snapshot()
                                        .entities[id]
                                        ?.let(Asset::from)
                                        ?.let(media::verified) == true
                                }
                            } != true
                    ) delay(100)
                }
                val wish = snapshot().wishes.values.single { it.title == "Synthetic Kotlin wish" }
                write { listOf(wishAction(wish.id, "confirmFulfillment")) }
                client.changed()
                withTimeout(90_000) { while (receipts[ownGift] == null) delay(100) }
                connection!!.cancelAndJoin()
                dir.resolve("offline").writeText("")
                waitFile("native-offline-written")
                write {
                    listOf(
                        record(
                            nativeTask,
                            "task",
                            mapOf("notes" to LogValue.string("Kotlin offline notes")),
                            false,
                        )
                    )
                }
                connection = scope.launch { client.run() }
                val result = Canonical.parse(waitFile("native-result.json").readBytes()).jsonObject
                withTimeout(60_000) {
                    while (
                        snapshot().entities[nativeTask]?.fields?.text("title") !=
                            "Native offline title" ||
                            snapshot().wishes[wish.id]?.status != "fulfilled" ||
                            client.state.value != "connected"
                    ) delay(100)
                }
                assertEquals("PASS", result.getValue("status").jsonPrimitive.content)
                assertEquals(1967, FinanceProjection.statistics(snapshot()).bookBalance)
                assertEquals(999, FinanceProjection.statistics(snapshot()).personal.values.sum())
                assertEquals(1, snapshot().of("expense").count { it.fields.id("billId") != null })
                val received = snapshot().gifts.getValue(gift)
                assertTrue(
                    giftAssets(received).all { id ->
                        val asset = Asset.from(snapshot().entities.getValue(id))
                        media.verified(asset) &&
                            MediaFiles.digest(media.original(asset)) == asset.sha256
                    }
                )
                assertEquals(
                    snapshot().changes.map { it.operationId }.distinct().size,
                    snapshot().changes.size,
                )
                assertTrue(snapshot().conflicts.isEmpty())
                File(root, "qa/results/android-phase-b/native-result.json")
                    .writeBytes(Canonical.bytes(result))
                dir.resolve("stop").writeText("")
                withTimeout(30_000) { while (process!!.isAlive) delay(100) }
                assertEquals(0, process!!.exitValue())
            }
        } catch (e: Exception) {
            throw AssertionError(
                "Native bridge failed; retained diagnostic log qa/results/android-phase-b/native-bridge.log",
                e,
            )
        } finally {
            connection?.cancelAndJoin()
            scope.cancel()
            process?.destroy()
            if (process?.isAlive == true) process?.destroyForcibly()
            dir.deleteRecursively()
        }
    }
}
