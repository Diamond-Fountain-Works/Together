package com.together.domain

import com.together.protocol.*
import java.io.*
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

@Serializable
data class Asset(
    val assetId: String,
    val spaceId: String,
    val ownerId: String,
    val mediaType: String,
    val originalFilename: String,
    val fileExtension: String,
    val sha256: String,
    val byteCount: Long,
    val createdAt: Long,
) {
    fun fields() =
        mapOf(
            "spaceId" to logId(spaceId),
            "ownerId" to logId(ownerId),
            "mediaType" to LogValue.string(mediaType),
            "originalFilename" to LogValue.string(originalFilename),
            "fileExtension" to LogValue.string(fileExtension),
            "sha256" to LogValue.string(sha256),
            "byteCount" to LogValue.integer(byteCount),
        )

    fun validate() {
        listOf(assetId, spaceId, ownerId).forEach(::uuid)
        requireProtocol(
            validDigest(sha256) &&
                byteCount > 0 &&
                mediaType in setOf("photo", "audio", "avatar") &&
                originalFilename.length <= 255 &&
                fileExtension in MediaFiles.extensions,
            "INVALID_MEDIA",
        )
    }

    companion object {
        fun from(e: ProjectedEntity) =
            e.fields
                .let {
                    Asset(
                        e.id,
                        it.id("spaceId")!!,
                        it.id("ownerId")!!,
                        it.text("mediaType")!!,
                        it.text("originalFilename")!!,
                        it.text("fileExtension")!!,
                        it.text("sha256")!!,
                        it.number("byteCount")!!,
                        e.base.createdAt,
                    )
                }
                .also { it.validate() }
    }
}

@Serializable
data class GiftDraft(
    val text: String = "",
    val audioAssetId: String? = null,
    val photoAssetId: String? = null,
    val replyToGiftId: String? = null,
)

@Serializable
data class GiftPresentation(
    val hasAutoPresented: Boolean = false,
    val autoPresentedAt: Long? = null,
    val openedAt: Long? = null,
)

data class Transfer(
    val assetId: String,
    val done: Long,
    val total: Long,
    val status: String,
    val error: String? = null,
)

