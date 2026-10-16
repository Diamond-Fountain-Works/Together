package com.together.android.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import com.together.protocol.*
import kotlinx.serialization.json.*
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Each independent Ed25519 seed is AES-GCM wrapped by an Android Keystore key.
 * Ed25519 itself is BC software, not advertised as hardware-backed. Backup is disabled.
 * Missing/corrupt files or invalidated wrapping keys fail closed; never silently rotate. */
class AndroidIdentityStore(context: Context, private val namespace: String? = null) {
    init { requireProtocol(namespace == null || (com.together.android.BuildConfig.DEBUG && Regex("[A-Z0-9-]{1,45}").matches(namespace)), "INVALID_WORKSPACE") }
    private val root = File(if (namespace == null) context.noBackupFilesDir else File(context.noBackupFilesDir, "qa-$namespace"), "identity").apply { mkdirs() }
    private val keystore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    fun exists(slot: String) = path(slot).exists()
    private fun path(slot: String): File { requireProtocol(Regex("[A-Z0-9-]{1,50}").matches(slot), "INVALID_IDENTITY_PATH"); return File(root, "$slot.json") }
    private fun alias(slot: String) = if (namespace == null) "Together.Ed25519.Wrap.$slot" else "Together.QA.$namespace.Wrap.$slot"
    private fun key(slot: String, create: Boolean): SecretKey {
        val existing = keystore.getKey(alias(slot), null)
        if (existing is SecretKey) return existing
        requireProtocol(create, "IDENTITY_KEY_UNAVAILABLE")
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias(slot), KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).setRandomizedEncryptionRequired(true).build())
        return generator.generateKey()
    }
    @Synchronized fun create(slot: String, userId: String, spaceId: String, name: String, zone: String): DeviceIdentity {
        requireProtocol(!exists(slot) && !keystore.containsAlias(alias(slot)), "IDENTITY_ALREADY_EXISTS")
        val seed = Crypto.seed()
        try {
            val identity = DeviceIdentity.create(seed, userId, spaceId, name = name, zone = zone)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key(slot, true)); cipher.updateAAD(Canonical.encode(identity.descriptor))
            val wrapped = cipher.doFinal(seed)
            val data = buildJsonObject { put("version", 1); put("descriptor", identity.descriptor.json()); put("iv", cipher.iv.b64()); put("wrappedSeed", wrapped.b64()) }
            atomicWrite(path(slot), Canonical.bytes(data)); return load(slot)
        } finally { seed.fill(0) }
    }
    @Synchronized fun load(slot: String): DeviceIdentity {
        val file = path(slot); requireProtocol(file.exists(), "IDENTITY_FILE_UNAVAILABLE")
        val obj = Canonical.parse(AtomicFile(file).readFully(), 8192).jsonObject
        requireProtocol(obj.getValue("version").jsonPrimitive.int == 1, "IDENTITY_VERSION")
        val descriptor = obj.getValue("descriptor").model<DeviceDescriptor>()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.DECRYPT_MODE, key(slot, false), GCMParameterSpec(128, obj.getValue("iv").jsonPrimitive.content.unbase64())); cipher.updateAAD(Canonical.encode(descriptor))
        val seed = cipher.doFinal(obj.getValue("wrappedSeed").jsonPrimitive.content.unbase64())
        try { return DeviceIdentity(descriptor, seed.copyOf()) } finally { seed.fill(0) }
    }
    private fun atomicWrite(file: File, bytes: ByteArray) {
        val atomic = AtomicFile(file); val stream = atomic.startWrite()
        try { stream.write(bytes); atomic.finishWrite(stream) } catch (e: Exception) { atomic.failWrite(stream); throw e }
    }
}
