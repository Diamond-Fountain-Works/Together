package com.together.android

import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.core.app.ActivityOptionsCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.ui.TogetherApp
import com.together.domain.*
import com.together.protocol.*
import java.io.File
import java.time.Instant
import kotlinx.coroutines.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BusinessUiTest {
    @get:Rule val compose = createAndroidComposeRule<com.together.android.qa.BusinessQaActivity>()
    @get:Rule val testName = org.junit.rules.TestName()
    private lateinit var space: BusinessTestSpace
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    @Before
    fun setup() = runBlocking {
        val base = InstrumentationRegistry.getArguments().getString("relayURL")
        Assume.assumeTrue("Local C1 UI NOT RUN without explicit URL", base != null)
        space = BusinessTestSpace(instrumentation.targetContext, base!!)
        space.start()
        if (
            testName.methodName ==
                "stalledProviderDoesNotBlockEditorDismissalOrLocalCommandsAndCancelsCleanly"
        ) {
            // Inject only the system picker result. The real editor callback, provider I/O and
            // dismissal-owned coroutine run unchanged; native SAF itself has separate runtime QA.
            val registry =
                object : ActivityResultRegistry() {
                    override fun <I, O> onLaunch(
                        requestCode: Int,
                        contract: ActivityResultContract<I, O>,
                        input: I,
                        options: ActivityOptionsCompat?,
                    ) {
                        check(
                            contract
                                is
                                androidx.activity.result.contract.ActivityResultContracts.OpenDocument
                        )
                        val uri =
                            android.net.Uri.parse(
                                "content://${instrumentation.context.packageName}.stalled-media/synthetic.png"
                            )
                        dispatchResult(
                            requestCode,
                            android.app.Activity.RESULT_OK,
                            android.content.Intent().setData(uri),
                        )
                    }
                }
            val owner =
                object : ActivityResultRegistryOwner {
                    override val activityResultRegistry = registry
                }
            compose.setContent {
                CompositionLocalProvider(LocalActivityResultRegistryOwner provides owner) {
                    TogetherApp(space.repo)
                }
            }
        } else compose.setContent { TogetherApp(space.repo) }
    }

    @After
    fun close() {
        if (::space.isInitialized) space.close()
    }

    private fun text(id: Int) = instrumentation.targetContext.getString(id)

    private fun navigate(page: String) {
        if (compose.onAllNodesWithTag("navigation.open").fetchSemanticsNodes().isNotEmpty())
            compose.onNodeWithTag("navigation.open").performClick()
        compose.onNodeWithTag("nav.$page").performClick()
    }

    private fun waitFor(condition: () -> Boolean) {
        compose.waitUntil(20000, condition)
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        require(Regex("[a-z0-9-]+").matches(name))
        val prefix =
            InstrumentationRegistry.getArguments().getString("capturePrefix") ?: "phone-light"
        require(Regex("[a-z0-9-]+").matches(prefix))
        fun shell(command: String) {
            val p = instrumentation.uiAutomation.executeShellCommand(command)
            android.os.ParcelFileDescriptor.AutoCloseInputStream(p).use { it.readBytes() }
        }
        shell("mkdir -p /data/local/tmp/together-phase-b-candidates")
        shell("screencap -p /data/local/tmp/together-phase-b-candidates/$prefix-$name.png")
    }

    @Test
    fun stalledProviderDoesNotBlockEditorDismissalOrLocalCommandsAndCancelsCleanly() = runBlocking {
        val resolver = instrumentation.targetContext.contentResolver
        val authority = instrumentation.context.packageName + ".stalled-media"
        val status = android.net.Uri.parse("content://$authority/status")
        val release = android.net.Uri.parse("content://$authority/release")
        compose.onNodeWithTag("app.actions").performClick()
        compose.onNodeWithTag("menu.gift").performClick()
        compose.onNodeWithText(text(R.string.action_add_photo)).performScrollTo().performClick()
        try {
            waitFor {
                resolver.query(status, null, null, null, null)?.use {
                    it.moveToFirst() && it.getInt(0) == 1
                } == true
            }
            withTimeout(3000) {
                space.repo.saveDraft(GiftDraft("Synthetic draft remains editable"))
            }
            compose.onNodeWithTag("media.importing").assertExists()
            compose.onNodeWithTag("sheet.close").performClick()
            compose.waitUntil(3000) {
                compose.onAllNodesWithTag("gift.editor").fetchSemanticsNodes().isEmpty()
            }
            compose.onNodeWithTag("gift.editor").assertDoesNotExist()
            withTimeout(3000) {
                space.repo.execute { task(null, "Synthetic concurrent edit", "", null, null, null) }
            }
            assertTrue(
                space.repo.state.value.snapshot.of("task").any {
                    it.fields.text("title") == "Synthetic concurrent edit"
                }
            )
            waitFor { space.repo.mediaFiles.root.listFiles().orEmpty().isEmpty() }
            assertTrue(space.repo.state.value.staged.isEmpty())
        } finally {
            // Bounded escape even if a platform fails to interrupt a provider read.
            resolver.delete(release, null, null)
        }
    }

    @Test
    fun recordPauseResumePreviewAndAudioOnlyGiftUsesOneQuota() {
        val permission =
            instrumentation.uiAutomation.executeShellCommand(
                "pm grant com.together.android.debug android.permission.RECORD_AUDIO"
            )
        android.os.ParcelFileDescriptor.AutoCloseInputStream(permission).use { it.readBytes() }
        compose.onNodeWithTag("app.actions").performClick()
        compose.onNodeWithTag("menu.gift").performClick()
        compose.onNodeWithText(text(R.string.action_record_audio)).performScrollTo().performClick()
        compose.waitUntil(10000) {
            compose
                .onAllNodesWithText(text(R.string.action_stop_recording))
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
        Thread.sleep(1200)
        compose.onNodeWithText(text(R.string.action_pause)).performClick()
        Thread.sleep(250)
        compose.onNodeWithText(text(R.string.action_resume)).performClick()
        Thread.sleep(800)
        compose.onNodeWithText(text(R.string.action_stop_recording)).performClick()
        waitFor { space.repo.state.value.draft.audioAssetId != null }
        compose.onNodeWithTag("audio.play").performScrollTo().assertIsEnabled()
        capture("gift-audio-editor")
        compose.onNodeWithTag("sheet.save").performClick()
        waitFor {
            space.repo.state.value.snapshot.gifts.values.any {
                it.entity.fields.id("senderId") == space.repo.state.value.descriptor?.userId
            }
        }
        val gift =
            space.repo.state.value.snapshot.gifts.values.single {
                it.entity.fields.id("senderId") == space.repo.state.value.descriptor?.userId
            }
        assertNull(gift.entity.fields.id("photoAssetId"))
        assertTrue(gift.entity.fields.text("textContent").isNullOrBlank())
        val audio =
            Asset.from(
                space.repo.state.value.snapshot.entities.getValue(
                    gift.entity.fields.id("audioAssetId")!!
                )
            )
        assertEquals("m4a", audio.fileExtension)
        assertTrue(space.repo.mediaFiles.verified(audio))
        waitFor { gift.id in space.repo.state.value.giftSynced }
        compose.onNodeWithTag("gift.editor").assertDoesNotExist()
    }

    @Test
    fun taskEditorFlexibleLaterEditCompleteReopenAndTombstone() {
        navigate("plans")
        compose.onNodeWithTag("task.new").performClick()
        compose.onNodeWithTag("task.title").performTextInput("Synthetic UI flexible")
        compose.onNodeWithTag("task.recurrence").performScrollTo().performClick()
        compose.onNodeWithText(text(R.string.label_flexible)).performClick()
        capture("task-editor")
        compose.onNodeWithTag("task.save").performClick()
        waitFor { space.repo.state.value.snapshot.of("task").size == 1 }
        val id = space.repo.state.value.snapshot.of("task").single().id
        capture("tasks-pending")
        compose.onNodeWithTag("task.complete.$id").performClick()
        compose.onNodeWithTag("sheet.save").performClick()
        waitFor {
            space.repo.state.value.snapshot.entities[id]?.fields?.text("status") == "completed"
        }
        assertEquals(1, space.repo.state.value.snapshot.of("task").size)
        compose.onNodeWithTag("tasks.completed").performClick()
        capture("tasks-completed")
        compose.onNodeWithText("Synthetic UI flexible").performClick()
        compose.onNodeWithTag("task.title").performTextReplacement("Synthetic UI edited")
        compose.onNodeWithTag("task.save").performClick()
        waitFor {
            space.repo.state.value.snapshot.entities[id]?.fields?.text("title") ==
                "Synthetic UI edited"
        }
        compose.onNodeWithTag("task.complete.$id").performClick()
        compose.onNodeWithTag("tasks.pending").performClick()
        compose.onNodeWithTag("task.delete.$id").performClick()
        waitFor { space.repo.state.value.snapshot.entities[id]?.deletedAt != null }
        compose.onNodeWithTag("tasks.empty").assertIsDisplayed()
    }

    @Test
    fun actualFinanceCRUDCurrencyBillsAndReviewUseOneLedger() {
        capture("home-populated")
        navigate("finances")
        capture("reserves-empty")
        compose.onNodeWithTag("finance.new").performClick()
        compose.onNodeWithTag("amount.original").performTextInput("100.01")
        compose.onNodeWithTag("sheet.save").performClick()
        waitFor { space.repo.state.value.snapshot.of("reserveEntry").size == 1 }
        capture("reserves-populated")
        compose.onNodeWithTag("finance.tab.1").performClick()
        compose.onNodeWithTag("finance.new").performClick()
        compose.onNodeWithTag("finance.title").performTextInput("Synthetic UI AA")
        compose.onNodeWithTag("amount.original").performTextInput("9.99")
        compose.onNodeWithTag("payment.kind").performScrollTo().performClick()
        compose.onNodeWithText(text(R.string.payment_aa)).performClick()
        capture("expense-aa-editor")
        compose.onNodeWithTag("sheet.save").performClick()
        waitFor { space.repo.state.value.snapshot.of("expense").size == 1 }
        assertEquals(
            999,
            FinanceProjection.statistics(space.repo.state.value.snapshot).personal.values.sum(),
        )
        compose.onNodeWithTag("finance.new").performClick()
        compose.onNodeWithTag("currency.open").performClick()
        capture("currency-wheel")
        compose.onNodeWithTag("currency.search").performTextInput("JPY")
        compose.onNodeWithTag("currency.JPY").performClick()
        compose
            .onNodeWithTag("amount.original")
            .assert(
                SemanticsMatcher.expectValue(
                    androidx.compose.ui.semantics.SemanticsProperties.EditableText,
                    androidx.compose.ui.text.AnnotatedString(""),
                )
            )
        compose.onNodeWithTag("finance.title").performTextInput("Synthetic JPY expense")
        compose.onNodeWithTag("amount.original").performTextInput("1000")
        compose.onNodeWithTag("amount.cny").performTextInput("48.26")
        compose.onNodeWithTag("sheet.save").performClick()
        waitFor { space.repo.state.value.snapshot.of("expense").size == 2 }
        compose.onNodeWithTag("finance.tab.2").performClick()
        compose.onNodeWithTag("finance.new").performClick()
        compose.onNodeWithTag("finance.title").performTextInput("Synthetic UI bill")
        compose.onNodeWithTag("amount.original").performTextInput("68")
        compose.onNodeWithTag("day.wheel").performScrollTo()
        compose.onNodeWithTag("day.wheel").performScrollToNode(hasText("31"))
        compose.onNodeWithText("31").performClick()
        capture("bill-editor")
        compose.onNodeWithTag("sheet.save").performClick()
        waitFor { space.repo.state.value.snapshot.of("recurringBill").size == 1 }
        capture("bills-populated")
        runBlocking {
            space.now = Instant.parse("2026-10-31T04:00:00Z")
            space.repo.execute { emptyList() }
        }
        waitFor {
            space.repo.state.value.snapshot.of("expense").any { it.fields.id("billId") != null }
        }
        val billExpense =
            space.repo.state.value.snapshot.of("expense").single { it.fields.id("billId") != null }
        val before = FinanceProjection.statistics(space.repo.state.value.snapshot).bookBalance
        compose.onNodeWithTag("finance.tab.1").performClick()
        compose.onNodeWithTag("finance.record.${billExpense.id}").performScrollTo().performClick()
        compose.onNodeWithTag("expense.confirm").performScrollTo().performClick()
        waitFor {
            space.repo.state.value.snapshot.entities[billExpense.id]?.fields?.text("status") ==
                "reconciled"
        }
        assertEquals(
            before,
            FinanceProjection.statistics(space.repo.state.value.snapshot).bookBalance,
        )
        compose.onNodeWithTag("finance.settings").performClick()
        capture("cycle-settings")
        compose.onNodeWithTag("sheet.close").performClick()
        navigate("plans")
        compose.onNodeWithTag("tasks.upcoming").performClick()
        compose.onNodeWithTag("task.new").assertDoesNotExist()
        compose.onNodeWithTag("tasks.completed").performClick()
        compose.onNodeWithTag("task.new").assertDoesNotExist()
        navigate("settings")
        capture("settings")
        navigate("connection")
        capture("connection")
    }

    @Test
    fun wishesBeneficiaryConfirmsAndHistoryDoesNotRequireFinancialApproval() {
        val grant = runBlocking { space.grantToMe() }
        navigate("wishes")
        capture("wishes-populated")
        compose.onNodeWithTag("grant.$grant").performClick()
        compose.onNodeWithTag("wish.new").performClick()
        compose.onNodeWithTag("wish.title").performTextInput("Synthetic UI wish")
        compose.onNodeWithTag("sheet.save").performClick()
        waitFor { space.repo.state.value.snapshot.wishes.size == 1 }
        val wish = space.repo.state.value.snapshot.wishes.values.single()
        space.writeRemote { listOf(wishAction(wish.id, "requestFulfillment")) }
        waitFor { space.repo.state.value.snapshot.wishes[wish.id]?.status == "completionRequested" }
        compose.onNodeWithTag("grant.$grant").performClick()
        capture("wish-fulfillment")
        compose.onNodeWithTag("wish.confirm.${wish.id}").performScrollTo().performClick()
        waitFor { space.repo.state.value.snapshot.wishes[wish.id]?.status == "fulfilled" }
        assertEquals(2, space.repo.state.value.snapshot.remaining(grant))
        compose.onNodeWithTag("sheet.close").performClick()
        compose.onNodeWithTag("app.actions").performClick()
        compose.onNodeWithTag("menu.changes").performClick()
        capture("change-review")
        compose.onNodeWithTag("changes.close").performClick()
    }

    @Test
    fun sealedGiftHasNoPrivateSemanticsUntilOpenAndContentReceiptIsIndependent() {
        space.repo.noteInteraction()
        val id = runBlocking { space.receivedGift() }
        compose.onNodeWithTag("gift.reveal").assertDoesNotExist()
        capture("home-unread-gift")
        compose.onNodeWithTag("app.actions").performClick()
        compose.onNodeWithTag("menu.gifts").performClick()
        compose.onNodeWithTag("gift.history.open.$id").performScrollTo().performClick()
        compose.onNodeWithTag("gift.privateText").assertDoesNotExist()
        compose.onNodeWithText("Synthetic private gift sentinel").assertDoesNotExist()
        capture("gift-sealed")
        compose.onNodeWithTag("gift.open").performClick()
        waitFor { space.repo.state.value.presentations[id]?.openedAt != null }
        compose.onNodeWithTag("gift.privateText").performScrollTo().assertIsDisplayed()
        capture("gift-opened")
        compose.onNodeWithTag("audio.play").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText(text(R.string.action_play)).assertIsDisplayed()
        compose.onNodeWithTag("audio.play").performClick()
        compose.waitUntil(8000) {
            compose
                .onAllNodes(
                    hasText("0:01 / 0:03") or hasText("0:02 / 0:03") or hasText("0:03 / 0:03")
                )
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
        compose.onNodeWithText(text(R.string.action_pause)).performClick()
        compose.onNodeWithText(text(R.string.action_play)).assertIsDisplayed()
        compose.onNodeWithTag("gift.savePhoto").performScrollTo().assertIsDisplayed()
        space.writeRemote {
            listOf(
                record(
                    actor,
                    "profile",
                    mapOf("relationshipLabel" to LogValue.string("future family")),
                    false,
                )
            )
        }
        waitFor {
            space.repo.state.value.snapshot.entities[space.fixture.b.descriptor.userId]
                ?.fields
                ?.text("relationshipLabel") == "future family"
        }
        compose
            .onNodeWithText(text(R.string.gift_title_unknown_text))
            .performScrollTo()
            .assertIsDisplayed()
        compose.onNodeWithTag("gift.received").performClick()
        compose.onNodeWithTag("gift.reveal").assertDoesNotExist()
        runBlocking { space.repo.presentedGift(id, true) }
        val state = space.repo.state.value.presentations[id]!!
        assertTrue(state.hasAutoPresented)
        assertNotNull(state.openedAt)
        val gift = space.repo.state.value.snapshot.gifts.getValue(id)
        val photo =
            Asset.from(
                space.repo.state.value.snapshot.entities.getValue(
                    gift.entity.fields.id("photoAssetId")!!
                )
            )
        val export = File(space.context.cacheDir, "synthetic-export-${space.namespace}.png")
        space.repo.mediaFiles.export(photo, export.outputStream())
        assertEquals(photo.sha256, MediaFiles.digest(export))
    }
}
