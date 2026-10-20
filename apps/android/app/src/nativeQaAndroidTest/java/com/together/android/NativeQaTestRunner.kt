package com.together.android

import android.os.Build
import android.os.Bundle
import androidx.test.runner.AndroidJUnitRunner

/** Only one public-input clipboard aid is authorized; no other fixture or data setup can run. */
class NativeQaTestRunner : AndroidJUnitRunner() {
    override fun onCreate(arguments: Bundle) {
        check(BuildConfig.DEBUG && BuildConfig.NATIVE_QA &&
            targetContext.packageName == "com.together.android.qa.native" &&
            arguments.getString("nativeAppQa") == "explicit-native-app-ui-only" &&
            arguments.getString("class") == "com.together.android.NativeQaClipboardTest#placePublicInvitation") {
            "Native QA requires the explicit, isolated clipboard input helper"
        }
        if (Build.HARDWARE !in setOf("ranchu", "goldfish")) {
            check(arguments.getString("physicalQa") == "explicit-test-app-only")
            check(arguments.getString("expectedModel") == Build.MODEL)
            check(arguments.getString("qaRunId")?.matches(Regex("[A-F0-9]{32}")) == true)
        }
        super.onCreate(arguments)
    }
}
