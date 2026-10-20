package com.together.android.data

import com.together.protocol.requireProtocol

/** Transport selection never grants access to a QA or production data root. */
internal object NativeRuntimePolicy {
    fun validate(native: Boolean, qa: Boolean, debug: Boolean, packageName: String,
        namespace: String?, relayOrigin: String) {
        requireProtocol(!qa || native, "ISOLATED_NATIVE_QA_REQUIRED")
        if (!native) return
        requireProtocol(relayOrigin.isEmpty(), "NATIVE_TRANSPORT_REQUIRED")
        if (qa) requireProtocol(debug && packageName == "com.together.android.qa.native" &&
            namespace == "NATIVE-APP", "ISOLATED_NATIVE_QA_REQUIRED")
        else requireProtocol(!debug && packageName == "com.together.android" && namespace == null,
            "NATIVE_TRANSPORT_REQUIRED")
    }

    fun requireFirstIdentity(hasStore: Boolean, hasReplicaPointer: Boolean, hasTransportKey: Boolean) {
        requireProtocol(!hasStore && !hasReplicaPointer && !hasTransportKey, "IDENTITY_FILE_UNAVAILABLE")
    }
}
