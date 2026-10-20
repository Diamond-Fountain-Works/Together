package com.together.android.data

import com.together.protocol.ProtocolException
import org.junit.Assert.assertEquals
import org.junit.Test

class NativeRuntimePolicyTest {
    private fun rejected(code: String, block: () -> Unit) {
        try { block(); throw AssertionError("Expected fail-closed rejection") }
        catch (error: ProtocolException) { assertEquals(code, error.code) }
    }

    @Test fun releaseUsesOnlyItsNormalPrivateRoot() {
        NativeRuntimePolicy.validate(true, false, false, "com.together.android", null, "")
        rejected("NATIVE_TRANSPORT_REQUIRED") {
            NativeRuntimePolicy.validate(true, false, false, "com.together.android", "NATIVE-APP", "")
        }
        rejected("NATIVE_TRANSPORT_REQUIRED") {
            NativeRuntimePolicy.validate(true, false, true, "com.together.android.debug", null, "")
        }
    }

    @Test fun nativeNeverFallsBackToProductionCloudflare() {
        rejected("NATIVE_TRANSPORT_REQUIRED") {
            NativeRuntimePolicy.validate(true, false, false, "com.together.android", null, "https://example.invalid")
        }
    }

    @Test fun qaRequiresItsOwnDebugPackageAndNamespace() {
        NativeRuntimePolicy.validate(true, true, true, "com.together.android.qa.native", "NATIVE-APP", "")
        rejected("ISOLATED_NATIVE_QA_REQUIRED") {
            NativeRuntimePolicy.validate(true, true, true, "com.together.android", "NATIVE-APP", "")
        }
        rejected("ISOLATED_NATIVE_QA_REQUIRED") {
            NativeRuntimePolicy.validate(true, true, true, "com.together.android.qa.native", null, "")
        }
    }

    @Test fun legacyC1DebugKeepsItsExistingIsolationAndOrigin() {
        NativeRuntimePolicy.validate(false, false, true, "com.together.android.debug", "SYNTHETIC", "http://127.0.0.1")
    }

    @Test fun genuinelyEmptyInstallCanCreateIndependentIdentity() {
        NativeRuntimePolicy.requireFirstIdentity(false, false, false)
    }

    @Test fun anyPriorStorageEvidencePreventsReplacementIdentity() {
        for (evidence in listOf(Triple(true, false, false), Triple(false, true, false), Triple(false, false, true))) {
            rejected("IDENTITY_FILE_UNAVAILABLE") {
                NativeRuntimePolicy.requireFirstIdentity(evidence.first, evidence.second, evidence.third)
            }
        }
    }
}
