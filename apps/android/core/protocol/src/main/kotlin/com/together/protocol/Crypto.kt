package com.together.protocol

import org.bouncycastle.crypto.params.*
import org.bouncycastle.crypto.signers.Ed25519Signer
import org.bouncycastle.crypto.generators.HKDFBytesGenerator
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.modes.ChaCha20Poly1305
import java.security.SecureRandom

/** Lightweight BC primitives, not Android's replaceable global JCA provider. */
object Crypto {
    private val random = SecureRandom()
    fun seed() = ByteArray(32).also(random::nextBytes)
    fun publicKey(seed: ByteArray): ByteArray = Ed25519PrivateKeyParameters(seed, 0).generatePublicKey().encoded
    fun sign(seed: ByteArray, bytes: ByteArray): ByteArray = Ed25519Signer().run {
        init(true, Ed25519PrivateKeyParameters(seed, 0)); update(bytes, 0, bytes.size); generateSignature()
    }
    fun verify(publicKey: ByteArray, signature: ByteArray, bytes: ByteArray): Boolean = try {
        publicKey.size == 32 && signature.size == 64 && Ed25519Signer().run {
            init(false, Ed25519PublicKeyParameters(publicKey, 0)); update(bytes, 0, bytes.size); verifySignature(signature)
        }
    } catch (_: Exception) { false }
    fun xPublic(seed: ByteArray) = X25519PrivateKeyParameters(seed, 0).generatePublicKey().encoded
    fun xSecret(seed: ByteArray, remote: ByteArray): ByteArray = ByteArray(32).also {
        X25519PrivateKeyParameters(seed, 0).generateSecret(X25519PublicKeyParameters(remote, 0), it, 0)
        requireProtocol(it.any { b -> b != 0.toByte() }, "INVALID_X25519_KEY")
    }
    fun hkdf(secret: ByteArray, salt: ByteArray, info: ByteArray): ByteArray = ByteArray(32).also {
        HKDFBytesGenerator(SHA256Digest()).apply { init(HKDFParameters(secret, salt, info)); generateBytes(it, 0, it.size) }
    }
    fun aead(encrypt: Boolean, key: ByteArray, nonce: ByteArray, aad: ByteArray, bytes: ByteArray): ByteArray {
        val cipher = ChaCha20Poly1305(); cipher.init(encrypt, AEADParameters(KeyParameter(key), 128, nonce, aad))
        val out = ByteArray(cipher.getOutputSize(bytes.size)); val n = cipher.processBytes(bytes, 0, bytes.size, out, 0)
        val size = n + cipher.doFinal(out, n); return out.copyOf(size)
    }
}
