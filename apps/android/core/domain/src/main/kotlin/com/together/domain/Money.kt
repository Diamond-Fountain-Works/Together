package com.together.domain

import com.together.protocol.*
import kotlinx.serialization.json.*
import java.math.BigDecimal
import java.math.RoundingMode

object Money {
    const val MAX_MINOR = 90_000_000_000_000L
    val currencies: Map<String, JsonObject> by lazy {
        val resource=Money::class.java.getResourceAsStream("/FinanceCurrencies.json")?:error("Missing bundled ISO currencies")
        wireJson.parseToJsonElement(resource.bufferedReader().use{it.readText()}).jsonObject.getValue("currencies").jsonArray.associate{it.jsonObject.getValue("code").jsonPrimitive.content to it.jsonObject}
    }
    val precisions: Map<String,Int> by lazy { currencies.mapValues{it.value.getValue("minorDigits").jsonPrimitive.int} }
    fun decimal(text: String): BigDecimal {
        val s = text.trim(); requireProtocol(s.length <= 64 && Regex("[+-]?[0-9]+(?:\\.[0-9]+)?").matches(s), "INVALID_AMOUNT")
        return BigDecimal(s)
    }
    fun minor(text: String, currency: String, round: Boolean = false): Long {
        val digits = precisions[currency] ?: throw ProtocolException("INVALID_CURRENCY")
        val scaled = decimal(text).setScale(digits, if (round) RoundingMode.HALF_UP else RoundingMode.UNNECESSARY).movePointRight(digits).longValueExact()
        requireProtocol(scaled in -MAX_MINOR..MAX_MINOR, "AMOUNT_BOUNDS"); return scaled
    }
    fun string(minor: Long, currency: String = "CNY") = BigDecimal.valueOf(minor, precisions[currency] ?: throw ProtocolException("INVALID_CURRENCY")).toPlainString()
    fun sum(values: Iterable<Long>) = values.fold(0L, Math::addExact)
}
data class Amount(val currencyCode: String, val originalMinor: Long, val finalCNYMinor: Long,
    val settlementBasis: String = "actualCNY", val exchangeRate: JsonObject? = null) {
    fun validate() {
        requireProtocol(currencyCode in Money.precisions && originalMinor in -Money.MAX_MINOR..Money.MAX_MINOR && finalCNYMinor in -Money.MAX_MINOR..Money.MAX_MINOR && (originalMinor >= 0) == (finalCNYMinor >= 0) && (currencyCode != "CNY" || originalMinor == finalCNYMinor) && settlementBasis in setOf("actualCNY", "referenceRate"), "INVALID_AMOUNT")
        exchangeRate?.let { r ->
            val rate = Money.decimal(r.getValue("cnyPerOriginalUnit").jsonPrimitive.content)
            val source = r.getValue("source").jsonPrimitive.content
            CivilDate.from(r.getValue("quotedOn"))
            requireProtocol(rate.signum() > 0 && source.isNotEmpty() && source.length <= 120, "INVALID_RATE")
            if (settlementBasis == "referenceRate") requireProtocol(Money.minor(BigDecimal(Money.string(originalMinor, currencyCode)).multiply(rate).toPlainString(), "CNY", true) == finalCNYMinor, "SETTLEMENT_MISMATCH")
        }
        requireProtocol(exchangeRate != null || settlementBasis != "referenceRate", "MISSING_RATE")
    }
    fun json(): JsonObject = buildJsonObject {
        put("currencyCode", currencyCode); put("originalMinor", originalMinor.toString()); put("finalCNYMinor", finalCNYMinor.toString()); put("settlementBasis", settlementBasis); exchangeRate?.let { put("exchangeRate", it) }
    }
    companion object {
        fun create(original: String, currency: String = "CNY", actualCNY: String? = null, exchangeRate: JsonObject? = null): Amount {
            val originalMinor = Money.minor(original, currency)
            val basis = if (currency == "CNY" || !actualCNY.isNullOrBlank()) "actualCNY" else "referenceRate"
            val cny = if (currency == "CNY") originalMinor else if (!actualCNY.isNullOrBlank()) Money.minor(actualCNY, "CNY", true)
                else Money.minor(Money.decimal(original).multiply(Money.decimal(exchangeRate?.get("cnyPerOriginalUnit")?.jsonPrimitive?.content ?: throw ProtocolException("MISSING_SETTLEMENT"))).toPlainString(), "CNY", true)
            return Amount(currency, originalMinor, cny, basis, exchangeRate).also { it.validate() }
        }
        fun from(v: JsonElement): Amount {
            val o = v.jsonObject
            requireProtocol(o.getValue("originalMinor").jsonPrimitive.isString && o.getValue("finalCNYMinor").jsonPrimitive.isString, "MONEY_MUST_BE_STRING")
            return Amount(o.getValue("currencyCode").jsonPrimitive.content, o.getValue("originalMinor").jsonPrimitive.content.toLong(), o.getValue("finalCNYMinor").jsonPrimitive.content.toLong(), o.getValue("settlementBasis").jsonPrimitive.content, o["exchangeRate"] as? JsonObject).also { it.validate() }
        }
    }
}
data class Payment(val kind: String, val userIds: List<String>, val paymentMethodId: String? = null) {
    fun validate(members: Set<String>) {
        userIds.forEach(::uuid); paymentMethodId?.let(::uuid)
        requireProtocol(userIds.distinct().size == userIds.size && userIds.all { it in members } && when (kind) { "reserves" -> userIds.isEmpty(); "personal" -> userIds.size == 1; "equalSplit" -> userIds.size == 2; else -> false }, "INVALID_PAYMENT")
    }
    fun allocations(amount: Long): Map<String, Long> {
        if (kind == "reserves") return emptyMap()
        requireProtocol(amount >= 0 && userIds.isNotEmpty(), "INVALID_EXPENSE_AMOUNT")
        val n = userIds.size
        return userIds.sorted().mapIndexed { i, id -> id to (amount / n + if (i < amount % n) 1 else 0) }.toMap()
    }
    fun json() = buildJsonObject { put("kind", kind); put("userIds", JsonArray(userIds.sorted().map(::JsonPrimitive))); paymentMethodId?.let { put("paymentMethodId", it) } }
    companion object { fun from(v: JsonElement) = v.jsonObject.let { Payment(it.getValue("kind").jsonPrimitive.content, it.getValue("userIds").jsonArray.map { u -> u.jsonPrimitive.content }, it["paymentMethodId"]?.jsonPrimitive?.content) } }
}
