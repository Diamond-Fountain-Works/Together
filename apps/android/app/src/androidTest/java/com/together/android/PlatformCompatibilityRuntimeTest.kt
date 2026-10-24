package com.together.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import computer.iroh.*
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import com.together.domain.*
import com.together.android.data.AndroidMedia
import com.together.android.data.HeifContainer
import com.together.android.data.AndroidIdentityStore
import com.together.android.data.RoomReplicaStore
import com.together.android.data.TogetherDatabase
import com.together.protocol.*
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.KeyStore
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Run on every supported API/ABI. A modern emulator pass is not an API-24 device pass. */
@RunWith(AndroidJUnit4::class)
class PlatformCompatibilityRuntimeTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext.also {
        check(BuildConfig.DEBUG && it.packageName == "com.together.android.debug")
    }

    @Test fun desugaredCalendarBase64AndSignaturesKeepExactProtocolBytes() {
        val date = Instant.parse("2024-02-29T16:30:00Z").atZone(ZoneId.of("Asia/Shanghai"))
        assertEquals(LocalDate.of(2024, 3, 1), date.toLocalDate())
        val bytes = "中文 / ♡\n".toByteArray(Charsets.UTF_8)
        assertArrayEquals(bytes, bytes.b64().unbase64())
        val seed = ByteArray(32) { it.toByte() } // Synthetic, public deterministic test seed.
        val signature = Crypto.sign(seed, bytes)
        assertTrue(Crypto.verify(Crypto.publicKey(seed), signature, bytes))
        assertFalse(Crypto.verify(Crypto.publicKey(seed), signature, bytes + 1.toByte()))
        assertEquals(1, "👨‍👩‍👧‍👦".graphemeCount())
        assertEquals(1, "e\u0301".graphemeCount())
        assertEquals(1, "🇨🇳".graphemeCount())
    }

    @Test fun desugaredNioAtomicReplacementPreservesOriginalBytes() {
        val owned = File(context.cacheDir, "compat-nio-${uid()}").apply { mkdirs() }
        try {
            val target = File(owned, "original.bin")
            val temporary = File(owned, "verified.tmp")
            val bytes = ByteArray(131_073) { (it % 251).toByte() }
            target.writeBytes(byteArrayOf(1, 2, 3))
            FileOutputStream(temporary).use { it.write(bytes); it.fd.sync() }
            Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING)
            assertFalse(temporary.exists())
            assertArrayEquals(bytes, target.readBytes())
        } finally {
            assertTrue(owned.deleteRecursively())
        }
    }

    @Test fun actualKeystoreAndRoomPreserveIndependentIdentityAndSignedHistoryOnReopen() {
        val context = context
        val namespace = "COMPAT-${uid()}"
        val databaseName = "compat-$namespace.db"
        val slot = "CURRENT"
        val identityStore = AndroidIdentityStore(context, namespace)
        val a = identityStore.create(slot, uid(), uid(), "Compatibility QA", "Asia/Shanghai")
        val b = DeviceIdentity.create(Crypto.seed(), name = "Compatibility partner QA", zone = "Asia/Shanghai")
        val roots = listOf(a, b).sortedBy { it.descriptor.deviceId }
        val space = stableId("compat:" + roots.joinToString(":") { it.descriptor.deviceId })
        val body = GenesisBody(4, space, roots.map { it.descriptor.userId }.sorted(), roots.map { it.descriptor },
            listOf(a.descriptor.initialSpaceId, b.descriptor.initialSpaceId, space).distinct().sorted(),
            "Asia/Shanghai", checkpoint(emptyList()))
        val trust = SpaceAuthorization.restore(AuthorizationArchive(SignedGenesis(body,
            roots.map { DeviceSignature(it.descriptor.deviceId, it.sign(Canonical.encode(body))) }), emptyList()))
        var db: TogetherDatabase? = null
        try {
            db = TogetherDatabase.open(context, databaseName)
            val replica = Replica(RoomReplicaStore(db), a, trust).also { it.restore() }
            val operation = SyncOperation(uid(), a.descriptor.deviceId, a.descriptor.userId, uid(), "task", "create",
                1, mapOf("title" to LogValue.string("Compatibility synthetic task")), 1791532800000)
            val saved = replica.append(listOf(operation)).single()
            val exact = Canonical.encode(saved)
            db.close()
            val restored = identityStore.load(slot)
            assertEquals(a.descriptor, restored.descriptor)
            db = TogetherDatabase.open(context, databaseName)
            val reopened = Replica(RoomReplicaStore(db), restored, trust).also { it.restore() }
            val history = reopened.store.rows()
            assertEquals(1, history.size)
            assertArrayEquals(exact, Canonical.encode(history.single().record))
            history.single().record.authorized!!.verify(trust)
            val challenge = "identity-still-signs".toByteArray()
            assertTrue(Crypto.verify(a.descriptor.publicKey.unbase64(), restored.sign(challenge).unbase64(), challenge))
        } finally {
            db?.close()
            context.deleteDatabase(databaseName)
            assertFalse(context.getDatabasePath(databaseName).exists())
            val ownedIdentity = File(context.noBackupFilesDir, "qa-$namespace")
            assertTrue(ownedIdentity.deleteRecursively())
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                .deleteEntry("Together.QA.$namespace.Wrap.$slot")
        }
    }
    @Test fun reviewedNativeJniAndAsyncEndpointWorkWithoutPublicRelay() = runBlocking {
        assertEquals("5.19.1", com.sun.jna.Native.VERSION)
        IrohAndroid.installAndroidContext(context)
        val key = SecretKey.generate()
        val seed = try { key.toBytes() } finally { key.close() }
        val endpoint = try {
            withTimeout(15_000) {
                Endpoint.bind(EndpointOptions(preset = presetMinimal(), bindAddr = "127.0.0.1:0",
                    secretKey = seed, alpns = listOf("together-compatibility-qa".toByteArray()),
                    relayMode = RelayMode.disabled()))
            }
        } finally { seed.fill(0) }
        try {
            val address = endpoint.addr()
            try {
                assertTrue(Regex("[0-9a-f]{64}").matches(address.id().toString()))
                assertNull(address.relayUrl())
            } finally { address.close() }
        } finally { endpoint.close() }
    }

    @Test fun syntheticHeifContainerAndOriginalTransferExportKeepExactBytes() {
        val root = File(context.cacheDir, "compat-heif-${uid()}").apply { mkdirs() }
        // Generated by ImageIO from a 16x16 solid RGB PNG; no photo, GPS or user content.
        val bytes = "AAAAJGZ0eXBoZWljAAAAAG1pZjFNaVBybWlhZk1pSEJoZWljAAABhm1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAHBpY3QAAAAAAAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAAADnBpdG0AAAAAAAEAAAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABodmMxAAAAAOZpcHJwAAAAxWlwY28AAAATY29scm5jbHgAAgACAAaAAAAADGNsbGkAywBAAAAAFGlzcGUAAAAAAAAAEAAAABAAAAAJaXJvdAAAAAAQcGl4aQAAAAADCAgIAAAAcWh2Y0MBA3AAAACwAAAAAAAe8AD8/fj4AAALA6AAAQAXQAEMAf//A3AAAAMAsAAAAwAAAwAecCShAAEAI0IBAQNwAAADALAAAAMAAAMAHqAUIEHAkwziHuRZVNwICBgCogABAAlEAcBhcshAUyQAAAAZaXBtYQAAAAAAAAABAAEGgQIDBYaEAAAAHmlsb2MAAAAARAAAAQABAAAAAQAAAboAAABCAAAAAW1kYXQAAAAAAAAAUgAAAD4oAa+i6kaBfMXj5//h/svcXz1f/BnyKsS/vWD3TLJn+j6DYP+vEw/60i+mVr78MBz0LtImpbTmVTR2Rc9PwA==".unbase64()
        try {
            val file = File(root, "synthetic.heic").apply { writeBytes(bytes) }
            assertTrue(HeifContainer.recognizes(file))
            val local = MediaFiles(File(root, "sender"), validateFormat = AndroidMedia::validate)
            val remote = MediaFiles(File(root, "receiver"), validateFormat = AndroidMedia::validate)
            val asset = local.import(bytes.inputStream(), "synthetic.heic", "heic", "photo", uid(), uid(), 1791532800000)
            var offset = 0L
            while (offset < asset.byteCount) offset = remote.append(asset, offset, local.read(asset, offset))
            remote.finish(asset)
            assertTrue(remote.verified(asset))
            val exported = java.io.ByteArrayOutputStream()
            remote.export(asset, exported)
            assertArrayEquals(bytes, exported.toByteArray())
            assertEquals(sha256(bytes), asset.sha256)
        } finally { assertTrue(root.deleteRecursively()) }
    }

}
