package com.together.domain

import com.together.protocol.*
import kotlinx.serialization.json.*
import java.time.*

fun interface DateProvider { fun now(): Instant }
val systemDateProvider = DateProvider { Instant.now() }
data class CivilDate(val year: Int, val month: Int, val day: Int) : Comparable<CivilDate> {
    init { requireProtocol(year in 1900..3000, "INVALID_DATE"); LocalDate.of(year, month, day) }
    val local get() = LocalDate.of(year, month, day)
    val iso get() = local.toString()
    fun json() = buildJsonObject { put("year", year); put("month", month); put("day", day) }
    override fun compareTo(other: CivilDate) = local.compareTo(other.local)
    companion object {
        fun from(v: JsonElement) = v.jsonObject.let { CivilDate(it.getValue("year").jsonPrimitive.int, it.getValue("month").jsonPrimitive.int, it.getValue("day").jsonPrimitive.int) }
        fun parse(s: String) = LocalDate.parse(s).let { CivilDate(it.year, it.monthValue, it.dayOfMonth) }.also { requireProtocol(it.iso == s, "INVALID_DATE") }
    }
}
data class FinanceMonth(val year: Int, val month: Int) : Comparable<FinanceMonth> {
    init { requireProtocol(year in 1900..3000 && month in 1..12, "INVALID_MONTH") }
    val ym get() = YearMonth.of(year, month)
    val iso get() = ym.toString()
    val next get() = ym.plusMonths(1).let { FinanceMonth(it.year, it.monthValue) }
    fun json() = buildJsonObject { put("year", year); put("month", month) }
    override fun compareTo(other: FinanceMonth) = ym.compareTo(other.ym)
    companion object {
        fun at(date: Instant, zone: String) = date.atZone(ZoneId.of(zone)).let { FinanceMonth(it.year, it.monthValue) }
        fun from(v: JsonElement) = v.jsonObject.let { FinanceMonth(it.getValue("year").jsonPrimitive.int, it.getValue("month").jsonPrimitive.int) }
        fun parse(s: String) = YearMonth.parse(s).let { FinanceMonth(it.year, it.monthValue) }
    }
}
object FinancialCalendar {
    fun day(month: FinanceMonth, requested: Int, zone: String): CivilDate {
        ZoneId.of(zone); requireProtocol(requested in 1..31, "INVALID_DAY")
        return CivilDate(month.year, month.month, minOf(requested, month.ym.lengthOfMonth()))
    }
    fun instant(day: CivilDate, zone: String, minuteOfDay: Int? = null): Instant {
        val z = ZoneId.of(zone); if (minuteOfDay == null) return day.local.atStartOfDay(z).toInstant()
        requireProtocol(minuteOfDay in 0..1439, "INVALID_MINUTE")
        val local = day.local.atTime(minuteOfDay / 60, minuteOfDay % 60)
        val offsets = z.rules.getValidOffsets(local)
        // Calendar matchingPolicy.nextTime selects the first valid time after a DST gap,
        // not java.time's default minute-preserving shift through that gap.
        if (offsets.isEmpty()) return z.rules.getTransition(local).dateTimeAfter.atZone(z).toInstant()
        return ZonedDateTime.ofLocal(local, z, offsets.first()).toInstant()
    }
    fun cycle(date: Instant, startDay: Int, zone: String): Pair<Instant, Instant> {
        val current = FinanceMonth.at(date, zone)
        val anchor = instant(day(current, startDay, zone), zone)
        val m = if (date < anchor) current.ym.minusMonths(1).let { FinanceMonth(it.year, it.monthValue) } else current
        return instant(day(m, startDay, zone), zone) to instant(day(m.next, startDay, zone), zone)
    }
}
object Recurrence {
    fun instanceId(ruleId: String, index: Int) = stableId("recurrence:${uuid(ruleId)}:$index")
    fun flexibleId(parentId: String) = stableId("flexible-next:${uuid(parentId)}")
    fun date(anchor: Instant, unit: String, interval: Int, index: Int, zone: String, mode: String = "regular"): Instant? {
        requireProtocol(interval in 1..1000 && index in 0..1_000_000 && unit in setOf("day", "week", "month"), "INVALID_RECURRENCE")
        if (mode == "flexible") return null
        requireProtocol(mode == "regular", "INVALID_RECURRENCE")
        val base = anchor.atZone(ZoneId.of(zone)); val n = Math.multiplyExact(interval.toLong(), index.toLong())
        val target = when (unit) { "day" -> base.toLocalDateTime().plusDays(n); "week" -> base.toLocalDateTime().plusWeeks(n); else -> base.toLocalDateTime().plusMonths(n) }
        // Standard Calendar day/week arithmetic maintains local time across DST.
        return target.atZone(ZoneId.of(zone)).toInstant()
    }
}
fun dayKey(at: Instant, zone: String) = at.atZone(ZoneId.of(zone)).toLocalDate().toString()
fun occurrenceId(billId: String, month: FinanceMonth) = stableId("finance-bill:${uuid(billId)}:${month.iso}")
