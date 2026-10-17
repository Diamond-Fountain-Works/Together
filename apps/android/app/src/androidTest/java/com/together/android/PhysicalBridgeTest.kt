package com.together.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.*
import com.together.domain.*
import com.together.protocol.*
import java.io.File
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

/**
 * Real phone + independent native Swift process. Only public signed files and synthetic media pass
 * through the driver; every Android key is generated and retained in its own Keystore slot.
 */
@RunWith(AndroidJUnit4::class)
class PhysicalBridgeTest {
    private val args
        get() = InstrumentationRegistry.getArguments()

    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val at = Instant.parse("2026-10-09T04:00:00Z")

    private fun directory(): File {
        val id = args.getString("physicalBridgeId")
        Assume.assumeTrue("Physical bridge is separately orchestrated", id != null)
        requireProtocol(id!!.matches(Regex("[A-F0-9]{32}")), "INVALID_WORKSPACE")
        return File(context.filesDir, "physical-bridge/$id").also { check(it.isDirectory) }
    }

    private suspend fun waitFor(label: String, condition: () -> Boolean) {
        val start = android.os.SystemClock.elapsedRealtime()
        try {
            withTimeout(90_000) { while (!condition()) delay(100) }
        } finally {
            android.util.Log.i(
                "TogetherPhysicalQa",
                "bridge stage=$label elapsedMs=${android.os.SystemClock.elapsedRealtime()-start}",
            )
        }
    }

    private fun write(
        dir: File,
        name: String,
        value: JsonObject = buildJsonObject { put("status", "PASS") },
    ) {
        val atomic = android.util.AtomicFile(File(dir, name))
        val stream = atomic.startWrite()
        try {
            stream.write(Canonical.bytes(value))
            atomic.finishWrite(stream)
        } catch (e: Exception) {
            atomic.failWrite(stream)
            throw e
        }
    }

    private fun json(dir: File, name: String) =
        Canonical.parse(File(dir, name).readBytes()).jsonObject

    @Test
    fun sameSignerApkUpgradeKeepsExistingIdentityBindingFactsAndMedia() = runBlocking {
        Assume.assumeTrue(
            "APK upgrade inspection is explicitly orchestrated",
            args.getString("inspectUpgrade") == "true",
        )
        val dir = directory()
        val plan = json(dir, "phone-reconnected.json")
        val namespace = plan.getValue("namespace").jsonPrimitive.content
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val repo = TogetherRepository(context, scope, namespace, DateProvider { at })
        try {
            withTimeout(15000) { repo.state.first { it.loaded } }
            assertNull(repo.state.value.error)
            val identity = plan.getValue("descriptor").model<DeviceDescriptor>()
            assertEquals(identity, repo.state.value.descriptor)
            val pointer =
                json(File(context.noBackupFilesDir, "qa-$namespace"), "active-replica.json")
            val slot = pointer.getValue("offerId").jsonPrimitive.content
            val db = TogetherDatabase.open(context, "qa-$namespace-replica-$slot.db")
            try {
                val store = RoomReplicaStore(db)
                val binding = Canonical.parse(store.local("binding")!!).model<C1Binding>()
                assertEquals(identity.deviceId, binding.localDeviceId)
                assertEquals(repo.state.value.authorization!!.spaceId, binding.spaceId)
                val trust =
                    SpaceAuthorization.restore(
                        Canonical.parse(store.local("authorization")!!).model()
                    )
                val reopened =
                    Replica(store, AndroidIdentityStore(context, namespace).load(slot), trust)
                        .also { it.restore() }
                assertEquals(
                    json(dir, "native-checkpoint.json").model<Checkpoint>(),
                    reopened.inventoryCheckpoint(),
                )
                assertTrue(
                    repo.state.value.snapshot.of("mediaAsset").map(Asset::from).all {
                        repo.mediaFiles.verified(it) &&
                            MediaFiles.digest(repo.mediaFiles.original(it)) == it.sha256
                    }
                )
                write(
                    dir,
                    "phone-upgrade.json",
                    buildJsonObject {
                        put("status", "PASS")
                        put("identityRetained", true)
                        put("bindingRetained", true)
                        put("exactFactCheckpointRetained", true)
                        put("originalsRetained", true)
                        put("roomSchema", 1)
                    },
                )
            } finally {
                db.close()
            }
        } finally {
            repo.close()
            scope.cancel()
        }
    }

