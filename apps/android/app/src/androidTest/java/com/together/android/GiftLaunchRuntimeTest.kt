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
 * Explicit setup/inspection for native process-restart and SAF QA, never a production fixture
 * loader.
 */
@RunWith(AndroidJUnit4::class)
class GiftLaunchRuntimeTest {
    @Test
    fun inspectNativePhotoDraftAfterPicker() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        Assume.assumeTrue(
            "Native picker QA is explicitly orchestrated",
            args.getString("inspectPhotoDraft") == "true",
        )
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val plan =
            Canonical.parse(File(context.filesDir, "phase-b-launch.json").readBytes()).jsonObject
        val expected =
            args.getString("expectedPhotoHash") ?: error("Expected synthetic photo hash required")
        requireProtocol(expected.matches(Regex("[a-f0-9]{64}")), "INVALID_HASH")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val repo =
            TogetherRepository(
                context,
                scope,
                plan.getValue("namespace").jsonPrimitive.content,
                DateProvider { Instant.parse(plan.getValue("clock").jsonPrimitive.content) },
            )
        try {
            withTimeout(15000) { repo.state.first { it.loaded } }
            val asset = repo.state.value.staged.getValue(repo.state.value.draft.photoAssetId!!)
            assertEquals(expected, asset.sha256)
            assertTrue(repo.mediaFiles.verified(asset))
            assertEquals(expected, MediaFiles.digest(repo.mediaFiles.original(asset)))
            assertEquals(
                plan.getValue("photoBytes").jsonPrimitive.long,
                repo.mediaFiles.original(asset).length(),
            )
            assertEquals(1, repo.state.value.snapshot.gifts.size)
        } finally {
            repo.close()
            scope.cancel()
        }
    }

    @Test
    fun prepareCachedGiftForActualProcessRestart() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        Assume.assumeTrue(
            "Standalone process QA is explicitly orchestrated",
            args.getString("prepareLaunch") == "true",
        )
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val base = args.getString("relayURL") ?: error("Local Relay required")
        BusinessTestSpace(context, base).use { space ->
            space.start()
            space.repo.noteInteraction()
            val id = space.receivedGift()
            val s = space.repo.state.value
            val gift = s.snapshot.gifts.getValue(id)
            val photo =
                Asset.from(s.snapshot.entities.getValue(gift.entity.fields.id("photoAssetId")!!))
            assertNull(s.presentations[id]?.openedAt)
            assertFalse(s.presentations[id]?.hasAutoPresented ?: false)
            val plan = buildJsonObject {
                put("namespace", space.namespace)
                put("giftId", id)
                put("clock", space.now.toString())
                put("photoHash", photo.sha256)
                put("photoFilename", photo.originalFilename)
                put("photoBytes", photo.byteCount)
                put("ready", true)
            }
            File(context.filesDir, "phase-b-launch.json").writeBytes(Canonical.bytes(plan))
        }
    }

    @Test
    fun inspectPersistedPresentationAfterProcessDeath() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        Assume.assumeTrue(
            "Standalone inspection is explicitly orchestrated",
            args.getString("inspectLaunch") == "true",
        )
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val plan =
            Canonical.parse(File(context.filesDir, "phase-b-launch.json").readBytes()).jsonObject
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val repo =
            TogetherRepository(
                context,
                scope,
                plan.getValue("namespace").jsonPrimitive.content,
                DateProvider { Instant.parse(plan.getValue("clock").jsonPrimitive.content) },
            )
        try {
            withTimeout(15000) { repo.state.first { it.loaded } }
            val giftId = plan.getValue("giftId").jsonPrimitive.content
            val presentation = repo.state.value.presentations.getValue(giftId)
            assertTrue(presentation.hasAutoPresented)
            if (args.getString("expectOpened") == "true") assertNotNull(presentation.openedAt)
            else assertNull(presentation.openedAt)
            val gift = repo.state.value.snapshot.gifts.getValue(giftId)
            assertTrue(
                giftAssets(gift).all { id ->
                    val asset = Asset.from(repo.state.value.snapshot.entities.getValue(id))
                    repo.mediaFiles.verified(asset) &&
                        MediaFiles.digest(repo.mediaFiles.original(asset)) == asset.sha256
                }
            )
            File(context.filesDir, "phase-b-launch-result.json")
                .writeBytes(
                    Canonical.bytes(
                        buildJsonObject {
                            put("status", "PASS")
                            put("autoPresented", presentation.hasAutoPresented)
                            put("opened", presentation.openedAt != null)
                            put("mediaReady", true)
                        }
                    )
                )
        } finally {
            repo.close()
            scope.cancel()
        }
    }
}
