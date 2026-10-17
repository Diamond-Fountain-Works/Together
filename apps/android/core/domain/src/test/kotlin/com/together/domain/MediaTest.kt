package com.together.domain

import com.together.protocol.*
import java.nio.file.Files
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class MediaTest {
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