/** Original files are streamed; only separate previews may be downsampled by the platform. */
class MediaFiles(
    val root: File,
    private val availableBytes: () -> Long = { root.usableSpace },
    private val reserveBytes: () -> Long = {
        // Preserve room for the database and OS. This is a free-space reserve, never a file limit.
        (root.totalSpace / 100).coerceIn(8L * 1024 * 1024, 128L * 1024 * 1024)
    },
    private val validateFormat: (File, String) -> Unit,
) {
    companion object {
        const val CHUNK = 65_536
        val extensions =
            setOf(
                "jpg",
                "jpeg",
                "png",
                "heic",
                "heif",
                "tif",
                "tiff",
                "gif",
                "bmp",
                "m4a",
                "aac",
                "mp3",
                "wav",
                "aiff",
                "aif",
                "caf",
                "flac",
            )

        fun digest(file: File, checkCancelled: () -> Unit = {}): String {
            val d = MessageDigest.getInstance("SHA-256")
            file.inputStream().buffered(CHUNK).use { stream ->
                val b = ByteArray(CHUNK)
                while (true) {
                    checkCancelled()
                    val n = stream.read(b)
                    if (n < 0) break
                    d.update(b, 0, n)
                }
            }
            return d.digest().joinToString("") { "%02x".format(it) }
        }
    }

    init {
        root.mkdirs()
        requireProtocol(root.isDirectory, "MEDIA_STORAGE_UNAVAILABLE")
    }

    fun requireCapacity(incoming: Long) {
        requireProtocol(
            incoming >= 0 && incoming <= (availableBytes() - reserveBytes()).coerceAtLeast(0),
            "MEDIA_STORAGE_FULL",
        )
    }

    /** Only called for a newly imported, unpublished asset when its staging transaction fails. */
    fun discardImport(asset: Asset) {
        directory(asset).deleteRecursively()
    }

    private fun directory(asset: Asset): File {
        asset.validate()
        return File(root, uuid(asset.assetId)).apply { mkdirs() }
    }

    fun original(asset: Asset) = File(directory(asset), "original.${asset.fileExtension}")

    private fun partial(asset: Asset) = File(directory(asset), "download.part")

    private fun marker(asset: Asset) = File(directory(asset), "verified.json")

    private fun mark(asset: Asset) {
        val f = original(asset)
        val bytes =
            Canonical.bytes(
                buildJsonObject {
                    put("sha256", asset.sha256)
                    put("bytes", asset.byteCount)
                    put("modified", f.lastModified())
                }
            )
        val tmp = File(directory(asset), "verified.tmp")
        FileOutputStream(tmp).use {
            it.write(bytes)
            it.fd.sync()
        }
        Files.move(
            tmp.toPath(),
            marker(asset).toPath(),
            StandardCopyOption.REPLACE_EXISTING,
            StandardCopyOption.ATOMIC_MOVE,
        )
    }

    @Synchronized
    fun verified(asset: Asset): Boolean =
        runCatching {
                val f = original(asset)
                val m = Canonical.parse(marker(asset).readBytes(), 4096).jsonObject
                f.isFile &&
                    f.length() == asset.byteCount &&
                    m.getValue("bytes").jsonPrimitive.long == asset.byteCount &&
                    m.getValue("sha256").jsonPrimitive.content == asset.sha256 &&
                    m.getValue("modified").jsonPrimitive.long == f.lastModified()
            }
            .getOrDefault(false)

    fun import(
        input: InputStream,
        filename: String,
        extension: String,
        type: String,
        owner: String,
        space: String,
        at: Long,
        onImported: (Asset) -> Unit = {},
        checkCancelled: () -> Unit = {},
    ): Asset {
        requireProtocol(
            extension in extensions && type in setOf("photo", "avatar", "audio"),
            "UNSUPPORTED_MEDIA",
        )
        val id = uid()
        val dir = File(root, id).apply { mkdirs() }
        val target = File(dir, "original.$extension")
        try {
            input.use { src ->
                FileOutputStream(target).use { out ->
                    val buffer = ByteArray(CHUNK)
                    while (true) {
                        checkCancelled()
                        val count = src.read(buffer)
                        if (count < 0) break
                        checkCancelled()
                        synchronized(this) {
                            requireCapacity(count.toLong())
                            out.write(buffer, 0, count)
                        }
                    }
                    out.fd.sync()
                }
            }
            checkCancelled()
            requireProtocol(target.length() > 0, "EMPTY_MEDIA")
            validateFormat(target, type)
            checkCancelled()
            val asset =
                Asset(
                    id,
                    space,
                    owner,
                    type,
                    filename.take(255),
                    extension,
                    digest(target, checkCancelled),
                    target.length(),
                    at,
                )
            mark(asset)
            onImported(asset)
            return asset
        } catch (e: Exception) {
            dir.deleteRecursively()
            throw e
        }
    }

    @Synchronized
    fun offset(asset: Asset): Long {
        val f = partial(asset)
        if (!f.exists()) f.createNewFile()
        if (f.length() > asset.byteCount) RandomAccessFile(f, "rw").use { it.setLength(0) }
        return f.length()
    }

    @Synchronized
    fun read(asset: Asset, offset: Long): ByteArray {
        requireProtocol(verified(asset) && offset in 0..asset.byteCount, "UNVERIFIED_MEDIA")
        return RandomAccessFile(original(asset), "r").use { f ->
            f.seek(offset)
            ByteArray(minOf(CHUNK.toLong(), asset.byteCount - offset).toInt()).also {
                f.readFully(it)
            }
        }
    }

    @Synchronized
    fun append(asset: Asset, offset: Long, bytes: ByteArray): Long {
        requireProtocol(
            bytes.isNotEmpty() &&
                bytes.size <= CHUNK &&
                offset >= 0 &&
                offset <= asset.byteCount &&
                bytes.size.toLong() <= asset.byteCount - offset,
            "INVALID_MEDIA_CHUNK",
        )
        val current = offset(asset)
        if (offset < current) {
            requireProtocol(offset + bytes.size <= current, "OVERLAPPING_MEDIA_CHUNK")
            return current
        }
        requireProtocol(offset == current, "MEDIA_OFFSET_MISMATCH")
        requireCapacity(bytes.size.toLong())
        RandomAccessFile(partial(asset), "rw").use {
            it.seek(offset)
            it.write(bytes)
            it.fd.sync()
        }
        return offset + bytes.size
    }

    @Synchronized
    fun finish(asset: Asset) {
        if (verified(asset)) return
        val f = partial(asset)
        requireProtocol(f.length() == asset.byteCount, "INCOMPLETE_MEDIA")
        try {
            requireProtocol(digest(f) == asset.sha256, "MEDIA_HASH_MISMATCH")
            validateFormat(f, asset.mediaType)
        } catch (e: Exception) {
            f.delete()
            throw e
        }
        Files.move(
            f.toPath(),
            original(asset).toPath(),
            StandardCopyOption.REPLACE_EXISTING,
            StandardCopyOption.ATOMIC_MOVE,
        )
        mark(asset)
    }

    fun export(asset: Asset, output: OutputStream) {
        requireProtocol(
            verified(asset) &&
                asset.mediaType == "photo" &&
                digest(original(asset)) == asset.sha256,
            "UNVERIFIED_MEDIA",
        )
        original(asset).inputStream().use { input ->
            output.use {
                input.copyTo(it, CHUNK)
                it.flush()
            }
        }
    }
}

