package com.together.android.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.CancellationSignal
import android.provider.OpenableColumns
import com.together.domain.*
import com.together.protocol.*
import java.io.Closeable
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.*

object AndroidMedia {
    /** Close a provider pipe on cancellation, including a read waiting for bytes/EOF. */
    suspend fun importDocument(
        context: Context,
        uri: Uri,
        files: MediaFiles,
        type: String,
        owner: String,
        space: String,
        at: Long,
        onImported: (Asset) -> Unit = {},
    ): Asset = coroutineScope {
        val job = currentCoroutineContext()
        val signal = CancellationSignal()
        val resource = AtomicReference<Closeable?>()
        val closer =
            launch(Dispatchers.IO, start = CoroutineStart.UNDISPATCHED) {
                try {
                    awaitCancellation()
                } finally {
                    signal.cancel()
                    runCatching { resource.getAndSet(null)?.close() }
                }
            }
        try {
            runInterruptible(Dispatchers.IO) {
                val resolver = context.contentResolver
                var name = "media"
                resolver
                    .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null, signal)
                    ?.use { if (it.moveToFirst()) name = it.getString(0) ?: name }
                job.ensureActive()
                val descriptor =
                    resolver.openAssetFileDescriptor(uri, "r", signal)
                        ?: throw ProtocolException("MEDIA_IO_ERROR")
                resource.set(descriptor)
                try {
                    job.ensureActive()
                    val input = descriptor.createInputStream()
                    resource.set(input)
                    job.ensureActive()
                    files.import(
                        input,
                        name,
                        name.substringAfterLast('.', "").lowercase(),
                        type,
                        owner,
                        space,
                        at,
                        onImported = onImported,
                        checkCancelled = { job.ensureActive() },
                    )
                } finally {
                    runCatching { resource.getAndSet(null)?.close() }
                    runCatching { descriptor.close() }
                }
            }
        } catch (error: Exception) {
            job.ensureActive()
            throw error
        } finally {
            withContext(NonCancellable) { closer.cancelAndJoin() }
        }
    }

    fun legacyAvatar(bytes: ByteArray): Bitmap? {
        if (bytes.size > 131072) return null
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) return null
        options.inSampleSize = sample(options.outWidth, options.outHeight, 128)
        options.inJustDecodeBounds = false
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }

    fun validate(file: File, type: String) {
        if (type == "audio") {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(file.absolutePath)
                requireProtocol(
                    (retriever
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull() ?: 0) > 0,
                    "UNSUPPORTED_MEDIA",
                )
            } finally {
                retriever.release()
            }
        } else {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, options)
            if (options.outWidth <= 0 || options.outHeight <= 0) {
                // API24–27 has no system HEIF decoder. Preserve a structurally valid
                // original for authenticated transfer/export; never pretend it rendered.
                if (android.os.Build.VERSION.SDK_INT < 28 && HeifContainer.recognizes(file)) return
                throw ProtocolException("UNSUPPORTED_MEDIA")
            }
            options.inSampleSize = sample(options.outWidth, options.outHeight, 64)
            options.inJustDecodeBounds = false
            val bitmap =
                BitmapFactory.decodeFile(file.absolutePath, options)
                    ?: throw ProtocolException("UNSUPPORTED_MEDIA")
            bitmap.recycle()
        }
    }

    private fun sample(w: Int, h: Int, max: Int): Int {
        var n = 1
        while (w / n > max * 2 || h / n > max * 2) {
            if (n > 1 shl 28) break
            n *= 2
        }
        return n
    }

    fun preview(files: MediaFiles, asset: Asset): File {
        requireProtocol(files.verified(asset) && asset.mediaType != "audio", "UNVERIFIED_MEDIA")
        val target = File(files.original(asset).parentFile, "preview.png")
        if (target.exists()) return target
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(files.original(asset).absolutePath, o)
        o.inSampleSize = sample(o.outWidth, o.outHeight, 1024)
        o.inJustDecodeBounds = false
        val bitmap =
            BitmapFactory.decodeFile(files.original(asset).absolutePath, o)
                ?: throw ProtocolException("UNSUPPORTED_MEDIA")
        try {
            target.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        } finally {
            bitmap.recycle()
        }
        return target
    }
}
