package com.together.android.data

import java.io.File
import java.io.RandomAccessFile

/**
 * Legacy systems without a HEIF codec can retain/export an original after bounded
 * container checks. This verifies container structure, never decoded image pixels.
 * No compressed payload is read or decompressed and no file/pixel-size cap is imposed.
 */
internal object HeifContainer {
    private const val MAX_BOXES = 4096
    private val hevcBrands = setOf("heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs")
    private data class Box(val type: String, val payload: Long, val end: Long) {
        val length get() = end - payload
    }

    fun recognizes(file: File): Boolean = runCatching {
        RandomAccessFile(file, "r").use { input -> Reader(input).recognizes() }
    }.getOrDefault(false)

    private class Reader(private val input: RandomAccessFile) {
        private var visited = 0
        private val length = input.length()
        private fun uint(at: Long): Long {
            check(at >= 0 && length - at >= 4)
            input.seek(at)
            return input.readInt().toLong() and 0xffffffffL
        }
        private fun code(at: Long): String {
            check(at >= 0 && length - at >= 4)
            val bytes = ByteArray(4)
            input.seek(at); input.readFully(bytes)
            return String(bytes, Charsets.US_ASCII)
        }
        private fun boxes(start: Long, end: Long): List<Box> {
            check(start >= 0 && end <= length && start <= end)
            val result = mutableListOf<Box>()
            var at = start
            while (at < end) {
                check(++visited <= MAX_BOXES && end - at >= 8)
                val shortSize = uint(at)
                val type = code(at + 4)
                val header = if (shortSize == 1L) 16L else 8L
                val size = when (shortSize) {
                    0L -> end - at
                    1L -> { check(end - at >= 16); input.seek(at + 8); input.readLong().also { check(it >= 16) } }
                    else -> shortSize
                }
                check(size >= header && size <= end - at) // subtraction avoids signed-long overflow
                result += Box(type, at + header, at + size)
                at += size
            }
            return result
        }
        private fun List<Box>.one(type: String) = filter { it.type == type }.single()
        private fun version(box: Box): Int = (uint(box.payload) ushr 24).toInt()
        private inner class Cursor(private val box: Box, start: Long = box.payload) {
            var at = start
            fun unsigned(bytes: Int): Long {
                check(bytes in 0..8 && at >= box.payload && bytes <= box.end - at)
                input.seek(at)
                var result = 0L
                repeat(bytes) { result = (result shl 8) or input.readUnsignedByte().toLong() }
                at += bytes
                check(result >= 0)
                return result
            }
        }
        private fun primaryId(box: Box): Long {
            check(version(box) in 0..1)
            return Cursor(box, box.payload + 4).unsigned(if (version(box) == 0) 2 else 4).also { check(it > 0) }
        }
        private fun itemInfo(box: Box): Map<Long, String> {
            check(version(box) in 0..1)
            val cursor = Cursor(box, box.payload + 4)
            val count = cursor.unsigned(if (version(box) == 0) 2 else 4)
            check(count in 1..MAX_BOXES.toLong())
            val entries = boxes(cursor.at, box.end)
            check(entries.size.toLong() == count && entries.all { it.type == "infe" })
            val result = mutableMapOf<Long, String>()
            for (entry in entries) {
                val v = version(entry)
                check(v in 2..3)
                val c = Cursor(entry, entry.payload + 4)
                val id = c.unsigned(if (v == 2) 2 else 4)
                c.unsigned(2) // item protection index; no compressed bytes are interpreted here
                check(entry.end - c.at >= 4 && id > 0 && id !in result)
                result[id] = code(c.at)
            }
            return result
        }
        private fun locations(box: Box, info: Map<Long, String>, primary: Long,
                              media: List<Box>, idat: Box?) {
            val v = version(box)
            check(v in 0..2)
            val c = Cursor(box, box.payload + 4)
            val offsetLength = c.unsigned(1).toInt()
            val baseIndex = c.unsigned(1).toInt()
            val offsetSize = offsetLength ushr 4
            val lengthSize = offsetLength and 15
            val baseSize = baseIndex ushr 4
            val indexSize = if (v == 0) 0 else baseIndex and 15
            check(listOf(offsetSize, lengthSize, baseSize, indexSize).all { it in setOf(0, 4, 8) })
            val count = c.unsigned(if (v < 2) 2 else 4)
            check(count in 1..MAX_BOXES.toLong())
            val seen = mutableSetOf<Long>()
            repeat(count.toInt()) {
                check(++visited <= MAX_BOXES)
                val id = c.unsigned(if (v < 2) 2 else 4)
                check(id in info && seen.add(id))
                val construction = if (v == 0) 0 else c.unsigned(2).toInt()
                check(construction in 0..1 && c.unsigned(2) == 0L) // no external data references
                val base = c.unsigned(baseSize)
                val extents = c.unsigned(2)
                check(extents in 1..MAX_BOXES.toLong())
                repeat(extents.toInt()) {
                    check(++visited <= MAX_BOXES)
                    if (v > 0 && indexSize > 0) c.unsigned(indexSize)
                    val offset = c.unsigned(offsetSize)
                    val size = c.unsigned(lengthSize)
                    check(size > 0 && offset <= Long.MAX_VALUE - base)
                    val relative = base + offset
                    if (construction == 0) {
                        check(media.any { relative >= it.payload && relative <= it.end && size <= it.end - relative })
                    } else {
                        check(idat != null && relative <= idat.length && size <= idat.length - relative)
                    }
                }
            }
            check(primary in seen && c.at == box.end)
        }
        fun recognizes(): Boolean {
            check(length >= 32)
            val top = boxes(0, length)
            val ftyp = top.one("ftyp")
            check(top.first() == ftyp && ftyp.length >= 8 && ftyp.length <= 4096 && ftyp.length % 4 == 0L)
            val brands = mutableSetOf(code(ftyp.payload))
            var brand = ftyp.payload + 8
            while (brand < ftyp.end) { brands += code(brand); brand += 4 }
            check(brands.any { it in hevcBrands })
            val meta = top.one("meta")
            check(meta.length >= 4 && version(meta) == 0)
            val children = boxes(meta.payload + 4, meta.end)
            val hdlr = children.one("hdlr")
            check(hdlr.length >= 12 && code(hdlr.payload + 8) == "pict")
            val primary = primaryId(children.one("pitm"))
            val info = itemInfo(children.one("iinf"))
            check(info[primary] in setOf("hvc1", "grid", "iden", "iovl"))
            val data = top.filter { it.type == "mdat" && it.length > 0 }
            val inline = children.filter { it.type == "idat" }.singleOrNull()
            locations(children.one("iloc"), info, primary, data, inline)
            val properties = boxes(children.one("iprp").payload, children.one("iprp").end)
            val ipco = properties.one("ipco")
            val imageProperties = boxes(ipco.payload, ipco.end)
            check(imageProperties.any { it.type == "ispe" && it.length >= 12 &&
                uint(it.payload + 4) > 0 && uint(it.payload + 8) > 0 })
            check(imageProperties.any { it.type == "hvcC" && it.length >= 23 &&
                (uint(it.payload) ushr 24) == 1L })
            val associations = properties.one("ipma")
            check(associations.length >= 8 && uint(associations.payload + 4) > 0)
            check(top.any { it.type == "mdat" && it.length > 0 } ||
                children.any { it.type == "idat" && it.length > 0 })
            return true
        }
    }
}