/** Own the result before a cancellable dispatcher handoff can discard it. */
class MediaImportLease(private val files: MediaFiles) : AutoCloseable {
    var asset: Asset? = null
        private set

    private var committed = false

    @Synchronized
    fun acquired(value: Asset) {
        check(asset == null)
        asset = value
    }

    @Synchronized
    fun commit() {
        check(asset != null)
        committed = true
    }

    @Synchronized
    override fun close() {
        if (!committed) asset?.let(files::discardImport)
    }
}

fun giftAssets(gift: Gift) =
    listOfNotNull(gift.entity.fields.id("audioAssetId"), gift.entity.fields.id("photoAssetId"))

private fun referencedAssets(s: Snapshot) =
    s.of("profile").mapNotNull { it.fields.id("avatarAssetId") }.toSet() +
        s.gifts.values.filter { it.effective && it.entity.deletedAt == null }.flatMap(::giftAssets)

fun expectedReceipt(gift: Gift, s: Snapshot): JsonObject {
    val pairs =
        giftAssets(gift).sorted().flatMap { id ->
            listOf(
                JsonPrimitive(id),
                JsonPrimitive(s.entities.getValue(id).fields.text("sha256")!!),
            )
        }
    return buildJsonObject {
        put("giftId", gift.id)
        put("creationOperationId", gift.entity.base.operationId)
        put("recipientId", gift.entity.fields.id("recipientId")!!)
        put("assetHashes", JsonArray(pairs))
    }
}

fun normalizedReceipt(receipt: JsonObject): JsonObject {
    val a = receipt.getValue("assetHashes").jsonArray
    requireProtocol(a.size <= 4 && a.size % 2 == 0, "INVALID_GIFT_RECEIPT")
    val pairs =
        a.chunked(2).map { uuid(it[0].jsonPrimitive.content) to it[1].jsonPrimitive.content }
    requireProtocol(
        pairs.map { it.first }.distinct().size == pairs.size &&
            pairs.all { validDigest(it.second) },
        "INVALID_GIFT_RECEIPT",
    )
    return buildJsonObject {
        put("giftId", uuid(receipt.getValue("giftId").jsonPrimitive.content))
        put(
            "creationOperationId",
            uuid(receipt.getValue("creationOperationId").jsonPrimitive.content),
        )
        put("recipientId", uuid(receipt.getValue("recipientId").jsonPrimitive.content))
        put(
            "assetHashes",
            JsonArray(
                pairs
                    .sortedBy { it.first }
                    .flatMap { listOf(JsonPrimitive(it.first), JsonPrimitive(it.second)) }
            ),
        )
    }
}

