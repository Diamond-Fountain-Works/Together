package com.together.android.qa

import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.together.android.data.TogetherRepository
import com.together.android.ui.TogetherApp
import com.together.domain.DateProvider
import com.together.protocol.requireProtocol
import java.io.File
import java.time.Instant
import kotlinx.coroutines.*

/**
 * Debug-only emulator host. It can reopen an existing synthetic QA namespace, never create a
 * replacement identity.
 */
class BusinessQaActivity : ComponentActivity() {
    private var repository: TogetherRepository? = null
    private val qaScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        check(
            com.together.android.BuildConfig.DEBUG &&
                packageName == "com.together.android.debug" &&
                Build.HARDWARE in setOf("ranchu", "goldfish")
        ) {
            "Isolated emulator QA host required"
        }
        enableEdgeToEdge()
        val namespace =
            intent.getStringExtra("qaNamespace")
                ?: return // Compose test Rule supplies its own isolated repository.
        requireProtocol(Regex("[A-Z0-9-]{1,45}").matches(namespace), "INVALID_WORKSPACE")
        requireProtocol(
            File(noBackupFilesDir, "qa-$namespace/active-replica.json").isFile,
            "QA_EXISTING_REPLICA_REQUIRED",
        )
        val fixed = intent.getStringExtra("qaClock")?.let(Instant::parse)
        val repo =
            TogetherRepository(this, qaScope, namespace, DateProvider { fixed ?: Instant.now() })
        repository = repo
        setContent { TogetherApp(repo) }
    }

    override fun onStart() {
        super.onStart()
        repository?.foreground(true)
    }

    override fun onStop() {
        repository?.foreground(false)
        super.onStop()
    }

    override fun onDestroy() {
        val repo = repository
        qaScope.launch {
            repo?.close()
            qaScope.cancel()
        }
        super.onDestroy()
    }
}
