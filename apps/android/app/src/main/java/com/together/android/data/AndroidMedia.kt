package com.together.android.data

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import com.together.domain.*
import com.together.protocol.*
import java.io.File

object AndroidMedia {
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
            requireProtocol(options.outWidth > 0 && options.outHeight > 0, "UNSUPPORTED_MEDIA")
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
