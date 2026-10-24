package com.together.android

import android.content.ContextWrapper
import android.content.res.Configuration
import android.os.LocaleList
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.TogetherRepository
import com.together.android.localization.AppLanguage
import com.together.android.ui.TogetherApp
import com.together.protocol.uid
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated QA Activity and synthetic namespace; never opens the installed user workspace. */
@RunWith(AndroidJUnit4::class)
class LanguageNavigationUiTest {
    @get:Rule val compose = createAndroidComposeRule<com.together.android.qa.BusinessQaActivity>()

    @Test fun languageIsASettingsGlobeAndOptionsAppearOnlyOnClick() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.packageName == "com.together.android.debug")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val repository = TogetherRepository(context, scope, uid())
        try {
            runBlocking { withTimeout(15000) { repository.state.first { it.loaded } } }
            compose.setContent {
                var language by remember { mutableStateOf(AppLanguage.ENGLISH) }
                val localized = remember(language) {
                    val configuration = Configuration(context.resources.configuration)
                    configuration.setLocales(LocaleList(language.locale))
                    val localizedResources = context.createConfigurationContext(configuration).resources
                    object : ContextWrapper(compose.activity) {
                        override fun getResources() = localizedResources
                    }
                }
                CompositionLocalProvider(LocalContext provides localized,
                    LocalConfiguration provides localized.resources.configuration,
                    LocalResources provides localized.resources) {
                    TogetherApp(repository, language, { language = it })
                }
            }
            compose.onNodeWithTag("settings.language").assertDoesNotExist()
            if (compose.onAllNodesWithTag("navigation.open").fetchSemanticsNodes().isNotEmpty())
                compose.onNodeWithTag("navigation.open").performClick()
            // Navigation contains destinations, never a language row or globe.
            compose.onNodeWithTag("settings.language").assertDoesNotExist()
            compose.onNodeWithText("Language").assertDoesNotExist()
            compose.onNodeWithTag("nav.settings").performClick()
            compose.onNodeWithTag("settings.language").assertIsDisplayed()
            compose.onNodeWithText("Language").assertDoesNotExist()
            compose.onNodeWithTag("language.zh-CN").assertDoesNotExist()
            compose.onNodeWithTag("settings.language").performClick()
            waitForLanguagePopup()
            compose.onNodeWithTag("language.zh-CN").assertIsDisplayed().performClick()
            compose.onNodeWithTag("language.zh-CN").assertDoesNotExist()
            compose.onAllNodesWithText("设置").assertAny(hasText("设置"))
            compose.onNodeWithTag("profile.open").assertTextContains("资料").performClick()
            compose.onNodeWithTag("profile.editor").assertIsDisplayed()
            compose.onNodeWithTag("sheet.close").assertIsDisplayed().assertTextContains("取消").performClick()
            compose.onNodeWithTag("profile.editor").assertDoesNotExist()
            compose.onNodeWithTag("settings.language").assertIsDisplayed().performClick()
            waitForLanguagePopup()
            compose.onNodeWithTag("language.zh-CN").assertIsDisplayed().assertTextContains("中文")
            compose.onNodeWithTag("language.en").assertIsDisplayed().assertTextContains("英语")
            val screenshot = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            java.io.File(context.cacheDir, "language-settings-zh-menu.png").outputStream().use {
                screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
            compose.onNodeWithTag("language.en").performClick()
            compose.onAllNodesWithText("Settings").assertAny(hasText("Settings"))
        } catch (failure: Throwable) {
            runCatching {
                println("LANGUAGE_MENU_FAILURE_NODES " +
                    compose.onAllNodesWithTag("language.zh-CN", useUnmergedTree = true)
                        .fetchSemanticsNodes().map { it.boundsInRoot })
            }
            runCatching {
                val screenshot = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
                java.io.File(context.cacheDir, "language-navigation-failure.png").outputStream().use {
                    screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }
            }
            throw failure
        } finally {
            runBlocking { repository.close() }
            scope.cancel()
        }
    }
    private fun waitForLanguagePopup() {
        // PopupWindow layout is asynchronous to Compose's recomposition/animation clock.
        // Wait for actual visible menu bounds, retaining the final assertions and real click.
        val started = System.nanoTime()
        compose.waitUntil(timeoutMillis = 3000) {
            runCatching {
                compose.onNodeWithTag("language.zh-CN").assertIsDisplayed()
                compose.onNodeWithTag("language.en").assertIsDisplayed()
            }.isSuccess
        }
        println("LANGUAGE_POPUP_VISIBLE_MS " + (System.nanoTime() - started) / 1_000_000)
    }

}
