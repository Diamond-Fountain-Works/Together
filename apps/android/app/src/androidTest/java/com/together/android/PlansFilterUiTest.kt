package com.together.android

import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.TogetherRepository
import com.together.android.ui.TogetherApp
import com.together.domain.*
import com.together.protocol.*
import java.io.File
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.*

/** Real Compose app and isolated Room/Keystore. No service or USB networking. */
class PlansFilterUiTest {
    @get:Rule val compose = createAndroidComposeRule<com.together.android.qa.BusinessQaActivity>()
    private lateinit var repo: TogetherRepository
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    private fun stage(value: String) { android.util.Log.i("TogetherPlansQa", value) }
    @After fun close() = runBlocking {
        stage("teardown-start")
        try { if (::repo.isInitialized) withTimeout(10000) { repo.close() } }
        finally { scope.cancel(); stage("teardown-finished") }
    }

    @Test fun mergedPendingAndCompletedLight() { checkFilters(false) }
    @Test fun mergedPendingAndCompletedDark() { checkFilters(true) }

    private fun checkFilters(dark: Boolean) {
        stage(if (dark) "dark-start" else "light-start")
        val now = Instant.parse("2026-10-09T04:00:00Z")
        repo = TogetherRepository(instrumentation.targetContext, scope, uid(), DateProvider { now })
        runBlocking {
            withTimeout(10000) { repo.state.first { it.loaded } }
            stage("repository-ready")
            repo.saveProfile("Synthetic QA", "unknown", null)
            for ((title, due) in listOf("QA overdue" to now.minusSeconds(86400).toEpochMilli(),
                    "QA future" to now.plusSeconds(86400).toEpochMilli(), "QA undated" to null,
                    "QA completed" to null)) {
                repo.execute { task(null, title, "", null, due, null) }
            }
            repo.completeTask(repo.state.value.snapshot.of("task").single { it.fields.text("title") == "QA completed" })
        }
        stage("fixture-ready")
        val configuration = Configuration(instrumentation.targetContext.resources.configuration)
        configuration.uiMode = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
        compose.setContent {
            CompositionLocalProvider(LocalConfiguration provides configuration) { TogetherApp(repo) }
        }
        stage("content-ready")
        if (compose.onAllNodesWithTag("navigation.open").fetchSemanticsNodes().isNotEmpty())
            compose.onNodeWithTag("navigation.open").performClick()
        compose.onNodeWithTag("nav.plans").performClick()
        stage("plans-navigation")
        compose.onNodeWithTag("tasks.pending").assertIsSelected()
        compose.onNodeWithTag("tasks.upcoming").assertDoesNotExist()
        compose.onNodeWithTag("tasks.completed").assertIsDisplayed()
        compose.onNodeWithTag("task.new").assertIsDisplayed()
        for (title in listOf("QA overdue", "QA future", "QA undated")) {
            compose.onNodeWithTag("tasks.list").performScrollToNode(hasText(title))
            compose.onNodeWithText(title).assertIsDisplayed()
        }
        compose.onNodeWithText("QA completed").assertDoesNotExist()
        stage("pending-asserted")
        compose.onNodeWithTag("tasks.list").performScrollToIndex(0)
        compose.waitForIdle()
        val run = InstrumentationRegistry.getArguments().getString("qaRunId")!!
        require(run.matches(Regex("[A-F0-9]{32}")))
        val theme = if (dark) "dark" else "light"
        File(instrumentation.targetContext.filesDir, "plans-unified-$run-$theme.png").outputStream().use {
            compose.onRoot().captureToImage().asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
        stage("candidate-captured")
        compose.onNodeWithTag("tasks.completed").performClick()
        compose.onNodeWithTag("task.new").assertDoesNotExist()
        compose.onNodeWithText("QA completed").assertIsDisplayed()
        compose.onNodeWithText("QA overdue").assertDoesNotExist()
        compose.onNodeWithTag("tasks.pending").performClick()
        compose.onNodeWithText("QA future").assertExists()
        stage("completed-asserted")
    }
}
