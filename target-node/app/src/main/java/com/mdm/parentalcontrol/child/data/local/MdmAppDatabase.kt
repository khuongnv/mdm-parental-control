package com.mdm.parentalcontrol.child.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [
        AppUsageEventEntity::class,
        DailyAppUsageEntity::class,
        DevicePolicyLocalEntity::class
    ],
    version = 1,
    exportSchema = false
)
abstract class MdmAppDatabase : RoomDatabase() {
    abstract fun usageDao(): UsageDao
}
