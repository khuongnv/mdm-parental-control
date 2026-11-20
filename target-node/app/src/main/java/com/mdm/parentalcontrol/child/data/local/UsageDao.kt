package com.mdm.parentalcontrol.child.data.local

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface UsageDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertUsageEvents(events: List<AppUsageEventEntity>)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertDailyUsageIfAbsent(usage: DailyAppUsageEntity): Long

    @Query(
        "UPDATE daily_app_usage " +
            "SET totalTimeInForegroundMs = totalTimeInForegroundMs + :deltaMs, lastUpdated = :lastUpdated " +
            "WHERE packageName = :packageName AND date = :date"
    )
    suspend fun addDailyUsageDelta(packageName: String, date: String, deltaMs: Long, lastUpdated: Long): Int

    @Transaction
    suspend fun incrementDailyUsage(packageName: String, date: String, deltaMs: Long, lastUpdated: Long) {
        if (deltaMs <= 0L) return
        val inserted = insertDailyUsageIfAbsent(
            DailyAppUsageEntity(
                packageName = packageName,
                date = date,
                totalTimeInForegroundMs = deltaMs,
                lastUpdated = lastUpdated
            )
        )
        if (inserted == -1L) {
            addDailyUsageDelta(packageName, date, deltaMs, lastUpdated)
        }
    }

    @Query("SELECT * FROM daily_app_usage WHERE date = :date ORDER BY totalTimeInForegroundMs DESC")
    fun getDailyUsageFlow(date: String): Flow<List<DailyAppUsageEntity>>

    @Query("SELECT * FROM daily_app_usage WHERE date = :date ORDER BY totalTimeInForegroundMs DESC")
    suspend fun getDailyUsageSnapshot(date: String): List<DailyAppUsageEntity>

    @Query("SELECT SUM(totalTimeInForegroundMs) FROM daily_app_usage WHERE date = :date")
    suspend fun getTotalScreenTimeMs(date: String): Long?

    @Query("SELECT SUM(totalTimeInForegroundMs) FROM daily_app_usage WHERE date = :date")
    fun getTotalScreenTimeMsFlow(date: String): Flow<Long?>

    @Query("SELECT * FROM device_policy_local WHERE id = 1")
    fun getLocalPolicyFlow(): Flow<DevicePolicyLocalEntity?>

    @Query("SELECT * FROM device_policy_local WHERE id = 1")
    suspend fun getLocalPolicy(): DevicePolicyLocalEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun savePolicy(policy: DevicePolicyLocalEntity)
}