    @Test
    fun enrolledPhysicalPhoneExchangesBusinessAndPersistsForRestart() = runBlocking {
        val dir = directory()
        val namespace = uid()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val repo = TogetherRepository(context, scope, namespace, DateProvider { at })
        try {
            withTimeout(15000) { repo.state.first { it.loaded } }
            assertNull(repo.state.value.error)
            val offer =
                Canonical.parse(File(dir, "offer.json").readBytes()).model<EnrollmentOffer>()
            val request =
                repo.stageOffer(Canonical.encode(offer), "Synthetic physical Android", true)
            File(dir, "request.json").writeBytes(request)
            val requested = Canonical.parse(request).model<EnrollmentRequest>()
            assertEquals(offer.body.ownerId, requested.body.device.userId)
            assertNotEquals(
                offer.body.archive.genesis.body.roots
                    .first { it.deviceId == offer.body.issuerDeviceId }
                    .publicKey,
                requested.body.device.publicKey,
            )
            waitFor("root completion") { File(dir, "completion.json").isFile }
            repo.completeEnrollment(File(dir, "completion.json").readBytes(), true)
            assertEquals(offer.body.binding.spaceId, repo.state.value.authorization!!.spaceId)
            repo.noteInteraction()
            repo.foreground(true)
            val native = json(dir, "native-created.json")
            val grant = native.getValue("grant").jsonPrimitive.content
            val nativeGift = native.getValue("gift").jsonPrimitive.content
            val legacy = native.getValue("legacyTask").jsonPrimitive.content
            val deleted = native.getValue("deletedTask").jsonPrimitive.content
            waitFor("complete native history") {
                repo.state.value.historyReady &&
                    repo.state.value.snapshot.entities[grant] != null &&
                    repo.state.value.snapshot.gifts[nativeGift] != null
            }
            assertNotNull(repo.state.value.snapshot.entities[legacy])
            assertNotNull(repo.state.value.snapshot.entities[deleted]?.deletedAt)
            repo.execute {
                task(null, "Synthetic physical Android task", "", null, null, null) +
                    listOf(
                        wish(grant, "Synthetic physical Android wish", ""),
                        expense(
                            null,
                            "Synthetic physical AA",
                            Amount.create("9.99"),
                            Payment("equalSplit", context.members.toList()),
                            CivilDate(2026, 10, 9),
                            "food",
                            "",
                            null,
                        ),
                        expense(
                            null,
                            "Synthetic physical shared",
                            Amount.create("12.34"),
                            Payment("reserves", emptyList()),
                            CivilDate(2026, 10, 9),
                            "food",
                            "",
                            null,
                        ),
                    )
            }
            val task =
                repo.state.value.snapshot
                    .of("task")
                    .single { it.fields.text("title") == "Synthetic physical Android task" }
                    .id
            val wish =
                repo.state.value.snapshot.wishes.values
                    .single { it.title == "Synthetic physical Android wish" }
                    .id
            val photoFile =
                File(dir, "synthetic.png")
                    .copyTo(File(context.cacheDir, "synthetic-physical-$namespace.png"))
            val audioFile =
                File(dir, "synthetic.wav")
                    .copyTo(File(context.cacheDir, "synthetic-physical-$namespace.wav"))
            val photo = repo.importOwnedMedia(photoFile, "photo")
            val audio = repo.importOwnedMedia(audioFile, "audio")
            repo.sendGift(
                GiftDraft("Synthetic physical Android sealed gift", audio.assetId, photo.assetId)
            )
            val ownGift =
                repo.state.value.snapshot.gifts.values
                    .single { it.entity.fields.id("senderId") == requested.body.device.userId }
                    .id
            write(
                dir,
                "phone-created.json",
                buildJsonObject {
                    put("device", requested.body.device.json())
                    put("task", task)
                    put("wish", wish)
                    put("gift", ownGift)
                },
            )
            waitFor("wish requested") {
                repo.state.value.snapshot.wishes[wish]?.status == "completionRequested"
            }
            repo.execute { listOf(wishAction(wish, "confirmFulfillment")) }
            waitFor("verified media and partner persistence") {
                val s = repo.state.value
                ownGift in s.giftSynced &&
                    s.snapshot.gifts[nativeGift]?.let {
                        giftAssets(it).all { id ->
                            s.snapshot.entities[id]
                                ?.let(Asset::from)
                                ?.let(repo.mediaFiles::verified) == true
                        }
                    } == true &&
                    s.operationStates.values.any { it == "converged" }
            }
            val stats = FinanceProjection.statistics(repo.state.value.snapshot)
            assertEquals(1967, stats.bookBalance)
            assertEquals(999, stats.personal.values.sum())
            assertEquals(
                1,
                repo.state.value.snapshot.of("expense").count { it.fields.id("billId") != null },
            )
            assertEquals(2, repo.state.value.snapshot.remaining(grant))
            assertTrue(repo.state.value.autoGifts.isEmpty())
            val reviewIds = repo.state.value.snapshot.changes.map { it.operationId }.toSet()
            repo.markReviewed(reviewIds)
            repo.markNotified(reviewIds)
            repo.foreground(false)
            waitFor("foreground disconnect") { repo.state.value.connection == "offline" }
            repo.localWrite(
                task,
                "task",
                "patch",
                mapOf("notes" to LogValue.string("Synthetic Android offline notes")),
            )
            write(dir, "phone-offline.json")
            waitFor("native offline operation") { File(dir, "native-offline-written").exists() }
            // Exercise duplicate connect and cancellation/new-session ownership with actual Room.
            repeat(6) {
                repo.foreground(true)
                repo.reconnect()
                delay(20)
            }
            waitFor("reconnected live sync") {
                val s = repo.state.value
                s.connection == "connected" &&
                    s.snapshot.entities[task]?.fields?.text("title") ==
                        "Synthetic Mac offline title" &&
                    s.snapshot.of("task").any {
                        it.fields.text("title") == "Synthetic Mac catch-up"
                    }
            }
            write(
                dir,
                "phone-reconnected.json",
                buildJsonObject {
                    put("namespace", namespace)
                    put("descriptor", repo.state.value.descriptor!!.json())
                    put("clock", at.toString())
                    put("photoHash", photo.sha256)
                    put("audioHash", audio.sha256)
                    put("task", task)
                    put("reviewed", buildJsonArray { reviewIds.sorted().forEach { add(it) } })
                },
            )
        } finally {
            val s = repo.state.value
            write(
                dir,
                "phone-diagnostic.json",
                buildJsonObject {
                    put("connection", s.connection)
                    put("error", s.error)
                    put("connectionError", s.connectionError)
                    put("ready", s.historyReady)
                },
            )
            repo.close()
            scope.cancel()
        }
    }

