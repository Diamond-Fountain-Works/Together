package com.together.android.data

import android.content.Context
import com.together.protocol.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.StateFlow

/** QA-only transport seam. Ordinary C1 builds never instantiate or bundle the native implementation. */
data class NativeAppStatus(
    val stage: String = "idle",
    val invitation: String? = null,
    val peer: DeviceDescriptor? = null,
    val verificationCode: String? = null,
    val path: String? = null,
    val error: String? = null,
    val offline: Boolean = false,
)

data class NativeRepositoryContext(
    val identity: DeviceIdentity,
    val store: RoomReplicaStore,
    val replica: Replica?,
    val media: MediaChannel?,
)

interface NativeAppRepository {
    suspend fun <T> access(block: (NativeRepositoryContext) -> T): T
    suspend fun pin(peer: DeviceDescriptor)
    suspend fun activate(archive: AuthorizationArchive, peer: DeviceDescriptor, binding: ByteArray)
    suspend fun refreshed()
}

interface NativeAppSession {
    val state: StateFlow<NativeAppStatus>
    suspend fun createInvitation()
    suspend fun joinInvitation(contact: String)
    suspend fun cancelInvitation()
    suspend fun confirm(verified: Boolean)
    fun changed()
    fun foreground(value: Boolean)
    fun reconnect()
    suspend fun setOffline(value: Boolean)
    suspend fun close()
}

interface NativeAppSessionFactory {
    fun create(context: Context, scope: CoroutineScope, repository: NativeAppRepository): NativeAppSession
}