/** Stateful per-device media leases. Each peer remains authenticated by the existing C1 session. */
class MediaExchange(
    private val files: MediaFiles,
    private val snapshot: () -> Snapshot,
    private val identity: DeviceIdentity,
    private val active: (DeviceDescriptor) -> Boolean,
    private val persistReceipt: (DeviceDescriptor, JsonObject) -> Unit,
    private val progress: (Transfer) -> Unit = {},
) : MediaChannel {
    private val leases = mutableMapOf<String, String>()
    private val unavailable = mutableMapOf<String, MutableSet<String>>()
    private val receipts = mutableMapOf<String, MutableSet<String>>()

    private fun wire(kind: String, vararg values: JsonElement) = buildJsonObject {
        put(kind, buildJsonObject { values.forEachIndexed { i, v -> put("_$i", v) } })
    }

    @Synchronized
    fun retry() {
        unavailable.clear()
    }

    @Synchronized
    override fun disconnected(deviceId: String) {
        leases.entries.removeAll { it.value == deviceId }
        unavailable.remove(deviceId)
        receipts.remove(deviceId)
    }

    @Synchronized
    override fun synchronize(remote: DeviceDescriptor): List<JsonObject> {
        requireProtocol(active(remote), "UNAUTHORIZED_DEVICE")
        val s = snapshot()
        val result = mutableListOf<JsonObject>()
        val referenced = referencedAssets(s)
        leases.keys.retainAll(referenced)
        for (e in s.of("mediaAsset").filter { it.id in referenced }.sortedBy { it.id }) {
            val a = Asset.from(e)
            if (
                files.verified(a) ||
                    a.assetId in leases ||
                    a.assetId in (unavailable[remote.deviceId] ?: emptySet()) ||
                    leases.size >= 8
            )
                continue
            val offset = files.offset(a)
            val reserved =
                leases.keys.sumOf { id ->
                    val pending = s.entities[id]?.let(Asset::from)
                    if (pending == null) 0L
                    else (pending.byteCount - files.offset(pending)).coerceAtLeast(0)
                }
            try {
                files.requireCapacity(a.byteCount - offset + reserved)
            } catch (error: ProtocolException) {
                unavailable.getOrPut(remote.deviceId) { mutableSetOf() }.add(a.assetId)
                progress(Transfer(a.assetId, offset, a.byteCount, "failed", error.code))
                continue
            }
            leases[a.assetId] = remote.deviceId
            progress(Transfer(a.assetId, offset, a.byteCount, "transferring"))
            result.add(wire("mediaRequest", JsonPrimitive(a.assetId), JsonPrimitive(offset)))
        }
        for (g in
            s.gifts.values.filter {
                it.effective &&
                    it.entity.deletedAt == null &&
                    it.entity.fields.id("recipientId") == identity.descriptor.userId &&
                    it.entity.fields.id("senderId") == remote.userId
            }) {
            if (
                giftAssets(g).all {
                    s.entities[it]?.let(Asset::from)?.let(files::verified) == true
                } && receipts.getOrPut(remote.deviceId) { mutableSetOf() }.add(g.id)
            )
                result.add(wire("giftReceipt", expectedReceipt(g, s)))
        }
        return result
    }

    @Synchronized
    override fun receive(remote: DeviceDescriptor, payload: JsonObject): List<JsonObject> {
        requireProtocol(active(remote) && payload.size == 1, "UNAUTHORIZED_MEDIA")
        val (kind, value) = payload.entries.single()
        val p = value.jsonObject
        if (kind == "giftReceipt") {
            val receipt = normalizedReceipt(p.getValue("_0").jsonObject)
            val s = snapshot()
            val g =
                s.gifts[receipt.getValue("giftId").jsonPrimitive.content]
                    ?: throw ProtocolException("UNKNOWN_GIFT")
            requireProtocol(
                g.effective &&
                    g.entity.fields.id("senderId") == identity.descriptor.userId &&
                    g.entity.fields.id("recipientId") == remote.userId &&
                    remote.userId != identity.descriptor.userId &&
                    receipt == expectedReceipt(g, s),
                "INVALID_GIFT_RECEIPT",
            )
            persistReceipt(remote, receipt)
            return emptyList()
        }
        val id = uuid(p.getValue("_0").jsonPrimitive.content)
        val e = snapshot().entities[id] ?: throw ProtocolException("UNKNOWN_MEDIA")
        requireProtocol(e.base.entityType == "mediaAsset", "UNKNOWN_MEDIA")
        val a = Asset.from(e)
        val result = mutableListOf<JsonObject>()
        try {
            when (kind) {
                "mediaRequest" -> {
                    val offset = p.getValue("_1").jsonPrimitive.long
                    requireProtocol(offset in 0..a.byteCount, "INVALID_MEDIA_OFFSET")
                    if (!files.verified(a))
                        return listOf(
                            wire(
                                "mediaFailure",
                                JsonPrimitive(id),
                                JsonPrimitive("MEDIA_NOT_AVAILABLE"),
                            )
                        )
                    val bytes = files.read(a, offset)
                    result.add(
                        if (bytes.isEmpty())
                            wire("mediaComplete", JsonPrimitive(id), JsonPrimitive(a.sha256))
                        else
                            wire(
                                "mediaChunk",
                                JsonPrimitive(id),
                                JsonPrimitive(offset),
                                JsonPrimitive(bytes.b64()),
                            )
                    )
                }
                "mediaChunk" -> {
                    requireProtocol(
                        leases[id] == remote.deviceId && id in referencedAssets(snapshot()),
                        "UNREQUESTED_MEDIA",
                    )
                    val text = p.getValue("_2").jsonPrimitive.content
                    requireProtocol(text.length <= 87_384, "MEDIA_CHUNK_BOUNDS")
                    val next = files.append(a, p.getValue("_1").jsonPrimitive.long, text.unbase64())
                    progress(Transfer(id, next, a.byteCount, "transferring"))
                    result.add(wire("mediaRequest", JsonPrimitive(id), JsonPrimitive(next)))
                }
                "mediaComplete" -> {
                    requireProtocol(
                        leases[id] == remote.deviceId &&
                            p.getValue("_1").jsonPrimitive.content == a.sha256,
                        "INVALID_MEDIA_COMPLETE",
                    )
                    files.finish(a)
                    leases.remove(id)
                    progress(Transfer(id, a.byteCount, a.byteCount, "verified"))
                    result.add(wire("mediaVerified", JsonPrimitive(id), JsonPrimitive(a.sha256)))
                    result.addAll(synchronize(remote))
                }
                "mediaVerified" -> {
                    requireProtocol(
                        p.getValue("_1").jsonPrimitive.content == a.sha256,
                        "MEDIA_HASH_MISMATCH",
                    )
                    progress(Transfer(id, a.byteCount, a.byteCount, "verified"))
                }
                "mediaFailure" -> {
                    if (leases[id] == remote.deviceId) {
                        leases.remove(id)
                        unavailable.getOrPut(remote.deviceId) { mutableSetOf() }.add(id)
                        progress(
                            Transfer(
                                id,
                                files.offset(a),
                                a.byteCount,
                                "failed",
                                "MEDIA_NOT_AVAILABLE",
                            )
                        )
                        result.addAll(synchronize(remote))
                    }
                }
                else -> throw ProtocolException("UNKNOWN_MEDIA_FRAME")
            }
        } catch (e: Exception) {
            leases.remove(id)
            unavailable.getOrPut(remote.deviceId) { mutableSetOf() }.add(id)
            progress(
                Transfer(
                    id,
                    runCatching { files.offset(a) }.getOrDefault(0),
                    a.byteCount,
                    "failed",
                    (e as? ProtocolException)?.code ?: "MEDIA_IO_ERROR",
                )
            )
            throw e
        }
        return result
    }
}
