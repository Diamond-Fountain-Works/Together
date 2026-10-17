package com.together.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.*
import com.together.domain.*
import com.together.protocol.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BusinessPersistenceTest {
    @Test
    fun interruptedEncryptedMediaResumesAfterRoomAndKeystoreReopen() = runBlocking {
        val base = InstrumentationRegistry.getArguments().getString("relayURL")
        Assume.assumeTrue("Local C1 runtime NOT RUN", base != null)
        BusinessTestSpace(InstrumentationRegistry.getInstrumentation().targetContext, base!!).use {
            space ->
            space.start()
            space.repo.noteInteraction()
            space.holdMediaAfter = 65536
            val giftId = space.receivedGift(false)
            space.waitFor { space.requestedOffsets.any { it == 65536L } }
            val s = space.repo.state.value
            val assets =
                giftAssets(s.snapshot.gifts.getValue(giftId)).map {
                    s.snapshot.entities.getValue(it).let(Asset::from)
                }
            assertTrue(assets.any { space.repo.mediaFiles.offset(it) == 65536L })
            assertTrue(assets.none { space.repo.mediaFiles.verified(it) })
            assertFalse(space.receipts.containsKey(giftId))
            assertFalse(giftId in s.autoGifts)
            val identity = s.descriptor!!
            space.repo.foreground(false)
            space.repo.close()
            delay(300)
            space.holdMediaAfter = null
            space.requestedOffsets.clear()
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            val reopened =
                TogetherRepository(
                    space.context,
                    scope,
                    space.namespace,
                    DateProvider { space.now },
                )
            try {
                withTimeout(15000) { reopened.state.first { it.loaded } }
                assertEquals(identity, reopened.state.value.descriptor)
                assertTrue(assets.any { reopened.mediaFiles.offset(it) == 65536L })
                reopened.foreground(true)
                space.waitFor {
                    assets.all { reopened.mediaFiles.verified(it) } &&
                        space.receipts.containsKey(giftId)
                }
                assertTrue(space.requestedOffsets.any { it == 65536L })
                assets.forEach {
                    assertEquals(it.sha256, MediaFiles.digest(reopened.mediaFiles.original(it)))
                }
                assertEquals(
                    1,
                    reopened.state.value.snapshot.gifts.values.count { it.id == giftId },
                )
                assertEquals("connected", reopened.state.value.connection)
            } finally {
                reopened.close()
                scope.cancel()
            }
        }
    }

    @Test
    fun actualRoomGiftTransactionQuotaOriginalFilesAndReopen() = runBlocking {
        val base = InstrumentationRegistry.getArguments().getString("relayURL")
        Assume.assumeTrue("Local C1 runtime NOT RUN", base != null)
        BusinessTestSpace(InstrumentationRegistry.getInstrumentation().targetContext, base!!).use {
            space ->
            space.start()
            val repo = space.repo
            val (p, a) = space.samples()
            val photo = repo.importOwnedMedia(p, "photo")
            val audio = repo.importOwnedMedia(a, "audio")
            assertEquals(MediaFiles.digest(p), photo.sha256)
            assertEquals(p.length(), repo.mediaFiles.original(photo).length())
            assertTrue(photo.byteCount > 65536)
            val draft = GiftDraft("", audio.assetId, photo.assetId)
            repo.saveDraft(draft)
            repo.sendGift(draft)
            assertEquals(
                1,
                repo.state.value.snapshot.gifts.values.count {
                    it.entity.fields.id("senderId") == repo.state.value.descriptor!!.userId
                },
            )
            var rejected = false
            try {
                repo.sendGift(draft)
            } catch (e: ProtocolException) {
                rejected = true
            }
            assertTrue(rejected)
            val own =
                repo.state.value.snapshot.gifts.values.single {
                    it.entity.fields.id("senderId") == repo.state.value.descriptor!!.userId
                }
            space.waitFor { own.id in repo.state.value.giftSynced }
            val received = space.remoteSnapshot().gifts.getValue(own.id)
            assertTrue(
                giftAssets(received).all { id ->
                    space
                        .remoteSnapshot()
                        .entities[id]
                        ?.let(Asset::from)
                        ?.let(space.remoteMedia::verified) == true
                }
            )
            repo.execute { listOf(delete(own.id)) }
            try {
                repo.sendGift(draft)
                fail("Deleting must not refund quota")
            } catch (_: ProtocolException) {}
            space.now = space.now.plusSeconds(86400)
            repo.sendGift(GiftDraft(photoAssetId = photo.assetId))
            val photoOnly =
                repo.state.value.snapshot.gifts.values.single {
                    it.entity.fields.id("senderId") == repo.state.value.descriptor!!.userId &&
                        it.entity.deletedAt == null
                }
            assertNull(photoOnly.entity.fields.id("audioAssetId"))
            assertTrue(photoOnly.entity.fields.text("textContent").isNullOrBlank())
            space.waitFor { photoOnly.id in repo.state.value.giftSynced }
            val identity = repo.state.value.descriptor!!
            repo.foreground(false)
            repo.close()
            val otherScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            val reopened =
                TogetherRepository(
                    space.context,
                    otherScope,
                    space.namespace,
                    DateProvider { space.now },
                )
            try {
                withTimeout(15000) { reopened.state.first { it.loaded } }
                assertEquals(identity, reopened.state.value.descriptor)
                assertNotNull(reopened.state.value.snapshot.gifts[own.id]?.entity?.deletedAt)
                assertTrue(reopened.mediaFiles.verified(photo))
                assertTrue(reopened.state.value.snapshot.giftUsed(identity.userId, "2026-10-09"))
            } finally {
                reopened.close()
                otherScope.cancel()
            }
        }
    }

    @Test
    fun privateCardsAndDraftsPersistWithoutEnteringSignedLog() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val namespace = uid()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val repo = TogetherRepository(context, scope, namespace)
        try {
            withTimeout(15000) { repo.state.first { it.loaded } }
            val me = repo.state.value.descriptor!!.userId
            val card = buildJsonObject {
                put("id", uid())
                put("ownerId", me)
                put("holderId", me)
                put("bankName", "Synthetic bank")
                put("name", "Synthetic card")
                put("lastFour", "1234")
                put("cardKind", "debit")
                put("currencyCode", "CNY")
                put("isShared", false)
            }
            repo.saveCard(card)
            repo.saveDraft(GiftDraft("Synthetic unsent draft"))
            assertTrue(repo.state.value.snapshot.of("paymentMethod").isEmpty())
            assertEquals(1, repo.state.value.privateCards.size)
            val identity = repo.state.value.descriptor
            repo.close()
            val again = TogetherRepository(context, scope, namespace)
            try {
                withTimeout(15000) { again.state.first { it.loaded } }
                assertEquals(identity, again.state.value.descriptor)
                assertEquals("Synthetic unsent draft", again.state.value.draft.text)
                assertEquals(card, again.state.value.privateCards.single())
                assertTrue(again.state.value.snapshot.changes.isEmpty())
            } finally {
                again.close()
            }
        } finally {
            repo.close()
            scope.cancel()
        }
    }
}
