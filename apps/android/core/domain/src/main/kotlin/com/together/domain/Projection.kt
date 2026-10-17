package com.together.domain

import com.together.protocol.*
import kotlinx.serialization.json.*
import java.time.Instant
import java.time.ZoneId

fun Map<String, JsonObject>.text(key: String) = LogValue.string(this[key])
fun Map<String, JsonObject>.number(key: String) = LogValue.long(this[key])
fun Map<String, JsonObject>.date(key: String) = LogValue.long(this[key], "date")
fun Map<String, JsonObject>.bool(key: String) = LogValue.value(this[key], "boolean")?.booleanOrNull
fun Map<String, JsonObject>.data(key: String): JsonElement = Canonical.parse(LogValue.bytes(this[key]) ?: throw ProtocolException("MISSING_DOMAIN_FIELD"), 16_384)
fun Map<String, JsonObject>.optionalData(key: String) = if (this[key] == null || this[key] == LogValue.nil) null else data(key)
fun Map<String, JsonObject>.id(key: String): String? = text(key)?.let(::uuid)
fun textValid(v: JsonObject?, max: Int, nonempty: Boolean = false): Boolean = LogValue.string(v)?.let { it.graphemeCount() <= max && (!nonempty || it.isNotBlank()) } == true

data class DomainContext(val spaceId: String, val members: Set<String>, val aliases: Set<String>, val zone: String, val creatorId: String) {
    companion object { fun from(t: SpaceAuthorization) = t.archive.genesis.body.let { DomainContext(t.spaceId, t.members, it.legacySpaceIds.toSet(), it.sharedTimeZoneIdentifier, it.roots.minBy { r -> r.deviceId }.userId) } }
}
data class Conflict(val operationId: String, val entityId: String, val reason: String)
data class ChangeEvent(val operationId: String, val entityId: String, val entityType: String, val actorId: String, val deviceId: String,
    val action: String, val before: Map<String, JsonObject>, val after: Map<String, JsonObject>, val resolution: String = "effective", val createdAt: Long = 0)
data class ProjectedEntity(val base: SyncOperation, val fields: Map<String, JsonObject>, val deletedAt: Long? = null) {
    val id get() = base.entityId
}
data class Wish(val id: String, val grantId: String, val beneficiary: String, val fulfiller: String,
    var title: String, var description: String, var status: String, var fulfilledAt: Long? = null)
