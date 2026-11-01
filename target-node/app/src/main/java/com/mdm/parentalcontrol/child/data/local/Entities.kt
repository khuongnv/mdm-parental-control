package com.mdm.parentalcontrol.child.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "app_usage_events")
data class AppUsageEventEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val packageName: String,
    val eventType: Int, // 1: ACTIVITY_RESUMED, 2: ACTIVITY_PAUSED
    val timestamp: Long
)

@Entity(tableName = "daily_app_usage")
data class DailyAppUsageEntity(
    @PrimaryKey
    val packageName: String,
    val date: String, // YYYY-MM-DD
    val totalTimeInForegroundMs: Long,
    val lastUpdated: Long
)

@Entity(tableName = "device_policy_local")
data class DevicePolicyLocalEntity(
    @PrimaryKey
    val id: Int = 1,
    val dailyLimitMinutes: Int = 120,
    val bedtimeStart: String = "21:30",
    val bedtimeEnd: String = "06:00",
    val isEmergencyLockdown: Boolean = false,
    val policyVersion: Long = 1,
    val etag: String = ""
)
