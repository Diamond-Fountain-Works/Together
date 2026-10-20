package com.together.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Base64
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.protocol.Canonical
import com.together.protocol.NativePartnerContact
import com.together.protocol.model
import com.together.protocol.requireProtocol
import org.junit.Test
import org.junit.runner.RunWith

/** Input aid only: writes one validated PUBLIC invitation. Never reads clipboard, stores or trust. */
@RunWith(AndroidJUnit4::class)
class NativeQaClipboardTest {
    @Test fun placePublicInvitation() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val args = InstrumentationRegistry.getArguments()
        requireProtocol(BuildConfig.NATIVE_QA && BuildConfig.DEBUG &&
            instrumentation.targetContext.packageName == "com.together.android.qa.native" &&
            args.getString("nativeAppQa") == "explicit-native-app-ui-only", "ISOLATED_NATIVE_QA_REQUIRED")
        val encoded = args.getString("publicContactBase64") ?: error("PUBLIC_CONTACT_REQUIRED")
        requireProtocol(encoded.length in 1..44_000 && Regex("[A-Za-z0-9+/]*={0,2}").matches(encoded),
            "INVALID_NATIVE_CONTACT")
        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
        requireProtocol(bytes.size in 1..32_768, "INVALID_NATIVE_CONTACT")
        val contact = Canonical.parse(bytes, 32_768).model<NativePartnerContact>()
        contact.verify()
        val text = Canonical.encode(contact).toString(Charsets.UTF_8)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText(activity.getString(R.string.partner_code), text))
            }
        }
        instrumentation.waitForIdleSync()
    }
}
