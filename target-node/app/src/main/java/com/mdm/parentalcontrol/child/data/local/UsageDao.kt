package com.mdm.parentalcontrol.child.data.local

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface UsageDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertUsageEvents(events: List<AppUsageEventEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertDailyUsage(usage: DailyAppUsageEntity)

    @Query("SELECT * FROM daily_app_usage WHERE date = :date")
    fun getDailyUsageFlow(date: String): Flow<List<DailyAppUsageEntity>>

    @Query("SELECT SUM(totalTimeInForegroundMs) FROM daily_app_usage WHERE date = :date")
    suspend fun getTotalScreenTimeMs(date: String): Long?

    @Query("SELECT * FROM device_policy_local WHERE id = 1")
    fun getLocalPolicyFlow(): Flow<DevicePolicyLocalEntity?>

    @Query("SELECT * FROM device_policy_local WHERE id = 1")
    suspend fun getLocalPolicy(): DevicePolicyLocalEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun savePolicy(policy: DevicePolicyLocalEntity)
}
