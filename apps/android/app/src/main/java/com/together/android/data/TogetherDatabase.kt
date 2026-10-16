package com.together.android.data

import android.content.Context
import androidx.room.*
import com.together.protocol.*

@Entity(tableName = "operations", indices = [Index(value = ["accepted", "id"]), Index(value = ["epoch", "sequence"]), Index(value = ["entityId", "lamport"])])
data class OperationRow(@PrimaryKey val id: String, val deviceId: String, val entityId: String, val lamport: Long, val sequence: Long?, val epoch: String?, val accepted: Boolean, val bytes: ByteArray)
@Entity(tableName = "local_records") data class LocalRow(@PrimaryKey val key: String, val bytes: ByteArray)
@Entity(tableName = "inventory_cache", primaryKeys = ["snapshotId", "cursor"]) data class InventoryRow(val snapshotId: String, val cursor: String, val bytes: ByteArray)
@Dao interface TogetherDao {
    @Query("SELECT * FROM operations WHERE id = :id") fun get(id: String): OperationRow?
    @Query("SELECT * FROM operations WHERE epoch = :epoch AND sequence = :sequence ORDER BY id") fun sequence(epoch: String, sequence: Long): List<OperationRow>
    @Insert(onConflict = OnConflictStrategy.REPLACE) fun put(row: OperationRow)
    @Query("SELECT * FROM operations WHERE (:after IS NULL OR id > :after) AND (:acceptedOnly = 0 OR accepted = 1) ORDER BY id LIMIT :limit") fun rows(after: String?, limit: Int, acceptedOnly: Boolean): List<OperationRow>
    @Query("SELECT * FROM local_records WHERE `key` = :key") fun local(key: String): LocalRow?
    @Insert(onConflict = OnConflictStrategy.REPLACE) fun local(row: LocalRow)
    @Query("DELETE FROM local_records WHERE `key` = :key") fun removeLocal(key: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) fun snapshot(row: InventoryRow)
    @Query("SELECT * FROM inventory_cache WHERE snapshotId = :id AND cursor = :cursor") fun snapshot(id: String, cursor: String): InventoryRow?
    @Query("DELETE FROM inventory_cache WHERE snapshotId = :id") fun clearSnapshot(id: String)
    @Query("DELETE FROM inventory_cache") fun clearSnapshots()
    @Query("SELECT COUNT(*) FROM operations") fun count(): Int
}
@Database(entities = [OperationRow::class, LocalRow::class, InventoryRow::class], version = 1, exportSchema = true)
abstract class TogetherDatabase : RoomDatabase() {
    abstract fun dao(): TogetherDao
    companion object {
        fun open(context: Context, name: String = "together-local.db") = Room.databaseBuilder(context, TogetherDatabase::class.java, name)
            .setJournalMode(JournalMode.WRITE_AHEAD_LOGGING)
            .addCallback(object : Callback() {
                override fun onOpen(db: androidx.sqlite.db.SupportSQLiteDatabase) { db.execSQL("PRAGMA synchronous=FULL") }
            }).build()
    }
}
class RoomReplicaStore(private val db: TogetherDatabase) : ReplicaStore {
    private val dao get() = db.dao()
    override fun <T> transaction(block: () -> T): T = db.runInTransaction(java.util.concurrent.Callable { block() })
    override fun get(id: String) = dao.get(id)?.decode()
    override fun sequence(epoch: String, sequence: Long) = dao.sequence(epoch, sequence).map { it.decode() }
    override fun put(row: StoredRecord) {
        val op = row.record.operation.operation
        dao.put(OperationRow(row.id, op.deviceId, op.entityId, op.lamportClock, row.record.authorized?.body?.sequence, row.record.authorized?.body?.epochId, row.accepted, Canonical.encode(row.record)))
    }
    override fun rows(after: String?, limit: Int, acceptedOnly: Boolean): List<StoredRecord> {
        requireProtocol(limit in 1..256, "QUERY_BOUNDS"); return dao.rows(after, limit, acceptedOnly).map { it.decode() }
    }
    override fun local(key: String) = dao.local(key)?.bytes
    override fun local(key: String, bytes: ByteArray) { dao.local(LocalRow(key, bytes)) }
    override fun removeLocal(key: String) { dao.removeLocal(key) }
    override fun snapshot(id: String, after: String?, page: List<InventoryEntry>?) {
        requireProtocol(page != null && page.size <= 128, "CACHE_BOUNDS"); dao.snapshot(InventoryRow(id, after ?: "", Canonical.encode(page)))
    }
    override fun snapshot(id: String, after: String?) = dao.snapshot(id, after ?: "")?.let { Canonical.parse(it.bytes).model<List<InventoryEntry>>() }
    override fun clearSnapshot(id: String) { dao.clearSnapshot(id) }
    fun records(): List<StoredRecord> { val all = mutableListOf<StoredRecord>(); var cursor: String? = null; do { val rows = rows(cursor); all.addAll(rows); cursor = rows.lastOrNull()?.id } while (cursor != null); return all }
    private fun OperationRow.decode(): StoredRecord {
        val record = Canonical.parse(bytes).model<ReplicationRecord>(); val op = record.operation.operation
        requireProtocol(id == op.operationId && deviceId == op.deviceId && entityId == op.entityId && lamport == op.lamportClock && sequence == record.authorized?.body?.sequence && epoch == record.authorized?.body?.epochId, "DATABASE_FACT_MISMATCH")
        return StoredRecord(record, accepted)
    }
}