    @Test
    fun identityAckAndMediaSurviveActualForceStopThenRevocationRejectsAccess() = runBlocking {
        val dir = directory()
        val plan = json(dir, "phone-reconnected.json")
        val namespace = plan.getValue("namespace").jsonPrimitive.content
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val repo = TogetherRepository(context, scope, namespace, DateProvider { at })
        try {
            withTimeout(15000) { repo.state.first { it.loaded } }
            assertNull(repo.state.value.error)
            assertEquals(
                plan.getValue("descriptor").model<DeviceDescriptor>(),
                repo.state.value.descriptor,
            )
            val expected = json(dir, "native-checkpoint.json").model<Checkpoint>()
            val pointer =
                json(File(context.noBackupFilesDir, "qa-$namespace"), "active-replica.json")
            val slot = pointer.getValue("offerId").jsonPrimitive.content
            val db = TogetherDatabase.open(context, "qa-$namespace-replica-$slot.db")
            val identity = AndroidIdentityStore(context, namespace).load(slot)
            try {
                val store = RoomReplicaStore(db)
                val trust =
                    SpaceAuthorization.restore(
                        Canonical.parse(store.local("authorization")!!).model()
                    )
                val replica = Replica(store, identity, trust).also { it.restore() }
                assertEquals(expected, replica.inventoryCheckpoint())
                val own =
                    store.records().first {
                        it.record.operation.operation.deviceId == identity.descriptor.deviceId
                    }
                assertTrue(replica.persistedDevices(own.record.entry).size >= 2)
                val record = own.record
                replica.receive(listOf(record, record))
                assertEquals(expected, replica.inventoryCheckpoint())
                val assets = repo.state.value.snapshot.of("mediaAsset").map(Asset::from)
                assertTrue(
                    assets.all {
                        repo.mediaFiles.verified(it) &&
                            MediaFiles.digest(repo.mediaFiles.original(it)) == it.sha256
                    }
                )
                assertTrue(
                    repo.state.value.reviewed.containsAll(
                        plan.getValue("reviewed").jsonArray.map { it.jsonPrimitive.content }
                    )
                )
                assertTrue(repo.state.value.notified.containsAll(repo.state.value.reviewed))
                repo.foreground(true)
                waitFor("foreground after force-stop") {
                    repo.state.value.connection == "connected"
                }
                write(dir, "phone-restarted.json")
                waitFor("native revocation") { File(dir, "native-revoked").exists() }
                repo.reconnect()
                var error: String? = null
                try {
                    RelayApi(Canonical.parse(store.local("binding")!!).model(), identity, true)
                        .ticket()
                    fail("Revoked device received a ticket")
                } catch (e: ProtocolException) {
                    error = e.code
                }
                assertNotNull(error)
                waitFor("revoked network access") {
                    repo.state.value.connection != "connected" &&
                        repo.state.value.connectionError != null
                }
                write(
                    dir,
                    "phone-revoked.json",
                    buildJsonObject {
                        put("status", "PASS")
                        put("ticketError", error)
                        put("checkpoint", expected.json())
                        put("identityRetained", true)
                        put("signedAckRestored", true)
                        put("duplicateIdempotent", true)
                        put("originalMediaVerified", true)
                    },
                )
            } finally {
                db.close()
            }
        } finally {
            repo.close()
            scope.cancel()
        }
    }
}
