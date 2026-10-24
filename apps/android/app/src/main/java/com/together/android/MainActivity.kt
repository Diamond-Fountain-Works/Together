package com.together.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.together.android.ui.TogetherApp
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.lifecycle.compose.collectAsStateWithLifecycle

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState); enableEdgeToEdge()
        val app = application as TogetherApplication
        setContent {
            val language by app.languages.language.collectAsStateWithLifecycle()
            val configuration = LocalConfiguration.current
            val localized = remember(language, configuration) {
                app.languages.localizedContext(this@MainActivity, language)
            }
            CompositionLocalProvider(
                LocalContext provides localized,
                LocalConfiguration provides localized.resources.configuration,
                // stringResource/Popup/Dialog consume LocalResources independently
                // of the Activity context; update all three locals as one choice.
                LocalResources provides localized.resources,
            ) {
                TogetherApp(app.repository, language, app.languages::select)
            }
        }
    }
}
