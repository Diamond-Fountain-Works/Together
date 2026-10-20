package com.together.android

import android.os.Build
import android.os.Bundle
import androidx.test.runner.AndroidJUnitRunner

/**
 * Physical runs require an explicit, model-bound opt-in and an isolated test service. Run with `adb
 * am instrument`, never Gradle connected tests (which may uninstall the host).
 */
class IsolatedAndroidTestRunner : AndroidJUnitRunner() {
    override fun onCreate(arguments: Bundle) {
        check(BuildConfig.DEBUG && targetContext.packageName == "com.together.android.debug") {
            "Tests require the isolated Debug host"
        }
        if (Build.HARDWARE !in setOf("ranchu", "goldfish")) {
            check(arguments.getString("physicalQa") == "explicit-test-app-only") {
                "Physical QA must be explicitly authorized"
            }
            check(arguments.getString("expectedModel") == Build.MODEL) {
                "Physical QA model mismatch"
            }
            check(arguments.getString("qaRunId")?.matches(Regex("[A-F0-9]{32}")) == true) {
                "Physical QA run ID required"
            }
            val nativeP2p = arguments.getString("nativeP2pQa") == "explicit-public-p2p-only" &&
                arguments.getString("class")?.substringBefore('#') == "com.together.android.P2PPublicNetworkTest" &&
                arguments.getString("p2pNamespace")?.matches(Regex("QA-P2P-[A-Z0-9-]{1,32}")) == true
            val relay = java.net.URI(arguments.getString("relayURL") ?: "")
            val loopback = relay.scheme == "http" &&
                    relay.host == "127.0.0.1" &&
                    relay.port in 1024..65535
            val staging = arguments.getString("publicStagingQa") == "explicit-staging-only" &&
                relay.scheme == "https" && relay.host == "together-pairing-staging.together-connection-service.workers.dev" && relay.port == -1
            check(
                nativeP2p || ((loopback || staging) && relay.rawPath.orEmpty().isEmpty() &&
                    relay.rawQuery == null &&
                    relay.rawUserInfo == null && relay.rawFragment == null)
            ) {
                "Physical QA requires an explicitly authorized isolated Relay"
            }
            arguments.putString("listener", "com.together.android.RunnerTeardownDiagnostics")
        }
        super.onCreate(arguments)
    }
}
