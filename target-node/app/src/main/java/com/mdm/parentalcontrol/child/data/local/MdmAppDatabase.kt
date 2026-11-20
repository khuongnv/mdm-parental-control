package com.mdm.parentalcontrol.child.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        AppUsageEventEntity::class,
        DailyAppUsageEntity::class,
        DevicePolicyLocalEntity::class
    ],
    version = 2,
    exportSchema = false
)
abstract class MdmAppDatabase : RoomDatabase() {
    abstract fun usageDao(): UsageDao

    companion object {
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `daily_app_usage_new` (
                        `packageName` TEXT NOT NULL,
                        `date` TEXT NOT NULL,
                        `totalTimeInForegroundMs` INTEGER NOT NULL,
                        `lastUpdated` INTEGER NOT NULL,
                        PRIMARY KEY(`packageName`, `date`)
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    INSERT OR REPLACE INTO `daily_app_usage_new` (`packageName`, `date`, `totalTimeInForegroundMs`, `lastUpdated`)
                    SELECT `packageName`, `date`, `totalTimeInForegroundMs`, `lastUpdated` FROM `daily_app_usage`
                    """.trimIndent()
                )
                db.execSQL("DROP TABLE `daily_app_usage`")
                db.execSQL("ALTER TABLE `daily_app_usage_new` RENAME TO `daily_app_usage`")
            }
        }
    }
}
