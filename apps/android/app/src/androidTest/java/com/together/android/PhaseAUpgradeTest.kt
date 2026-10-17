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
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Seed uses Phase A's public APIs only, then the same case verifies after adb install -r. No
 * production package, root key export, real database or destructive migration.
 */
@RunWith(AndroidJUnit4::class)
class PhaseAUpgradeTest {
    @Test
    fun signedFactsKeysAndBindingSurviveActualApkReplacement() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val args = InstrumentationRegistry.getArguments()
        org.junit.Assume.assumeTrue(
            "Actual APK upgrade is a separately orchestrated test",
            args.containsKey("upgradeSeed"),
        )
        val seed = args.getString("upgradeSeed") == "true"
        val folder = File(context.filesDir, "synthetic-upgrade").apply { mkdirs() }
        val report = File(folder, "before.json")
        val old = if (seed) null else Canonical.parse(report.readBytes()).jsonObject
        val namespace = old?.getValue("namespace")?.jsonPrimitive?.content ?: uid()
        val at = Instant.parse("2026-10-09T04:00:00Z")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val repo = TogetherRepository(context, scope, namespace, DateProvider { at })
        try {
            withTimeout(15000) { repo.state.first { it.loaded } }
            assertNull(repo.state.value.error)
            var offerId = old?.getValue("offerId")?.jsonPrimitive?.content
            if (seed) {
                val base = args.getString("relayURL") ?: error("Isolated local Relay required")
                SyntheticRelaySpace(base).use { f ->
                    val offerBody =
                        OfferBody(
                            id = uid(),
                            issuerDeviceId = f.a.descriptor.deviceId,
                            ownerId = f.a.descriptor.userId,
                            archive = f.trust.archive,
                            binding = f.binding,
                            expiresAt = at.plusSeconds(1800).toEpochMilli(),
                        )
                    offerId = offerBody.id
                    val offer = EnrollmentOffer(offerBody, f.a.sign(Canonical.encode(offerBody)))
                    val request =
                        Canonical.parse(
                                repo.stageOffer(
                                    Canonical.encode(offer),
                                    "Synthetic upgrade device",
                                    true,
                                )
                            )
                            .model<EnrollmentRequest>()
                    val previous =
                        f.trust.archive.events.last { it.body.ownerId == f.a.descriptor.userId }
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
                    val archive =
                        RelayApi(f.binding, f.a, true)
                            .authorize(AuthorizationEvent(body, f.a.sign(Canonical.encode(body))))
                            .verify(f.a.descriptor, f.trust)
                            .archive
                    val completion =
                        CompletionBody(
                            requestDigest = request.digest,
                            archive = archive,
                            binding = f.binding.copy(localDeviceId = request.body.device.deviceId),
                        )
                    repo.completeEnrollment(
                        Canonical.encode(
                            EnrollmentCompletion(completion, f.a.sign(Canonical.encode(completion)))
                        ),
                        true,
                    )
                    val me = repo.state.value.descriptor!!.userId
                    val space = repo.state.value.authorization!!.spaceId
                    val identity =
                        mapOf(
                            "spaceId" to LogValue.string(space),
                            "createdBy" to LogValue.string(me),
                        )
                    repo.saveTask(
                        title = "Synthetic Phase A retained task",
                        notes = "Retained notes",
                    )
                    val grant = uid()
                    repo.localWrite(
                        grant,
                        "wishGrant",
                        "create",
                        identity +
                            mapOf(
                                "fulfillerId" to LogValue.string(f.b.descriptor.userId),
                                "beneficiaryId" to LogValue.string(me),
                                "quantity" to LogValue.integer(3),
                                "grantedOn" to LogValue.string("2026-10-09"),
                                "notes" to LogValue.string("Synthetic grant"),
                            ),
                    )
                    repo.localWrite(
                        uid(),
                        "wishItem",
                        "create",
                        mapOf(
                            "grantId" to LogValue.string(grant),
                            "title" to LogValue.string("Synthetic retained wish"),
                            "description" to LogValue.string(""),
                            "createdBy" to LogValue.string(me),
                        ),
                    )
                    val amount = LogValue.data(Canonical.bytes(Amount.create("100.01").json()))
                    val date = LogValue.data(Canonical.bytes(CivilDate(2026, 10, 9).json()))
                    repo.localWrite(
                        uid(),
                        "reserveEntry",
                        "create",
                        identity +
                            mapOf(
                                "kind" to LogValue.data(Canonical.bytes(JsonPrimitive("deposit"))),
                                "amount" to amount,
                                "depositedBy" to LogValue.string(me),
                                "date" to date,
                                "notes" to LogValue.string(""),
                            ),
                    )
                    repo.localWrite(
                        uid(),
                        "expense",
                        "create",
                        identity +
                            mapOf(
                                "title" to LogValue.string("Synthetic retained AA"),
                                "amount" to
                                    LogValue.data(Canonical.bytes(Amount.create("9.99").json())),
                                "payment" to
                                    LogValue.data(
                                        Canonical.bytes(
                                            Payment("equalSplit", listOf(me, f.b.descriptor.userId))
                                                .json()
                                        )
                                    ),
                                "date" to date,
                                "zone" to LogValue.string("Asia/Shanghai"),
                                "status" to LogValue.string("reconciled"),
                            ),
                    )
                    repo.localWrite(
                        stableId("gift:$space:$me:2026-10-09"),
                        "loveGift",
                        "create",
                        mapOf(
                            "spaceId" to LogValue.string(space),
                            "senderId" to LogValue.string(me),
                            "recipientId" to LogValue.string(f.b.descriptor.userId),
                            "textContent" to LogValue.string("Synthetic retained gift"),
                            "sentAt" to LogValue.date(at.toEpochMilli()),
                            "sentDayKey" to LogValue.string("2026-10-09"),
                            "sharedTimeZoneIdentifier" to LogValue.string("Asia/Shanghai"),
                        ),
                    )
                }
            }
            val db = TogetherDatabase.open(context, "qa-$namespace-replica-$offerId.db")
            val store = RoomReplicaStore(db)
            try {
                val facts = store.records().map { it.record.operation.contentDigest }.sorted()
                val descriptor = repo.state.value.descriptor!!.json()
                val binding = sha256(store.local("binding")!!)
                val authorization = sha256(store.local("authorization")!!)
                if (seed) {
                    report.writeBytes(
                        Canonical.bytes(
                            buildJsonObject {
                                put("namespace", namespace)
                                put("offerId", offerId)
                                put("descriptor", descriptor)
                                put("binding", binding)
                                put("authorization", authorization)
                                put("facts", JsonArray(facts.map(::JsonPrimitive)))
                                put(
                                    "version",
                                    context.packageManager
                                        .getPackageInfo(context.packageName, 0)
                                        .versionName,
                                )
                            }
                        )
                    )
                } else {
                    assertEquals("0.2.1-phaseA", old!!.getValue("version").jsonPrimitive.content)
                    assertEquals(
                        "0.2.1-phaseB",
                        context.packageManager.getPackageInfo(context.packageName, 0).versionName,
                    )
                    assertEquals(old.getValue("descriptor"), descriptor)
                    assertEquals(old.getValue("binding").jsonPrimitive.content, binding)
                    assertEquals(old.getValue("authorization").jsonPrimitive.content, authorization)
                    assertEquals(old.getValue("facts").model<List<String>>(), facts)
                    assertEquals(1, repo.state.value.snapshot.of("task").size)
                    assertEquals(1, repo.state.value.snapshot.wishes.size)
                    assertEquals(1, repo.state.value.snapshot.gifts.size)
                    assertEquals(
                        10001,
                        FinanceProjection.statistics(repo.state.value.snapshot).bookBalance,
                    )
                    val identity = repo.state.value.descriptor!!
                    repo.saveTask(title = "Synthetic upgrade signature proof")
                    val added =
                        store
                            .records()
                            .map { it.record.operation }
                            .single { it.contentDigest !in facts }
                    added.verify(identity)
                    val result = buildJsonObject {
                        put("status", "PASS")
                        put("schema", db.openHelper.readableDatabase.version)
                        put("retainedFacts", facts.size)
                        put("keyAndDevicePreserved", true)
                        put("bindingPreserved", true)
                        put("oldSignaturesPreserved", true)
                        put("newSignatureVerifiedWithOldPublicKey", true)
                    }
                    File(folder, "after.json").writeBytes(Canonical.bytes(result))
                }
            } finally {
                db.close()
            }
        } finally {
            repo.close()
            scope.cancel()
        }
    }
}
