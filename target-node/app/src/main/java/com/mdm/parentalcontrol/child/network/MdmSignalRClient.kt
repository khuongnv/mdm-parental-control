package com.mdm.parentalcontrol.child.network

import javax.inject.Inject
import javax.inject.Singleton

/**
 * Adapter duy trì tương thích ngược, chuyển tiếp toàn bộ sang MdmSupabaseClient
 */
@Singleton
class MdmSignalRClient @Inject constructor(
    private val supabaseClient: MdmSupabaseClient
) {

    fun connect(baseUrl: String, deviceId: String, onPanicLockdown: (Boolean) -> Unit, onExtraTime: (Int) -> Unit) {
        supabaseClient.connectRealtime(deviceId, onPanicLockdown, onExtraTime)
    }

    fun disconnect() {
        supabaseClient.disconnect()
    }
}
