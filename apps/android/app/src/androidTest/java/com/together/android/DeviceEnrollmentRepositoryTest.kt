package com.together.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.TogetherRepository
import com.together.domain.*
import com.together.protocol.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant

@RunWith(AndroidJUnit4::class)
class DeviceEnrollmentRepositoryTest {
    private val at = Instant.parse("2026-10-09T04:00:00Z")
    private fun offer(): Pair<DeviceIdentity, EnrollmentOffer> {
        val a = DeviceIdentity.create(Crypto.seed(), name = "Synthetic trusted root A", zone = "Asia/Shanghai")
        val b = DeviceIdentity.create(Crypto.seed(), name = "Synthetic trusted root B", zone = "Asia/Shanghai")
        val space = stableId("space:" + listOf(a.descriptor.deviceId, b.descriptor.deviceId).sorted().joinToString(":"))
        val body = GenesisBody(4, space, listOf(a.descriptor.userId, b.descriptor.userId).sorted(), listOf(a.descriptor, b.descriptor).sortedBy { it.deviceId }, listOf(space, a.descriptor.initialSpaceId, b.descriptor.initialSpaceId).sorted(), "Asia/Shanghai", checkpoint(emptyList()))
        val genesis = SignedGenesis(body, listOf(a, b).sortedBy { it.descriptor.deviceId }.map { DeviceSignature(it.descriptor.deviceId, it.sign(Canonical.encode(body))) })
        val archive = AuthorizationArchive(genesis, emptyList())
        val ob = OfferBody(id = uid(), issuerDeviceId = a.descriptor.deviceId, ownerId = a.descriptor.userId, archive = archive,
            binding = C1Binding("https://relay.example.invalid", space, uid(), a.descriptor.deviceId), expiresAt = at.plusSeconds(1800).toEpochMilli())
        return a to EnrollmentOffer(ob, a.sign(Canonical.encode(ob)))
    }
    @Test fun stagedIndependentIdentityAuthorizationAndActiveWorkspaceSurviveReopen() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val namespace = uid(); val job = SupervisorJob(); val scope = CoroutineScope(job + Dispatchers.IO)
        val opened = mutableListOf<TogetherRepository>()
        try {
            val repo = TogetherRepository(context, scope, namespace, DateProvider { at })
            opened.add(repo)
            withTimeout(10000) { repo.state.first { it.loaded } }
            val (root, offer) = offer()
            val before = repo.state.value.descriptor!!
            val bytes = repo.stageOffer(Canonical.encode(offer), "Synthetic enrolled Android", true)
            val request = Canonical.parse(bytes).model<EnrollmentRequest>(); request.verify(offer, at.toEpochMilli())
            assertNotEquals(root.descriptor.publicKey, request.body.device.publicKey)
            assertEquals(root.descriptor.userId, request.body.device.userId)
            assertNotEquals(before.deviceId, request.body.device.deviceId)
            val eventBody = AuthorizationBody(spaceId = offer.body.binding.spaceId, ownerId = root.descriptor.userId, revision = 1,
                previousDigest = offer.body.archive.genesis.digest, authorizerDeviceId = root.descriptor.deviceId, action = "grant", device = request.body.device, epochId = uid())
            val event = AuthorizationEvent(eventBody, root.sign(Canonical.encode(eventBody)))
            val archive = offer.body.archive.copy(events = listOf(event))
            val completeBody = CompletionBody(requestDigest = request.digest, archive = archive, binding = offer.body.binding.copy(localDeviceId = request.body.device.deviceId))
            val completion = EnrollmentCompletion(completeBody, root.sign(Canonical.encode(completeBody)))
            repo.completeEnrollment(Canonical.encode(completion), true)
            assertEquals(offer.body.archive.genesis.body.spaceId, repo.state.value.authorization!!.spaceId)
            repo.saveTask(title = "Synthetic enrolled offline task")
            val expected = repo.state.value.descriptor!!; val taskId = repo.state.value.snapshot.of("task").single().id
            val reopened = TogetherRepository(context, scope, namespace, DateProvider { at })
            opened.add(reopened)
            withTimeout(10000) { reopened.state.first { it.loaded } }
            assertEquals(expected, reopened.state.value.descriptor)
            assertEquals(taskId, reopened.state.value.snapshot.of("task").single().id)
            assertEquals(2, reopened.state.value.authorization!!.members.size)
            assertTrue(reopened.state.value.historyReady)
            assertEquals("offline", reopened.state.value.connection)
        } finally { opened.forEach { it.close() }; job.cancelAndJoin() }
    }
    @Test fun enrollmentCannotOverwriteOfflineBusinessData() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val job = SupervisorJob(); val repo = TogetherRepository(context, CoroutineScope(job + Dispatchers.IO), uid(), DateProvider { at })
        try {
            withTimeout(10000) { repo.state.first { it.loaded } }
            repo.saveTask(title = "Synthetic retained local task")
            val descriptor = repo.state.value.descriptor; val (root, offer) = offer()
            try { repo.stageOffer(Canonical.encode(offer), "Synthetic device", true); fail("Existing task workspace must not be replaced") } catch (e: ProtocolException) { assertEquals("EXISTING_LOCAL_DATA", e.code) }
            assertEquals(descriptor, repo.state.value.descriptor)
            assertEquals("Synthetic retained local task", repo.state.value.snapshot.of("task").single().fields.text("title"))
            assertNotEquals(root.descriptor.userId, descriptor!!.userId)
        } finally { repo.close(); job.cancelAndJoin() }
    }
}
