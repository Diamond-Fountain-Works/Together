package com.together.domain

import com.together.protocol.*
import java.io.ByteArrayInputStream
import java.nio.file.Files
import java.util.concurrent.CancellationException
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class MediaTest {
    @Test
    fun completedImportCancellationBeforeDispatcherHandoffDoesNotLeaveVerifiedOrphans() =
        runBlocking {
            val root = Files.createTempDirectory("together-synthetic-import-handoff").toFile()
            try {
                val files = MediaFiles(root) { _, _ -> }
                val lease = MediaImportLease(files)
                val cancelled = Job()
                try {
                    withContext(Dispatchers.IO + cancelled) {
                        files.import(
                            byteArrayOf(1, 2).inputStream(),
                            "synthetic.png",
                            "png",
                            "photo",
                            uid(),
                            uid(),
                            0,
                            onImported = {
                                lease.acquired(it)
                                cancelled.cancel()
                            },
                        )
                    }
                    fail("The completed result must not cross the cancelled handoff")
                } catch (_: CancellationException) {
                    assertTrue(files.verified(lease.asset!!))
                } finally {
                    lease.close()
                }
                assertEquals(0, root.listFiles()!!.size)
                val published = MediaImportLease(files)
                files.import(
                    byteArrayOf(3).inputStream(),
                    "synthetic.png",
                    "png",
                    "photo",
                    uid(),
                    uid(),
                    0,
                    onImported = published::acquired,
                )
                published.commit()
                published.close()
                assertTrue(files.verified(published.asset!!))
            } finally {
                root.deleteRecursively()
            }
        }

    @Test
    fun concurrentLeasesReserveTheirCombinedRemainingBytes() {
        val root = Files.createTempDirectory("together-synthetic-lease-budget").toFile()
        try {
            val me = DeviceIdentity.create(Crypto.seed(), name = "Synthetic receiver", zone = "UTC")
            val peer = DeviceIdentity.create(Crypto.seed(), name = "Synthetic sender", zone = "UTC")
            val s = Snapshot()
            for (user in listOf(me.descriptor.userId, peer.descriptor.userId)) {
                val asset =
                    Asset(
                        uid(),
                        uid(),
                        user,
                        "avatar",
                        "synthetic.png",
                        "png",
                        "a".repeat(64),
                        200,
                        0,
                    )
                val op =
                    SyncOperation(
                        uid(),
                        peer.descriptor.deviceId,
                        user,
                        asset.assetId,
                        "mediaAsset",
                        "create",
                        1,
                        asset.fields(),
                        0,
                    )
                s.entities[asset.assetId] = ProjectedEntity(op, asset.fields())
                val profile =
                    op.copy(
                        entityId = user,
                        entityType = "profile",
                        payload = mapOf("avatarAssetId" to logId(asset.assetId)),
                    )
                s.entities[user] = ProjectedEntity(profile, profile.payload)
            }
            val files =
                MediaFiles(root, availableBytes = { 300 }, reserveBytes = { 50 }) { _, _ -> }
            val progress = mutableListOf<Transfer>()
            val exchange = MediaExchange(files, { s }, me, { true }, { _, _ -> }, progress::add)
            assertEquals(1, exchange.synchronize(peer.descriptor).size)
            assertEquals(1, progress.count { it.error == "MEDIA_STORAGE_FULL" })
            assertTrue(exchange.synchronize(peer.descriptor).isEmpty())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun unreferencedManifestsNeverTriggerDownloadAndReferencedOnesRespectCapacity() {
        val root = Files.createTempDirectory("together-synthetic-budget").toFile()
        try {
            val me = DeviceIdentity.create(Crypto.seed(), name = "Synthetic receiver", zone = "UTC")
            val peer = DeviceIdentity.create(Crypto.seed(), name = "Synthetic sender", zone = "UTC")
            val asset =
                Asset(
                    uid(),
                    uid(),
                    peer.descriptor.userId,
                    "photo",
                    "synthetic.png",
                    "png",
                    "a".repeat(64),
                    1000000000000L,
                    0,
                )
            val operation =
                SyncOperation(
                    uid(),
                    peer.descriptor.deviceId,
                    peer.descriptor.userId,
                    asset.assetId,
                    "mediaAsset",
                    "create",
                    1,
                    asset.fields(),
                    0,
                )
            val s =
                Snapshot(
                    entities =
                        linkedMapOf(asset.assetId to ProjectedEntity(operation, asset.fields()))
                )
            var available = 256L * 1024
            val files =
                MediaFiles(root, availableBytes = { available }, reserveBytes = { 65536 }) { _, _ ->
                }
            val progress = mutableListOf<Transfer>()
            val exchange =
                MediaExchange(
                    files,
                    { s },
                    me,
                    { it == peer.descriptor },
                    { _, _ -> },
                    progress::add,
                )
            assertTrue(exchange.synchronize(peer.descriptor).isEmpty())
            assertEquals(0, root.listFiles()!!.size)
            val profile =
                operation.copy(
                    entityId = peer.descriptor.userId,
                    entityType = "profile",
                    payload = mapOf("avatarAssetId" to logId(asset.assetId)),
                )
            s.entities[profile.entityId] = ProjectedEntity(profile, profile.payload)
            assertTrue(exchange.synchronize(peer.descriptor).isEmpty())
            assertEquals("MEDIA_STORAGE_FULL", progress.last().error)
            assertEquals(0L, files.offset(asset))
            // Capacity is dynamic. A large original is permitted when the filesystem can hold it.
            available = asset.byteCount + 65536
            exchange.retry()
            assertEquals(1, exchange.synchronize(peer.descriptor).size)
            // Removing the live reference invalidates a previously leased chunk.
            s.entities.remove(profile.entityId)
            assertThrows(ProtocolException::class.java) {
                exchange.receive(
                    peer.descriptor,
                    buildJsonObject {
                        put(
                            "mediaChunk",
                            buildJsonObject {
                                put("_0", asset.assetId)
                                put("_1", 0)
                                put("_2", ByteArray(4).b64())
                            },
                        )
                    },
                )
            }
            assertEquals(0L, files.offset(asset))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun filesystemReserveSurvivesSpaceLossAndResumeDoesNotDuplicateBytes() {
        val root = Files.createTempDirectory("together-synthetic-space-loss").toFile()
        try {
            var available = 65536L + 64
            val files =
                MediaFiles(root, availableBytes = { available }, reserveBytes = { 64 }) { _, _ -> }
            val bytes = ByteArray(65536 * 2) { (it % 251).toByte() }
            val asset =
                Asset(
                    uid(),
                    uid(),
                    uid(),
                    "photo",
                    "synthetic.png",
                    "png",
                    sha256(bytes),
                    bytes.size.toLong(),
                    0,
                )
            assertEquals(65536L, files.append(asset, 0, bytes.copyOfRange(0, 65536)))
            available = 64
            val error =
                assertThrows(ProtocolException::class.java) {
                    files.append(asset, 65536, bytes.copyOfRange(65536, bytes.size))
                }
            assertEquals("MEDIA_STORAGE_FULL", error.code)
            assertEquals(65536L, files.offset(asset))
            assertFalse(files.verified(asset))
            available = 65536L + 64
            files.append(asset, 65536, bytes.copyOfRange(65536, bytes.size))
            files.finish(asset)
            assertTrue(files.verified(asset))
            assertArrayEquals(bytes, files.original(asset).readBytes())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun cancelledOrOutOfSpaceImportClosesInputAndDiscardsOnlyItsPartialDirectory() {
        val root = Files.createTempDirectory("together-synthetic-import-cancel").toFile()
        try {
            val files =
                MediaFiles(root, availableBytes = { 65536 }, reserveBytes = { 65536 }) { _, _ -> }
            assertThrows(ProtocolException::class.java) {
                files.import(
                    byteArrayOf(1).inputStream(),
                    "synthetic.png",
                    "png",
                    "photo",
                    uid(),
                    uid(),
                    0,
                )
            }
            assertEquals(0, root.listFiles()!!.size)
            var closed = false
            val input =
                object : ByteArrayInputStream(ByteArray(65537)) {
                    override fun close() {
                        closed = true
                        super.close()
                    }
                }
            var checks = 0
            val spacious =
                MediaFiles(root, availableBytes = { Long.MAX_VALUE }, reserveBytes = { 0 }) { _, _
                    ->
                }
            assertThrows(CancellationException::class.java) {
                spacious.import(input, "synthetic.png", "png", "photo", uid(), uid(), 0) {
                    if (++checks == 3) throw CancellationException("Synthetic cancellation")
                }
            }
            assertTrue(closed)
            assertEquals(0, root.listFiles()!!.size)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun chunkResumeHashAndExportAreIndependentFromLogAck() {
        val root = Files.createTempDirectory("together-synthetic-media").toFile()
        try {
            val bytes = ByteArray(65536 * 3 + 29) { (it % 251).toByte() }
            val source = MediaFiles(root.resolve("sender")) { _, _ -> }
            val target = MediaFiles(root.resolve("receiver")) { _, _ -> }
            val asset =
                source.import(
                    bytes.inputStream(),
                    "synthetic.png",
                    "png",
                    "photo",
                    uid(),
                    uid(),
                    1791532800000,
                )
            assertEquals(bytes.size.toLong(), asset.byteCount)
            assertTrue(source.verified(asset))
            assertFalse(target.verified(asset))
            assertEquals(65536, source.read(asset, 0).size)
            assertEquals(65536, target.append(asset, 0, source.read(asset, 0)))
            val reopened = MediaFiles(root.resolve("receiver")) { _, _ -> }
            assertEquals(65536, reopened.offset(asset))
            assertEquals(65536, reopened.append(asset, 0, source.read(asset, 0)))
            var offset = reopened.offset(asset)
            while (offset < asset.byteCount) offset =
                reopened.append(asset, offset, source.read(asset, offset))
            assertFalse(reopened.verified(asset))
            reopened.finish(asset)
            assertTrue(reopened.verified(asset))
            val out = root.resolve("export.png")
            reopened.export(asset, out.outputStream())
            assertEquals(asset.sha256, MediaFiles.digest(out))
            assertArrayEquals(bytes, out.readBytes())
            assertThrows(ProtocolException::class.java) {
                reopened.append(asset, 0, ByteArray(65537))
            }
            assertThrows(ProtocolException::class.java) { source.read(asset, -1) }
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun damagedDownloadIsDiscardedWithoutCommittingOriginal() {
        val root = Files.createTempDirectory("together-synthetic-corrupt").toFile()
        try {
            val files = MediaFiles(root) { _, _ -> }
            val a =
                Asset(
                    uid(),
                    uid(),
                    uid(),
                    "photo",
                    "synthetic.png",
                    "png",
                    sha256(byteArrayOf(1, 2)),
                    2,
                    0,
                )
            files.append(a, 0, byteArrayOf(9, 9))
            assertThrows(ProtocolException::class.java) { files.finish(a) }
            assertFalse(files.verified(a))
            assertEquals(0, files.offset(a))
            assertFalse(files.original(a).exists())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun unsafePathsAndInvalidReceiptHashesAreRejected() {
        val root = Files.createTempDirectory("together-synthetic-path").toFile()
        try {
            val files = MediaFiles(root) { _, _ -> }
            assertThrows(ProtocolException::class.java) {
                files.original(
                    Asset("../../outside", uid(), uid(), "photo", "x", "png", "a".repeat(64), 1, 0)
                )
            }
            assertThrows(ProtocolException::class.java) {
                normalizedReceipt(
                    buildJsonObject {
                        put("giftId", uid())
                        put("creationOperationId", uid())
                        put("recipientId", uid())
                        put(
                            "assetHashes",
                            JsonArray(listOf(JsonPrimitive(uid()), JsonPrimitive("bad"))),
                        )
                    }
                )
            }
        } finally {
            root.deleteRecursively()
        }
    }
}
