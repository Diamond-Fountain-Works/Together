package com.together.android

import android.graphics.Bitmap
import android.os.Debug
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.*
import com.together.domain.*
import com.together.protocol.*
import java.io.File
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

/**
 * Explicit opt-in, real 100,000 certified facts, bounded pages; not an end-to-end 100k UI claim.
 */
@RunWith(AndroidJUnit4::class)
class PhysicalPerformanceTest {
    private val args
        get() = InstrumentationRegistry.getArguments()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun enabled() {
        Assume.assumeTrue(
            "Physical performance is separately orchestrated",
            args.getString("runPerformance") == "true",
        )
    }

    private fun nanos() = SystemClock.elapsedRealtimeNanos()

    private fun milliseconds(start: Long) = (nanos() - start) / 1_000_000.0

    private fun output(name: String, json: JsonObject) {
        // Timings are ordinary diagnostic JSON, not signed wire data. Protocol canonical JSON
        // intentionally rejects fractional numbers; never weaken that protocol rule for telemetry.
        val target = android.util.AtomicFile(File(context.filesDir, "phase-c-$name.json"))
        val stream = target.startWrite()
        try {
            stream.write(json.toString().toByteArray(Charsets.UTF_8))
            target.finishWrite(stream)
        } catch (e: Exception) {
            target.failWrite(stream)
            throw e
        }
    }

    @Test
    fun diagnosticFractionalTimingDoesNotUseSignedWireCanonicalization() {
        enabled()
        output(
            "performance-format",
            buildJsonObject {
                put("elapsedMs", 1.25)
                put("count", 100_000)
            },
        )
        val value =
            Json.parseToJsonElement(
                    File(context.filesDir, "phase-c-performance-format.json").readText()
                )
                .jsonObject
        assertEquals(1.25, value.getValue("elapsedMs").jsonPrimitive.double, 0.0)
        assertEquals(100_000, value.getValue("count").jsonPrimitive.int)
    }

    @Test
    fun threeThousandFinanceFactsProjectExactBalancesAndOneReviewPage() {
        enabled()
        val identity =
            DeviceIdentity.create(
                Crypto.seed(),
                name = "Synthetic finance benchmark",
                zone = "Asia/Shanghai",
            )
        val partner = uid()
        val c =
            DomainContext(
                identity.descriptor.initialSpaceId,
                setOf(identity.descriptor.userId, partner),
                setOf(identity.descriptor.initialSpaceId),
                "Asia/Shanghai",
                identity.descriptor.userId,
            )
        val at = java.time.Instant.parse("2026-10-09T04:00:00Z")
        val commands = BusinessCommands(Snapshot(), c, identity.descriptor.userId, at)
        val facts = mutableListOf<SignedOperation>()
        fun add(m: PlannedMutation) {
            facts.add(
                identity.sign(
                    SyncOperation(
                        uid(),
                        identity.descriptor.deviceId,
                        identity.descriptor.userId,
                        m.entityId,
                        m.entityType,
                        m.operationType,
                        facts.size.toLong() + 1,
                        m.payload,
                        at.toEpochMilli(),
                    )
                )
            )
        }
        repeat(1000) {
            add(
                commands.deposit(
                    null,
                    Amount.create("100.01"),
                    identity.descriptor.userId,
                    CivilDate(2026, 10, 9),
                    "Synthetic benchmark",
                )
            )
        }
        repeat(2000) { i ->
            add(
                commands.expense(
                    null,
                    "Synthetic benchmark expense",
                    Amount.create("9.99"),
                    if (i % 2 == 0) Payment("reserves", emptyList())
                    else Payment("equalSplit", c.members.toList()),
                    CivilDate(2026, 10, 9),
                    "food",
                    "",
                    null,
                )
            )
        }
        var started = nanos()
        val projected = Projector.replay(facts, c)
        val projectionMs = milliseconds(started)
        assertTrue(projected.conflicts.isEmpty())
        started = nanos()
        val stats = FinanceProjection.statistics(projected)
        val statisticsMs = milliseconds(started)
        assertEquals(9_002_000L, stats.bookBalance)
        assertEquals(999_000L, stats.personal.values.sum())
        assertEquals(2000, projected.of("expense").size)
        started = nanos()
        val review = ChangeReview.page(facts, c, projected, "finance", 0)
        val reviewMs = milliseconds(started)
        assertEquals(16, review.size)
        assertTrue(review.all { it.after.isNotEmpty() })
        output(
            "performance-finance",
            buildJsonObject {
                put("status", "PASS")
                put("signedFacts", facts.size)
                put("expenses", 2000)
                put("deposits", 1000)
                put("projectionMs", projectionMs)
                put("statisticsMs", statisticsMs)
                put("reviewPage16Ms", reviewMs)
                put("bookBalanceCNYMinor", stats.bookBalance)
                put("personalCNYMinor", stats.personal.values.sum())
                put("pssKiB", Debug.getPss())
            },
        )
    }

