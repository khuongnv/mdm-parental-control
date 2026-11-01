package com.mdm.parentalcontrol.child.di

import android.content.Context
import androidx.room.Room
import com.mdm.parentalcontrol.child.data.local.MdmAppDatabase
import com.mdm.parentalcontrol.child.data.local.UsageDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): MdmAppDatabase {
        return Room.databaseBuilder(
            context,
            MdmAppDatabase::class.java,
            "mdm_child_db"
        ).fallbackToDestructiveMigration().build()
    }

    @Provides
    fun provideUsageDao(database: MdmAppDatabase): UsageDao {
        return database.usageDao()
    }
}
