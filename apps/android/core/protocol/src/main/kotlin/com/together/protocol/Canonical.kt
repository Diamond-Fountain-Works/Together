package com.together.protocol

import kotlinx.serialization.json.*
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.Base64
import java.util.Locale
import java.util.UUID

class ProtocolException(val code: String) : IllegalArgumentException(code)
fun requireProtocol(value: Boolean, code: String) { if (!value) throw ProtocolException(code) }
private val graphemes = java.util.regex.Pattern.compile("\\X")
fun String.graphemeCount(): Int { val matcher = graphemes.matcher(this); var n = 0; while (matcher.find()) n++; return n }
fun uid(): String = UUID.randomUUID().toString().uppercase(Locale.ROOT)
fun uuid(value: String): String {
    requireProtocol(Regex("[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}").matches(value), "INVALID_UUID")
    return value
}
fun ByteArray.b64(): String = Base64.getEncoder().encodeToString(this)
fun String.unbase64(): ByteArray = try { Base64.getDecoder().decode(this).also { requireProtocol(it.b64() == this, "INVALID_BASE64") } } catch (_: IllegalArgumentException) { throw ProtocolException("INVALID_BASE64") }
fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
fun validDigest(value: String) = Regex("[0-9a-f]{64}").matches(value)
fun stableId(seed: String): String {
    val b = MessageDigest.getInstance("SHA-256").digest(seed.toByteArray()).copyOf(16)
    b[6] = ((b[6].toInt() and 15) or 0x50).toByte(); b[8] = ((b[8].toInt() and 63) or 0x80).toByte()
    val buf = ByteBuffer.wrap(b)
    return UUID(buf.long, buf.long).toString().uppercase(Locale.ROOT)
}
val wireJson = Json { encodeDefaults = true; explicitNulls = false; ignoreUnknownKeys = true; isLenient = false }
inline fun <reified T> T.json(): JsonElement = wireJson.encodeToJsonElement(this)
inline fun <reified T> JsonElement.model(): T = wireJson.decodeFromJsonElement(this)

/** Foundation sortedKeys/withoutEscapingSlashes, integer milliseconds, UTF-8.
 * Reject duplicate keys, malformed Unicode, fractional/exponent numbers and oversized/deep input.
 * Business decimal strings are not converted to floating point. */
object Canonical {
    fun bytes(value: JsonElement): ByteArray = write(value).toByteArray(Charsets.UTF_8)
    inline fun <reified T> encode(value: T): ByteArray = bytes(value.json())
    fun parse(bytes: ByteArray, maximum: Int = 524_288): JsonElement {
        requireProtocol(bytes.size <= maximum, "FRAME_BOUNDS")
        val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        return Parser(text).parse()
    }
    private fun write(v: JsonElement): String = when (v) {
        is JsonObject -> v.keys.sorted().joinToString(",", "{", "}") { quote(it) + ":" + write(v.getValue(it)) }
        is JsonArray -> v.joinToString(",", "[", "]") { write(it) }
        is JsonNull -> "null"
        is JsonPrimitive -> if (v.isString) quote(v.content) else {
            if (v.content !in listOf("true", "false")) integer(v.content)
            v.content
        }
    }
    private fun integer(v: String) {
        requireProtocol(Regex("0|-?[1-9][0-9]*").matches(v), "NON_INTEGER_NUMBER")
        requireProtocol(v.toLongOrNull()?.let { it > -9_000_000_000_000_000L && it < 9_000_000_000_000_000L } == true, "INTEGER_BOUNDS")
    }
    private fun quote(s: String): String {
        val out = StringBuilder("\"")
        var i = 0
        while (i < s.length) {
            val c = s[i++]
            when (c) {
                '"' -> out.append("\\\""); '\\' -> out.append("\\\\"); '\b' -> out.append("\\b")
                '\u000c' -> out.append("\\f"); '\n' -> out.append("\\n"); '\r' -> out.append("\\r"); '\t' -> out.append("\\t")
                else -> when {
                    c.code < 32 -> out.append("\\u%04x".format(c.code))
                    c.isHighSurrogate() -> { requireProtocol(i < s.length && s[i].isLowSurrogate(), "INVALID_UNICODE"); out.append(c).append(s[i++]) }
                    c.isLowSurrogate() -> throw ProtocolException("INVALID_UNICODE")
                    else -> out.append(c)
                }
            }
        }
        return out.append('"').toString()
    }
    private class Parser(val text: String) {
        var p = 0
        fun parse(): JsonElement { val v = value(0); ws(); requireProtocol(p == text.length, "INVALID_JSON"); return v }
        fun ws() { while (p < text.length && text[p] in " \n\r\t") p++ }
        fun take(c: Char): Boolean { ws(); if (p < text.length && text[p] == c) { p++; return true }; return false }
        fun value(depth: Int): JsonElement {
            requireProtocol(depth < 64, "JSON_DEPTH"); ws(); requireProtocol(p < text.length, "INVALID_JSON")
            return when (text[p]) {
                '{' -> {
                    p++; val m = linkedMapOf<String, JsonElement>()
                    if (!take('}')) do {
                        val k = string(); requireProtocol(k !in m, "DUPLICATE_KEY"); requireProtocol(take(':'), "INVALID_JSON")
                        m[k] = value(depth + 1)
                        if (take('}')) break
                        requireProtocol(take(','), "INVALID_JSON")
                    } while (true)
                    JsonObject(m)
                }
                '[' -> {
                    p++; val a = mutableListOf<JsonElement>()
                    if (!take(']')) do {
                        a.add(value(depth + 1)); if (take(']')) break; requireProtocol(take(','), "INVALID_JSON")
                    } while (true)
                    JsonArray(a)
                }
                '"' -> JsonPrimitive(string())
                else -> {
                    val start = p
                    while (p < text.length && text[p] !in ",]} \t\r\n") p++
                    val token = text.substring(start, p)
                    when (token) { "null" -> JsonNull; "true" -> JsonPrimitive(true); "false" -> JsonPrimitive(false)
                        else -> { integer(token); JsonPrimitive(token.toLong()) } }
                }
            }
        }
        fun string(): String {
            ws(); requireProtocol(p < text.length && text[p] == '"', "INVALID_JSON")
            val start = p++
            while (p < text.length) {
                val c = text[p++]
                if (c == '\\') { requireProtocol(p < text.length, "INVALID_JSON"); p++ }
                else if (c == '"') {
                    val s = wireJson.parseToJsonElement(text.substring(start, p)).jsonPrimitive.content
                    quote(s) // validate surrogate pairs
                    return s
                }
            }
            throw ProtocolException("INVALID_JSON")
        }
    }
}