    @Test
    fun oneHundredThousandCertifiedRoomFactsArePagedIndexedAndRestored() {
        enabled()
        val base = args.getString("relayURL") ?: error("Local test service required")
        val count = 100_000
        val name = "qa-performance-${uid()}.db"
        val namespace = "PERF-${uid()}"
        val measurements = linkedMapOf<String, Double>()
        var maxHeap = 0L
        var maxPss = 0L
        fun sample() {
            maxHeap =
                maxOf(
                    maxHeap,
                    Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory(),
                )
            maxPss = maxOf(maxPss, Debug.getPss())
        }
        SyntheticRelaySpace(base) { owner, space ->
                AndroidIdentityStore(context, namespace)
                    .create("STRESS", owner, space, "Synthetic Android", "Asia/Shanghai")
            }
            .use { fixture ->
                var db = TogetherDatabase.open(context, name)
                try {
                    var store = RoomReplicaStore(db)
                    var replica = Replica(store, fixture.phone, fixture.trust).also { it.restore() }
                    store.local("authorization", Canonical.encode(fixture.trust.archive))
                    output(
                        "performance-workspace",
                        buildJsonObject {
                            put("namespace", namespace)
                            put("slot", "STRESS")
                            put("database", name)
                            put("descriptor", fixture.phone.descriptor.json())
                        },
                    )
                    fun phase(label: String) {
                        output(
                            "performance-progress",
                            buildJsonObject {
                                put("phase", label)
                                put("database", name)
                                put(
                                    "timingsMs",
                                    buildJsonObject { measurements.forEach { (k, v) -> put(k, v) } },
                                )
                            },
                        )
                        android.util.Log.i(
                            "TogetherPhysicalQa",
                            "100k phase=$label timingsMs=$measurements",
                        )
                    }
                    var started = nanos()
                    for (first in 0 until count step 32) {
                        val next = replica.nextClock()
                        replica.append(
                            (first until minOf(first + 32, count)).mapIndexed { offset, i ->
                                val create = i < 1000
                                SyncOperation(
                                    uid(),
                                    fixture.phone.descriptor.deviceId,
                                    fixture.phone.descriptor.userId,
                                    stableId("physical-performance-task-${i%1000}"),
                                    "task",
                                    if (create) "create" else "patch",
                                    next + offset,
                                    if (create)
                                        mapOf(
                                            "spaceId" to logId(fixture.trust.spaceId),
                                            "createdBy" to logId(fixture.phone.descriptor.userId),
                                            "title" to
                                                LogValue.string(
                                                    "Synthetic physical performance $i"
                                                ),
                                            "status" to LogValue.string("pending"),
                                        )
                                    else mapOf("notes" to LogValue.string("Synthetic revision $i")),
                                    1791518400000,
                                )
                            }
                        )
                        if (first % 4000 == 0) {
                            sample()
                            android.util.Log.i(
                                "TogetherPhysicalQa",
                                "100k seed=$first elapsedMs=${milliseconds(started)} pssKiB=${Debug.getPss()}",
                            )
                        }
                    }
                    measurements["certifyAndPersist100kMs"] = milliseconds(started)
                    phase("seed complete")
                    sample()
                    assertEquals(count, db.dao().count())
                    started = nanos()
                    val checkpoint = replica.inventoryCheckpoint()
                    measurements["inventory100kMs"] = milliseconds(started)
                    phase("inventory complete")
                    assertEquals(count, checkpoint.count)
                    started = nanos()
                    val id = uid()
                    assertEquals(checkpoint, replica.createSnapshot(id))
                    measurements["pinnedSnapshot100kMs"] = milliseconds(started)
                    phase("snapshot complete")
                    val hasher = InventoryHasher()
                    var cursor: String? = null
                    var seen = 0
                    var pages = 0
                    started = nanos()
                    do {
                        val page = store.snapshot(id, cursor)!!
                        assertTrue(page.size <= 128)
                        page.forEach { hasher.add(it) }
                        seen += page.size
                        pages++
                        cursor = if (page.size == 128) page.last().operationId else null
                    } while (cursor != null)
                    measurements["readPinnedPages100kMs"] = milliseconds(started)
                    phase("pinned pages complete")
                    assertEquals(count, seen)
                    assertEquals(checkpoint, hasher.finish())
                    store.clearSnapshot(id)
                    started = nanos()
                    var after: String? = null
                    var firstId: String? = null
                    var lastId: String? = null
                    do {
                        val page = store.rows(after, 128, true)
                        if (firstId == null) firstId = page.firstOrNull()?.id
                        lastId = page.lastOrNull()?.id ?: lastId
                        after = page.lastOrNull()?.id
                    } while (after != null)
                    measurements["decodeKeysetPages100kMs"] = milliseconds(started)
                    phase("keyset pages complete")
                    sample()
                    started = nanos()
                    repeat(1000) {
                        assertNotNull(store.get(if (it % 2 == 0) firstId!! else lastId!!))
                    }
                    measurements["primaryKey1000QueriesMs"] = milliseconds(started)
                    val plan = mutableListOf<String>()
                    db.openHelper.readableDatabase
                        .query(
                            "EXPLAIN QUERY PLAN SELECT * FROM operations WHERE (? IS NULL OR id > ?) AND (? = 0 OR accepted = 1) ORDER BY id LIMIT ?",
                            arrayOf(firstId, firstId, 1, 128),
                        )
                        .use { c -> while (c.moveToNext()) plan.add(c.getString(3)) }
                    db.close()
                    db = TogetherDatabase.open(context, name)
                    store = RoomReplicaStore(db)
                    started = nanos()
                    replica = Replica(store, fixture.phone, fixture.trust).also { it.restore() }
                    measurements["reopenVerifyAndRestore100kMs"] = milliseconds(started)
                    phase("restart verification complete")
                    assertEquals(checkpoint, replica.inventoryCheckpoint())
                    sample()
                    output(
                        "performance-100k",
                        buildJsonObject {
                            put("status", "PASS")
                            put("count", count)
                            put("database", name)
                            put("roomSchema", 1)
                            put("pages", pages)
                            put(
                                "timingsMs",
                                buildJsonObject { measurements.forEach { (k, v) -> put(k, v) } },
                            )
                            put("peakSampledJavaHeapBytes", maxHeap)
                            put("peakSampledPssKiB", maxPss)
                            put("maximumJavaHeapBytes", Runtime.getRuntime().maxMemory())
                            put("queryPlan", buildJsonArray { plan.forEach { add(it) } })
                            put(
                                "full100kBusinessProjection",
                                "NOT RUN - this measures durable signed storage, paging and restart verification",
                            )
                            put(
                                "full100kNetworkSync",
                                "NOT RUN - separate from bounded actual C1 reliability workload",
                            )
                        },
                    )
                } finally {
                    db.close()
                }
            }
    }

