package com.together.protocol

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/** Existing C1 content wire shape; business frames and original bytes remain
 * independent. This does not modify Protocol 4 signed facts or receipt rules. */
@Serializable data class AuthenticatedSyncContent(val kind: String,
    val frame: ReplicationFrame? = null, val payload: JsonObject? = null) {
    fun validate() {
        when (kind) {
            "replication" -> requireProtocol(frame != null && payload == null, "INVALID_REPLICATION_CONTENT")
            "media" -> requireProtocol(payload != null && frame == null, "INVALID_MEDIA_CONTENT")
            else -> throw ProtocolException("UNKNOWN_CONTENT")
        }
    }
    companion object {
        fun replication(frame: ReplicationFrame) = AuthenticatedSyncContent("replication", frame = frame)
        fun media(payload: JsonObject) = AuthenticatedSyncContent("media", payload = payload)
        fun decode(bytes: ByteArray) = Canonical.parse(bytes).model<AuthenticatedSyncContent>().also { it.validate() }
    }
}
