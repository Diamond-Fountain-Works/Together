package com.together.android

import android.os.Build
import android.os.Bundle
import androidx.test.runner.AndroidJUnitRunner

/**
 * Physical runs require an explicit, model-bound opt-in and a loopback test service. Run with `adb
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
            val relay = java.net.URI(arguments.getString("relayURL") ?: "")
            check(
                relay.scheme == "http" &&
                    relay.host == "127.0.0.1" &&
                    relay.port in 1024..65535 &&
                    relay.rawPath.orEmpty().isEmpty() &&
                    relay.rawQuery == null &&
                    relay.rawUserInfo == null
            ) {
                "Physical QA requires an explicit loopback Relay"
            }
            arguments.putString("listener", "com.together.android.RunnerTeardownDiagnostics")
        }
        super.onCreate(arguments)
    }
}