    @Test
    fun largeOriginalPhotoTransfersWithoutResamplingAndKeepsItsHash() = runBlocking {
        enabled()
        val base = args.getString("relayURL") ?: error("Local test service required")
        BusinessTestSpace(context, base).use { space ->
            space.start()
            space.repo.noteInteraction()
            val image = File(context.cacheDir, "synthetic-large-${space.namespace}.png")
            val bitmap = Bitmap.createBitmap(2560, 1920, Bitmap.Config.ARGB_8888)
            val random = java.util.Random(11)
            val row = IntArray(2560)
            repeat(1920) { y ->
                for (x in row.indices) row[x] = random.nextInt() or (0xff shl 24)
                bitmap.setPixels(row, 0, 2560, 0, y, 2560, 1)
            }
            image.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
            assertTrue(image.length() > 10 * 1024 * 1024)
            val started = nanos()
            val asset = space.repo.importOwnedMedia(image, "photo")
            val importMs = milliseconds(started)
            assertEquals(image.length(), space.repo.mediaFiles.original(asset).length())
            val transferStarted = nanos()
            space.repo.sendGift(GiftDraft(photoAssetId = asset.assetId))
            val gift =
                space.repo.state.value.snapshot.gifts.values.single {
                    it.entity.fields.id("senderId") == space.repo.state.value.descriptor!!.userId
                }
            space.waitFor { gift.id in space.repo.state.value.giftSynced }
            val transferred =
                space.remoteSnapshot().entities.getValue(asset.assetId).let(Asset::from)
            assertTrue(space.remoteMedia.verified(transferred))
            assertEquals(asset.sha256, MediaFiles.digest(space.remoteMedia.original(transferred)))
            val dimensions =
                android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            android.graphics.BitmapFactory.decodeFile(
                space.remoteMedia.original(transferred).absolutePath,
                dimensions,
            )
            assertEquals(2560, dimensions.outWidth)
            assertEquals(1920, dimensions.outHeight)
            output(
                "performance-media",
                buildJsonObject {
                    put("status", "PASS")
                    put("bytes", asset.byteCount)
                    put("sha256", asset.sha256)
                    put("width", dimensions.outWidth)
                    put("height", dimensions.outHeight)
                    put("importMs", importMs)
                    put("transferAndReceiptMs", milliseconds(transferStarted))
                    put(
                        "transport",
                        "real Samsung client to independent Kotlin test peer on same phone via USB-reversed Worker",
                    )
                    put("pssKiB", Debug.getPss())
                },
            )
        }
    }
}
