package com.together.android.data

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import org.junit.Assert.*
import org.junit.Test

/** Generated container vectors, not user photos and not a HEVC decoder test. */
class HeifContainerTest {
    private fun bytes(block: DataOutputStream.() -> Unit): ByteArray = ByteArrayOutputStream().also {
        DataOutputStream(it).use(block)
    }.toByteArray()
    private fun atom(name: String, value: ByteArray, wide: Boolean = false): ByteArray = bytes {
        writeInt(if (wide) 1 else value.size + 8); writeBytes(name)
        if (wide) writeLong(value.size.toLong() + 16)
        write(value)
    }
    private fun vector(wide: Boolean = false, invalidExtent: Boolean = false, width: Int = 32): ByteArray {
        val ftyp = atom("ftyp", bytes { writeBytes("heic"); writeInt(0); writeBytes("mif1") }, wide)
        fun meta(offset: Int) = atom("meta", bytes {
            writeInt(0)
            write(atom("hdlr", bytes { writeInt(0); writeInt(0); writeBytes("pict") }))
            write(atom("pitm", bytes { writeInt(0); writeShort(1) }))
            write(atom("iinf", bytes {
                writeInt(0); writeShort(1)
                write(atom("infe", bytes { writeInt(2 shl 24); writeShort(1); writeShort(0); writeBytes("hvc1"); writeByte(0) }))
            }))
            write(atom("iloc", bytes {
                writeInt(0); writeByte(0x44); writeByte(0); writeShort(1)
                writeShort(1); writeShort(0); writeShort(1)
                writeInt(if (invalidExtent) 0 else offset); writeInt(8)
            }))
            write(atom("iprp", bytes {
                write(atom("ipco", bytes {
                    write(atom("ispe", bytes { writeInt(0); writeInt(width); writeInt(32) }))
                    write(atom("hvcC", ByteArray(23).also { it[0] = 1 }))
                }))
                write(atom("ipma", bytes { writeInt(0); writeInt(1); writeShort(1); writeByte(2); writeByte(1); writeByte(2) }))
            }))
        })
        val metadata = meta(0)
        return ftyp + meta(ftyp.size + metadata.size + 8) + atom("mdat", ByteArray(8) { 1 })
    }
    private fun check(value: ByteArray, expected: Boolean) {
        val file = File.createTempFile("synthetic-heif-container-", ".bin")
        try { file.writeBytes(value); assertEquals(expected, HeifContainer.recognizes(file)) }
        finally { assertTrue(file.delete()) }
    }
    @Test fun ordinaryAnd64BitBoxSizesAreRecognizedWithoutDecoding() {
        check(vector(), true); check(vector(wide = true), true)
    }
    @Test fun noArtificialPixelLimitIsAdded() { check(vector(width = 100_000), true) }
    @Test fun imageExtentsCannotPointIntoMetadataOrOutsideTheFile() {
        check(vector(invalidExtent = true), false); check(vector().dropLast(1).toByteArray(), false)
    }
    @Test fun truncatedAndOversizedBoxHeadersFailClosed() {
        check(byteArrayOf(), false)
        val invalid = vector(wide = true).clone()
        for (i in 8..15) invalid[i] = 0x7f
        check(invalid, false)
    }
    @Test fun anotherCodecBrandCannotMasqueradeAsHeic() {
        val invalid = vector().clone(); "avif".toByteArray().copyInto(invalid, 8)
        check(invalid, false)
    }
    @Test fun boxWorkIsBoundedWithoutLoadingPayloadIntoMemory() {
        val invalid = (1..5000).fold(ByteArray(0)) { data, _ -> data + atom("free", byteArrayOf()) }
        check(invalid, false)
    }
}
