package com.together.android

import android.os.Build
import android.os.Bundle
import androidx.test.runner.AndroidJUnitRunner

/** No production package or accidental physical-phone test installation. */
class IsolatedAndroidTestRunner : AndroidJUnitRunner() {
    override fun onCreate(arguments: Bundle) {
        check(BuildConfig.DEBUG && targetContext.packageName == "com.together.android.debug") { "Tests require the isolated Debug host" }
        check(Build.HARDWARE in setOf("ranchu", "goldfish")) { "This automated suite requires a dedicated emulator; physical-device QA needs a separately reviewed run" }
        super.onCreate(arguments)
    }
}
