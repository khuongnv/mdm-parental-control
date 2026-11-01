package com.mdm.parentalcontrol.child.network

import android.util.Log
import com.microsoft.signalr.HubConnection
import com.microsoft.signalr.HubConnectionBuilder
import com.microsoft.signalr.HubConnectionState
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MdmSignalRClient @Inject constructor() {

    private var hubConnection: HubConnection? = null

    fun connect(baseUrl: String, deviceId: String, onPanicLockdown: (Boolean) -> Unit, onExtraTime: (Int) -> Unit) {
        val hubUrl = "$baseUrl/hubs/mdm"
        hubConnection = HubConnectionBuilder.create(hubUrl)
            .build()

        hubConnection?.on("ReceivePanicLockdown", { isLocked: Boolean ->
            Log.w(TAG, "SignalR received Panic Lockdown: $isLocked")
            onPanicLockdown(isLocked)
        }, Boolean::class.java)

        hubConnection?.on("ReceiveExtraTime", { minutes: Int ->
            Log.i(TAG, "SignalR received Extra Time: +$minutes minutes")
            onExtraTime(minutes)
        }, Int::class.java)

        try {
            hubConnection?.start()?.blockingAwait()
            if (hubConnection?.connectionState == HubConnectionState.CONNECTED) {
                hubConnection?.send("RegisterChildDevice", deviceId)
                Log.i(TAG, "Connected to SignalR Hub and registered device $deviceId")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to connect to SignalR Hub", e)
        }
    }

    fun disconnect() {
        hubConnection?.stop()
    }

    companion object {
        private const val TAG = "MdmSignalRClient"
    }
}
