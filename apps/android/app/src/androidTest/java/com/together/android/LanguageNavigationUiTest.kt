package com.together.android

import android.content.ContextWrapper
import android.content.res.Configuration
import android.os.LocaleList
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
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
                    LocalConfiguration provides localized.resources.configuration) {
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
            compose.onNodeWithTag("language.zh-CN").assertIsDisplayed().performClick()
            compose.onNodeWithTag("language.zh-CN").assertDoesNotExist()
            compose.onAllNodesWithText("设置").assertAny(hasText("设置"))
            compose.onNodeWithTag("settings.language").assertIsDisplayed().performClick()
            compose.onNodeWithText("中文").assertIsDisplayed()
            compose.onNodeWithText("英语").assertIsDisplayed()
            compose.onNodeWithTag("language.en").performClick()
            compose.onAllNodesWithText("Settings").assertAny(hasText("Settings"))
        } finally {
            runBlocking { repository.close() }
            scope.cancel()
        }
    }
}
