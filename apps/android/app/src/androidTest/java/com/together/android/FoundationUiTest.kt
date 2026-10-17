package com.together.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.TogetherRepository
import com.together.android.ui.TogetherApp
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs only on the independent com.together.android.debug installation. The text below is a test
 * fixture, never bundled as live product content.
 */
@RunWith(AndroidJUnit4::class)
class FoundationUiTest {
    @get:Rule val compose = createAndroidComposeRule<com.together.android.qa.BusinessQaActivity>()

    @Test
    fun offlineTaskCreateEditCompleteDeleteAndCloseSheets() {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val repository =
            TogetherRepository(
                InstrumentationRegistry.getInstrumentation().targetContext,
                scope,
                com.together.protocol.uid(),
            )
        try {
            runBlocking { withTimeout(15000) { repository.state.first { it.loaded } } }
            compose.setContent { TogetherApp(repository) }
            val title = "Synthetic Android QA " + com.together.protocol.uid()
            val edited = title + " edited"
            compose.waitUntil(15000) {
                compose.onAllNodesWithTag("connection.status").fetchSemanticsNodes().isNotEmpty()
            }
            navigate("plans")
            compose.onNodeWithTag("task.new").performClick()
            compose.onNodeWithTag("task.title").performTextInput(title)
            compose.onNodeWithTag("task.notes").performTextInput("Synthetic offline notes")
            compose.onNodeWithTag("task.save").performClick()
            compose.waitUntil(15000) {
                compose.onAllNodesWithTag("task.editor").fetchSemanticsNodes().isEmpty()
            }
            compose.onNodeWithText(title).assertIsDisplayed().performClick()
            compose.onNodeWithTag("task.title").performTextReplacement(edited)
            compose.onNodeWithTag("task.save").performClick()
            compose.waitUntil(15000) {
                compose.onAllNodesWithTag("task.editor").fetchSemanticsNodes().isEmpty()
            }
            compose.onNodeWithText(edited).assertIsDisplayed()
            val id =
                repository.state.value.snapshot
                    .of("task")
                    .single {
                        it.deletedAt == null &&
                            com.together.protocol.LogValue.string(it.fields["title"]) == edited
                    }
                    .id
            compose.onNodeWithTag("task.complete.$id").performClick()
            compose.onNodeWithTag("tasks.completed").performClick()
            compose.onNodeWithText(edited).assertIsDisplayed()
            compose.onNodeWithTag("task.delete.$id").performClick()
            compose.waitUntil(15000) {
                compose.onAllNodesWithText(edited).fetchSemanticsNodes().isEmpty()
            }
            navigate("home")
            compose.onNodeWithTag("changes.open").performClick()
            compose.onNodeWithTag("changes.close").performClick()
            navigate("connection")
            compose.onNodeWithTag("device.add").performClick()
            compose.onNodeWithTag("device.importOffer").assertIsDisplayed()
            compose.onNodeWithText(compose.activity.getString(R.string.action_close)).performClick()
        } finally {
            runBlocking { repository.close() }
            scope.cancel()
        }
    }

    private fun navigate(page: String) {
        if (compose.onAllNodesWithTag("navigation.open").fetchSemanticsNodes().isNotEmpty()) compose.onNodeWithTag("navigation.open").performClick()
        compose.onNodeWithTag("nav.$page").performClick()
    }

    private fun hasTestTagPrefix(prefix: String) =
        SemanticsMatcher("testTagPrefix") { node ->
            node.config
                .getOrElse(androidx.compose.ui.semantics.SemanticsProperties.TestTag) { "" }
                .startsWith(prefix)
        }
}