data class Gift(val entity: ProjectedEntity, val effective: Boolean) { val id get() = entity.id }
data class Snapshot(val entities: MutableMap<String, ProjectedEntity> = linkedMapOf(), val wishes: MutableMap<String, Wish> = linkedMapOf(),
    val grantTotals: MutableMap<String, Long> = linkedMapOf(), val gifts: MutableMap<String, Gift> = linkedMapOf(),
    val conflicts: MutableList<Conflict> = mutableListOf(), val changes: MutableList<ChangeEvent> = mutableListOf()) {
    fun of(type: String) = entities.values.filter { it.base.entityType == type }
    fun remaining(grantId: String): Long = (grantTotals[grantId] ?: 0) - wishes.values.count { it.grantId == grantId && it.status == "fulfilled" }
    fun giftUsed(sender: String, day: String) = gifts.values.any { it.effective && it.entity.fields.text("senderId") == sender && it.entity.fields.text("sentDayKey") == day }
}
internal class Draft(val base: SyncOperation) {
    val fields = base.payload.toMutableMap(); val orders = base.payload.keys.associateWith { base }.toMutableMap()
    var last = base; var deletedAt: Long? = null
    fun assign(key: String, value: JsonObject, op: SyncOperation) {
        if (orders[key]?.let { it < op } != false) { fields[key] = value; orders[key] = op }
        if (last < op) last = op
    }
    fun entity() = ProjectedEntity(base, fields.toMap(), deletedAt)
}
object Projector {
    fun replay(signed: List<SignedOperation>, context: DomainContext): Snapshot {
        val result = Snapshot(); val unique = signed.groupBy { it.operation.operationId }
        unique.values.forEach { rows -> requireProtocol(rows.distinct().size == 1, "CONTENT_COLLISION") }
        // Caller supplies only cryptographically verified and authorized accepted records.
        val ops = unique.values.map { it.first().operation }.sorted()
        requireProtocol(ops.all { it.actorId in context.members }, "UNAUTHORIZED_ACTOR")
        val drafts = mutableMapOf<String, Draft>()
        fun conflict(op: SyncOperation, code: String) { result.conflicts.add(Conflict(op.operationId, op.entityId, code)) }
        for (op in ops.filter { it.operationType == "create" && it.entityType in setOf("profile", "task", "recurrenceRule") }) {
            if (op.entityId in drafts) continue
            if (runCatching { requireProtocol(simpleValid(op, op.payload, context, true), "INVALID_RECORD") }.isSuccess) {
                drafts[op.entityId] = Draft(op); record(result, op, emptyMap(), op.payload)
            } else conflict(op, "INVALID_CREATE")
        }
        for (op in ops.filter { it.entityType in setOf("profile", "task", "recurrenceRule") && it.operationType != "create" }) {
            val d = drafts[op.entityId] ?: continue
            if (op.entityType != d.base.entityType) continue
            if (op.entityType == "profile" && op.actorId != op.entityId) { conflict(op, "PROFILE_OWNER_ONLY"); continue }
            val before = d.fields.toMap() + ("deletedAt" to (d.deletedAt?.let(LogValue::date) ?: LogValue.nil))
            when {
                op.entityType == "task" && op.operationType == "delete" -> d.deletedAt = d.deletedAt ?: op.createdAt
                op.entityType == "task" && op.operationType in setOf("completeTask", "reopenTask") -> {
                    d.assign("status", LogValue.string(if (op.operationType == "completeTask") "completed" else "pending"), op)
                    d.assign("completedAt", if (op.operationType == "completeTask") LogValue.date(op.createdAt) else LogValue.nil, op)
                }
                op.operationType == "patch" && runCatching { simpleValid(op, op.payload, context, false) }.getOrDefault(false) -> op.payload.forEach { (k, v) -> d.assign(k, v, op) }
                else -> { conflict(op, "INVALID_PATCH"); continue }
            }
            record(result, op, before, d.fields.toMap() + ("deletedAt" to (d.deletedAt?.let(LogValue::date) ?: LogValue.nil)))
        }
        drafts.values.forEach { result.entities[it.base.entityId] = it.entity() }
        wishes(ops, context, result); gifts(ops, context, result); FinanceProjection.apply(ops, context, result)
        val invalid = result.conflicts.map { it.operationId }.toSet()
        result.changes.removeAll { it.operationId in invalid || it.entityType in setOf("mediaAsset", "sharedSpace") || (it.entityType == "recurrenceRule" && it.action == "create") || (it.entityType == "wishItem" && result.wishes[it.entityId]?.status == "conflict") }
        val order = ops.associateBy { it.operationId }; val winners = mutableSetOf<String>()
        val reviewed = result.changes.sortedByDescending { order.getValue(it.operationId) }.map { e ->
            val fields = (e.before.keys + e.after.keys).filter { e.before[it] != e.after[it] }
            val replaced = fields.count { "${e.entityType}:${e.entityId}:$it" in winners }
            fields.forEach { winners.add("${e.entityType}:${e.entityId}:$it") }
            e.copy(resolution = if (e.action == "create" || replaced == 0) "effective" else if (replaced == fields.size) "superseded" else "partiallySuperseded")
        }
        result.changes.clear(); result.changes.addAll(reviewed.asReversed())
        result.conflicts.sortBy { it.operationId }
        return result
    }
    internal fun record(s: Snapshot, op: SyncOperation, before: Map<String, JsonObject>, after: Map<String, JsonObject>) {
        if (before != after) {
            // Gift content remains sealed in change history. No private text/attachment payload leaks.
            val b = if (op.entityType == "loveGift") emptyMap() else before
            val a = if (op.entityType == "loveGift") mapOf("status" to LogValue.string(op.operationType)) else after
            s.changes.add(ChangeEvent(op.operationId, op.entityId, op.entityType, op.actorId, op.deviceId, op.operationType, b, a, createdAt = op.createdAt))
        }
    }
    internal fun space(p: Map<String, JsonObject>, c: DomainContext) = p.id("spaceId") in c.aliases
    private fun simpleValid(op: SyncOperation, p: Map<String, JsonObject>, c: DomainContext, create: Boolean): Boolean {
        if (create) {
            when (op.entityType) {
                "profile" -> if (op.entityId != op.actorId || p.id("deviceId") != op.deviceId || !textValid(p["displayName"], 80, true) || (LogValue.bytes(p["avatarData"])?.size ?: 0) > 131_072) return false
                "task" -> if (!space(p, c) || p.id("createdBy") != op.actorId || !textValid(p["title"], 200, true) || !textValid(p["notes"] ?: LogValue.string(""), 10_000)) return false
                "recurrenceRule" -> if (!space(p, c) || p.id("createdBy") != op.actorId || !p.keys.containsAll(setOf("mode", "unit", "interval", "anchorAt", "timeZoneIdentifier"))) return false
            }
        } else {
            val allowed = when (op.entityType) {
                "profile" -> setOf("displayName", "relationshipLabel", "avatarData", "avatarAssetId", "avatarCrop")
                "task" -> setOf("title", "notes", "assignedTo", "dueAt", "recurrenceRuleId", "nextAt", "availableAt")
                "recurrenceRule" -> setOf("mode", "unit", "interval", "anchorAt", "timeZoneIdentifier")
                else -> emptySet()
            }
            if (!allowed.containsAll(p.keys)) return false
        }
        for ((k, v) in p) when (k) {
            "title" -> if (!textValid(v, 200, true)) return false
            "notes" -> if (!textValid(v, 10_000)) return false
            "displayName" -> if (!textValid(v, 80, true)) return false
            "relationshipLabel" -> if (!textValid(v, 40)) return false
            "assignedTo" -> if (v != LogValue.nil && p.id(k) !in c.members) return false
            "avatarAssetId", "recurrenceRuleId" -> if (v != LogValue.nil && p.id(k) == null) return false
            "dueAt", "nextAt", "availableAt" -> if (v != LogValue.nil && p.date(k) == null) return false
            "occurrenceIndex" -> if (p.number(k) !in 0..1_000_000L) return false
            "mode" -> if (p.text(k) !in setOf("regular", "flexible")) return false
            "unit" -> if (p.text(k) !in setOf("day", "week", "month")) return false
            "interval" -> if (p.number(k) !in 1..1000L) return false
            "anchorAt" -> if (p.date(k) == null) return false
            "timeZoneIdentifier" -> ZoneId.of(p.text(k) ?: return false)
            "avatarData" -> if (v != LogValue.nil && (LogValue.bytes(v)?.size ?: Int.MAX_VALUE) > 131_072) return false
            "avatarCrop" -> if (v != LogValue.nil) {
                val bytes = LogValue.bytes(v) ?: return false
                if (bytes.size >= 1024) return false
                val crop = wireJson.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
                // Crop JSON may use fractional numbers. It is opaque signed data; validation
                // is delegated until native original-image UI is implemented in the next phase.
                val x = crop["horizontal"]?.jsonPrimitive?.doubleOrNull ?: return false
                val y = crop["vertical"]?.jsonPrimitive?.doubleOrNull ?: return false
                val scale = crop["zoom"]?.jsonPrimitive?.doubleOrNull ?: return false
                if (!x.isFinite() || !y.isFinite() || !scale.isFinite() || x !in 0.0..1.0 || y !in 0.0..1.0 || scale !in 1.0..4.0) return false
            }
        }
        return true
    }
    private fun wishes(ops: List<SyncOperation>, c: DomainContext, s: Snapshot) {
        fun bad(op: SyncOperation) { s.conflicts.add(Conflict(op.operationId, op.entityId, "INVALID_WISH_OPERATION")) }
        for (op in ops.filter { it.entityType == "wishGrant" && it.operationType == "create" }) {
            if (op.entityId in s.entities) continue
            val p = op.payload
            val valid = runCatching { space(p, c) && p.id("createdBy") == op.actorId && p.id("fulfillerId") in c.members && p.id("beneficiaryId") in c.members && p.id("fulfillerId") != p.id("beneficiaryId") && p.number("quantity") in 1..10_000L && CivilDate.parse(p.text("grantedOn")!!).iso.isNotEmpty() }.getOrDefault(false)
            if (!valid) { bad(op); continue }
            s.entities[op.entityId] = ProjectedEntity(op, p); s.grantTotals[op.entityId] = p.number("quantity")!!; record(s, op, emptyMap(), p)
        }
        val occupied = mutableMapOf<String, MutableSet<String>>(); val deferred = mutableMapOf<String, MutableList<SyncOperation>>()
        fun action(op: SyncOperation) {
            val wish = s.wishes[op.entityId] ?: return
            if (wish.status == "conflict") { bad(op); return }
            val before = mapOf("title" to LogValue.string(wish.title), "description" to LogValue.string(wish.description), "status" to LogValue.string(wish.status))
            when (op.operationType) {
                "patch" -> {
                    if (op.actorId != wish.beneficiary || wish.status == "fulfilled" || !setOf("title", "description").containsAll(op.payload.keys)) { bad(op); return }
                    if (op.payload["title"] != null) { if (!textValid(op.payload["title"], 200, true)) { bad(op); return }; wish.title = op.payload.text("title")!! }
                    if (op.payload["description"] != null) { if (!textValid(op.payload["description"], 10_000)) { bad(op); return }; wish.description = op.payload.text("description")!! }
                }
                "requestFulfillment" -> if (op.actorId == wish.fulfiller) { if (wish.status != "fulfilled") wish.status = "completionRequested" } else { bad(op); return }
                "confirmFulfillment" -> if (op.actorId == wish.beneficiary && wish.status in setOf("fulfilled", "completionRequested")) { if (wish.status != "fulfilled") { wish.status = "fulfilled"; wish.fulfilledAt = op.createdAt } } else { bad(op); return }
                "rejectFulfillment" -> if (op.actorId == wish.beneficiary) { if (wish.status != "fulfilled") wish.status = "open" } else { bad(op); return }
                else -> { bad(op); return }
            }
            record(s, op, before, mapOf("title" to LogValue.string(wish.title), "description" to LogValue.string(wish.description), "status" to LogValue.string(wish.status)))
        }
        for (op in ops) when (op.entityType) {
            "grantAdjustment" -> {
                val p = op.payload; val grant = p.id("grantId")?.let(s.entities::get)
                val delta = p.number("delta")
                if (op.operationType != "create" || grant == null || grant.base.actorId != op.actorId || delta == null || delta == 0L || delta !in -10_000..10_000L || !textValid(p["notes"], 5000, true)) { bad(op); continue }
                if (op.entityId in s.entities) continue
                val total = s.grantTotals.getValue(grant.id) + delta
                val effective = total >= (occupied[grant.id]?.size ?: 0) && total >= 0
                s.entities[op.entityId] = ProjectedEntity(op, p + ("effective" to LogValue.bool(effective)))
                if (effective) { s.grantTotals[grant.id] = total; record(s, op, emptyMap(), p) } else bad(op)
            }
            "wishItem" -> if (op.operationType == "create") {
                if (op.entityId in s.wishes) continue
                val p = op.payload; val grantId = p.id("grantId"); val grant = grantId?.let(s.entities::get)
                if (grant == null || grant.base.entityType != "wishGrant" || grant.fields.id("beneficiaryId") != op.actorId || p.id("createdBy") != op.actorId || !textValid(p["title"], 200, true) || !textValid(p["description"] ?: LogValue.string(""), 10_000)) { bad(op); continue }
                val effective = (occupied[grantId]?.size ?: 0) < s.grantTotals.getValue(grantId)
                val wish = Wish(op.entityId, grantId, op.actorId, grant.fields.id("fulfillerId")!!, p.text("title")!!, p.text("description") ?: "", if (effective) "open" else "conflict")
                s.wishes[op.entityId] = wish
                if (effective) { occupied.getOrPut(grantId) { mutableSetOf() }.add(op.entityId); record(s, op, emptyMap(), p) } else bad(op)
                deferred.remove(op.entityId)?.forEach(::action)
            } else if (op.entityId in s.wishes) action(op) else deferred.getOrPut(op.entityId) { mutableListOf() }.add(op)
        }
        deferred.values.flatten().forEach(::bad)
    }
    private fun gifts(ops: List<SyncOperation>, c: DomainContext, s: Snapshot) {
        var zone = c.zone
        for (op in ops.filter { it.entityType == "sharedSpace" }) {
            val value = op.payload.text("sharedTimeZoneIdentifier")
            if (op.operationType == "create" && op.entityId == c.spaceId && op.actorId == c.creatorId && value != null && s.entities[op.entityId] == null && runCatching { ZoneId.of(value) }.isSuccess) {
                zone = value; s.entities[op.entityId] = ProjectedEntity(op, op.payload)
            }
        }
        for (op in ops.filter { it.entityType == "mediaAsset" }) {
            val p = op.payload
            if (runCatching { op.operationType == "create" && space(p, c) && p.id("ownerId") == op.actorId && p.text("mediaType") in setOf("avatar", "audio", "photo") && (p.text("originalFilename")?.length ?: 256) <= 255 && p.text("fileExtension") in setOf("jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "m4a", "aac", "mp3", "wav", "aiff", "aif", "caf", "flac") && validDigest(p.text("sha256") ?: "") && (p.number("byteCount") ?: 0) > 0 }.getOrDefault(false)) {
                val old = s.entities[op.entityId]
                if (old == null) s.entities[op.entityId] = ProjectedEntity(op, p) else if (old.fields != p) s.conflicts.add(Conflict(op.operationId, op.entityId, "MEDIA_ID_COLLISION"))
            } else s.conflicts.add(Conflict(op.operationId, op.entityId, "INVALID_MEDIA_MANIFEST"))
        }
        val slots = mutableSetOf<String>()
        for (op in ops.filter { it.entityType == "loveGift" && it.operationType == "create" }) {
            val p = op.payload; val text = p.text("textContent")?.trim().orEmpty()
            fun asset(key: String, type: String): Boolean {
                if (p[key] == null || p[key] == LogValue.nil) return true
                val id = p.id(key) ?: return false; val media = s.entities[id] ?: return false
                return media.base.entityType == "mediaAsset" && media.fields.text("mediaType") == type && media.fields.id("ownerId") == op.actorId
            }
            val valid = runCatching { p.id("spaceId") == c.spaceId && p.id("senderId") == op.actorId && p.id("recipientId") in c.members && p.id("recipientId") != op.actorId && p.date("sentAt") != null && p.text("sharedTimeZoneIdentifier") == zone && dayKey(Instant.ofEpochMilli(p.date("sentAt")!!), zone) == p.text("sentDayKey") && text.graphemeCount() <= 4000 && text.toByteArray().size <= 16_000 && (text.isNotEmpty() || p.id("audioAssetId") != null || p.id("photoAssetId") != null) && asset("audioAssetId", "audio") && asset("photoAssetId", "photo") && (p["replyToGiftId"] == null || p["replyToGiftId"] == LogValue.nil || p.id("replyToGiftId") != null) }.getOrDefault(false)
            if (!valid || op.entityId in s.gifts) { s.conflicts.add(Conflict(op.operationId, op.entityId, "INVALID_GIFT")); continue }
            val effective = slots.add("${c.spaceId}:${op.actorId}:${p.text("sentDayKey")}")
            val gift = Gift(ProjectedEntity(op, p), effective); s.gifts[op.entityId] = gift
            if (!effective) s.conflicts.add(Conflict(op.operationId, op.entityId, "DAILY_QUOTA_CONFLICT")) else record(s, op, emptyMap(), p)
        }
        for (op in ops.filter { it.entityType == "loveGift" && it.operationType != "create" }) {
            val gift = s.gifts[op.entityId]
            if (op.operationType == "delete" && gift?.entity?.base?.actorId == op.actorId) {
                s.gifts[op.entityId] = gift.copy(entity = gift.entity.copy(deletedAt = gift.entity.deletedAt ?: op.createdAt)); record(s, op, gift.entity.fields, emptyMap())
            } else s.conflicts.add(Conflict(op.operationId, op.entityId, "INVALID_GIFT_DELETE"))
        }
    }
}
