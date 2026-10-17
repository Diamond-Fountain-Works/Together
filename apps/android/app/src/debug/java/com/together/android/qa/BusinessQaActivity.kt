package com.together.android.qa

import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import com.together.android.data.TogetherRepository
import com.together.android.ui.TogetherApp
import com.together.domain.DateProvider
import com.together.protocol.requireProtocol
import java.io.File
import java.time.Instant
import kotlinx.coroutines.*

/**
 * Debug-only isolated host. It can reopen an existing synthetic QA namespace, never create a
 * replacement identity.
 */
class BusinessQaActivity : ComponentActivity() {
    private var repository: TogetherRepository? = null
    private val qaScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        check(
            com.together.android.BuildConfig.DEBUG && packageName == "com.together.android.debug"
        ) {
            "Isolated Debug QA host required"
        }
        enableEdgeToEdge()
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val namespace =
            intent.getStringExtra("qaNamespace")
                ?: return // Compose test Rule supplies its own isolated repository.
        requireProtocol(Regex("[A-Z0-9-]{1,45}").matches(namespace), "INVALID_WORKSPACE")
        if (Build.HARDWARE !in setOf("ranchu", "goldfish")) {
            // A host-side, explicitly authorized run issues this short-lived capability using
            // run-as. It is only in this Debug installation, bound to one existing QA namespace.
            val permit = File(noBackupFilesDir, "physical-qa-permit.json")
            val values = org.json.JSONObject(permit.readText())
            val now = System.currentTimeMillis()
            requireProtocol(
                values.getString("namespace") == namespace &&
                    values.getString("token").matches(Regex("[A-F0-9]{64}")) &&
                    values.getString("token") == intent.getStringExtra("qaPhysicalToken") &&
                    values.getLong("expiresAt") > now &&
                    values.getLong("expiresAt") <= now + 3_600_000,
                "PHYSICAL_QA_EXPLICIT_PERMIT_REQUIRED",
            )
        }
        requireProtocol(
            File(noBackupFilesDir, "qa-$namespace/active-replica.json").isFile,
            "QA_EXISTING_REPLICA_REQUIRED",
        )
        val fixed = intent.getStringExtra("qaClock")?.let(Instant::parse)
        val repo =
            TogetherRepository(this, qaScope, namespace, DateProvider { fixed ?: Instant.now() })
        repository = repo
        setContent {
            Box(Modifier.semantics { testTagsAsResourceId = true }) { TogetherApp(repo) }
        }
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
