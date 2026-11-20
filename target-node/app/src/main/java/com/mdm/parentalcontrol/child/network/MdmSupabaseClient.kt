package com.mdm.parentalcontrol.child.network

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.mdm.parentalcontrol.child.BuildConfig
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MdmSupabaseClient @Inject constructor() {

    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS) // For WebSockets
        .build()

    private var webSocket: WebSocket? = null
    private var heartbeatHandler: Handler? = null
    private var heartbeatRunnable: Runnable? = null
    private var isConnected = false

    data class RealtimeCallbacks(
        val onPanicLockdown: ((Boolean) -> Unit)? = null,
        val onExtraTime: ((Int) -> Unit)? = null,
        val onAdjustTime: ((deltaMinutes: Int, reason: String?) -> Unit)? = null,
        val onRemoteMessage: ((messageId: String, title: String, body: String, templateKey: String?) -> Unit)? = null,
        val onTimeRequestResolved: ((status: String, grantedMinutes: Int) -> Unit)? = null,
        val onDeviceUnpaired: (() -> Unit)? = null,
        val onPairingSuccess: (() -> Unit)? = null
    )

    data class DeviceTelemetry(
        val batteryLevel: Int = 100,
        val isCharging: Boolean = false,
        val currentApp: String = "Màn hình chính",
        val currentPackageName: String? = null,
        val screenBrightness: Int = 50,
        val isAutoBrightness: Boolean = false,
        val screenMode: String = "on_unlocked",
        val isScreenOn: Boolean = true,
        val isDarkMode: Boolean = false,
        val mediaVolume: Int = 50,
        val ringVolume: Int = 50,
        val notificationVolume: Int = 50,
        val alarmVolume: Int = 80,
        val ringerMode: String = "normal",
        val isMediaMuted: Boolean = false
    )

    data class DailyAppUsageItem(
        val packageName: String,
        val appName: String,
        val appCategory: String = "other",
        val durationSeconds: Int
    )

    private val callbackList = java.util.concurrent.CopyOnWriteArrayList<RealtimeCallbacks>()
    private var currentConnectedDeviceId: String? = null
    private var reconnectHandler: Handler? = null
    private var lastKnownBatteryLevel = 100
    private var lastKnownIsCharging = false
    private var lastKnownCurrentApp = "Màn hình chính"
    private var lastKnownTelemetry: DeviceTelemetry? = null

    /**
     * Đồng bộ Presence (Online state & Live Telemetry) qua WebSocket Channel
     */
    fun trackPresence(
        deviceId: String,
        telemetry: DeviceTelemetry
    ) {
        lastKnownTelemetry = telemetry
        lastKnownBatteryLevel = telemetry.batteryLevel
        lastKnownIsCharging = telemetry.isCharging
        lastKnownCurrentApp = telemetry.currentApp

        val socket = webSocket ?: return
        val topic = "realtime:device:$deviceId"
        val presenceMsg = JSONObject().apply {
            put("topic", topic)
            put("event", "presence")
            put("payload", JSONObject().apply {
                put("type", "track")
                put("payload", JSONObject().apply {
                    put("status", "online")
                    put("device_id", deviceId)
                    put("battery_level", telemetry.batteryLevel)
                    put("is_charging", telemetry.isCharging)
                    put("current_app", telemetry.currentApp)
                    put("current_app_name", telemetry.currentApp)
                    if (telemetry.currentPackageName != null) {
                        put("current_package_name", telemetry.currentPackageName)
                    }
                    put("agent_version", BuildConfig.VERSION_NAME)
                    put("screen_brightness", telemetry.screenBrightness)
                    put("is_auto_brightness", telemetry.isAutoBrightness)
                    put("screen_mode", telemetry.screenMode)
                    put("is_screen_on", telemetry.isScreenOn)
                    put("is_dark_mode", telemetry.isDarkMode)
                    put("media_volume", telemetry.mediaVolume)
                    put("ring_volume", telemetry.ringVolume)
                    put("notification_volume", telemetry.notificationVolume)
                    put("alarm_volume", telemetry.alarmVolume)
                    put("ringer_mode", telemetry.ringerMode)
                    put("is_media_muted", telemetry.isMediaMuted)
                    put("timestamp", System.currentTimeMillis())
                })
            })
            put("ref", System.currentTimeMillis().toString())
        }
        socket.send(presenceMsg.toString())
    }

    fun trackPresence(
        deviceId: String,
        batteryLevel: Int = lastKnownBatteryLevel,
        isCharging: Boolean = lastKnownIsCharging,
        currentApp: String = lastKnownCurrentApp
    ) {
        val base = lastKnownTelemetry ?: DeviceTelemetry()
        trackPresence(
            deviceId,
            base.copy(
                batteryLevel = batteryLevel,
                isCharging = isCharging,
                currentApp = currentApp
            )
        )
    }
    private var reconnectRunnable: Runnable? = null

    private val supabaseUrl = BuildConfig.SUPABASE_URL
    private val anonKey = BuildConfig.SUPABASE_ANON_KEY

    data class PairingResult(
        val deviceId: String,
        val otpCode: String,
        val qrToken: String,
        val expiresAt: String
    )

    /**
     * Tạo phiên ghép nối ban đầu qua Supabase RPC `create_device_pairing`
     */
    fun createPairingSession(
        deviceName: String,
        model: String,
        osVersion: String,
        onSuccess: (PairingResult) -> Unit,
        onError: (String) -> Unit
    ) {
        val rpcUrl = "$supabaseUrl/rest/v1/rpc/create_device_pairing"
        val payload = JSONObject().apply {
            put("p_device_name", deviceName)
            put("p_model", model)
            put("p_os_version", osVersion)
            put("p_agent_version", BuildConfig.VERSION_NAME)
        }

        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
        val requestBody = payload.toString().toRequestBody(mediaType)

        val request = Request.Builder()
            .url(rpcUrl)
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .post(requestBody)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "Pairing request failed", e)
                onError(e.message ?: "Network error")
            }

            override fun onResponse(call: Call, response: Response) {
                val body = response.body?.string()
                if (response.isSuccessful && !body.isNullOrEmpty()) {
                    try {
                        val jsonArray = JSONArray(body)
                        if (jsonArray.length() > 0) {
                            val item = jsonArray.getJSONObject(0)
                            val result = PairingResult(
                                deviceId = item.getString("device_id"),
                                otpCode = item.getString("otp_code"),
                                qrToken = item.getString("qr_token"),
                                expiresAt = item.getString("expires_at")
                            )
                            onSuccess(result)
                            return
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to parse pairing response", e)
                    }
                }
                onError("Pairing failed: HTTP ${response.code}")
            }
        })
    }

    /**
     * Cập nhật FCM token của thiết bị con lên bảng devices để nhận silent push
     */
    fun updateFcmToken(deviceId: String, fcmToken: String, onComplete: ((Boolean) -> Unit)? = null) {
        val url = "$supabaseUrl/rest/v1/devices?id=eq.$deviceId"
        val payload = JSONObject().apply {
            put("fcm_token", fcmToken)
            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            put("updated_at", sdf.format(Date()))
        }
        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
        val requestBody = payload.toString().toRequestBody(mediaType)

        val request = Request.Builder()
            .url(url)
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .addHeader("Prefer", "return=minimal")
            .patch(requestBody)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "Failed to update FCM token", e)
                onComplete?.invoke(false)
            }

            override fun onResponse(call: Call, response: Response) {
                val success = response.isSuccessful
                Log.d(TAG, "Update FCM token response code: ${response.code}")
                onComplete?.invoke(success)
            }
        })
    }

    /**
     * Cập nhật Telemetry mở rộng máy con lên Supabase: pin, sạc, app, độ sáng, chế độ màn hình, âm lượng
     */
    fun updateTelemetry(
        deviceId: String,
        telemetry: DeviceTelemetry
    ) {
        lastKnownBatteryLevel = telemetry.batteryLevel
        lastKnownIsCharging = telemetry.isCharging
        lastKnownCurrentApp = telemetry.currentApp
        lastKnownTelemetry = telemetry

        // 1. Phát Broadcast realtime tới máy phụ huynh tức thì
        val topic = "realtime:device:$deviceId"
        val broadcastPayload = JSONObject().apply {
            put("device_id", deviceId)
            put("battery_level", telemetry.batteryLevel)
            put("is_charging", telemetry.isCharging)
            put("current_app", telemetry.currentApp)
            put("current_app_name", telemetry.currentApp)
            if (telemetry.currentPackageName != null) {
                put("current_package_name", telemetry.currentPackageName)
            }
            put("agent_version", BuildConfig.VERSION_NAME)
            put("screen_brightness", telemetry.screenBrightness)
            put("is_auto_brightness", telemetry.isAutoBrightness)
            put("screen_mode", telemetry.screenMode)
            put("is_screen_on", telemetry.isScreenOn)
            put("is_dark_mode", telemetry.isDarkMode)
            put("media_volume", telemetry.mediaVolume)
            put("ring_volume", telemetry.ringVolume)
            put("notification_volume", telemetry.notificationVolume)
            put("alarm_volume", telemetry.alarmVolume)
            put("ringer_mode", telemetry.ringerMode)
            put("is_media_muted", telemetry.isMediaMuted)
            put("timestamp", System.currentTimeMillis())
        }
        sendBroadcast(topic, "TELEMETRY_UPDATE", broadcastPayload)

        // 2. Cập nhật Presence trên WebSocket
        trackPresence(deviceId, telemetry)

        // 3. Ghi nhận vào DB qua Supabase RPC (update_device_telemetry - 17 tham số chuẩn M1)
        val rpcUrl = "$supabaseUrl/rest/v1/rpc/update_device_telemetry"
        val rpcPayload = JSONObject().apply {
            put("p_device_id", deviceId)
            put("p_battery_level", telemetry.batteryLevel)
            put("p_is_charging", telemetry.isCharging)
            put("p_current_app", telemetry.currentApp)
            put("p_agent_version", BuildConfig.VERSION_NAME)
            if (telemetry.currentPackageName != null) {
                put("p_current_package_name", telemetry.currentPackageName)
            }
            put("p_screen_brightness", telemetry.screenBrightness)
            put("p_is_auto_brightness", telemetry.isAutoBrightness)
            put("p_screen_mode", telemetry.screenMode)
            put("p_is_screen_on", telemetry.isScreenOn)
            put("p_is_dark_mode", telemetry.isDarkMode)
            put("p_media_volume", telemetry.mediaVolume)
            put("p_ring_volume", telemetry.ringVolume)
            put("p_notification_volume", telemetry.notificationVolume)
            put("p_alarm_volume", telemetry.alarmVolume)
            put("p_ringer_mode", telemetry.ringerMode)
            put("p_is_media_muted", telemetry.isMediaMuted)
        }
        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
        val rpcRequest = Request.Builder()
            .url(rpcUrl)
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .post(rpcPayload.toString().toRequestBody(mediaType))
            .build()

        client.newCall(rpcRequest).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.w(TAG, "RPC update_device_telemetry network error: ${e.message}")
            }
            override fun onResponse(call: Call, response: Response) {
                if (!response.isSuccessful) {
                    val err = response.body?.string()
                    Log.w(TAG, "RPC update_device_telemetry HTTP ${response.code}: $err")
                } else {
                    Log.d(TAG, "RPC update_device_telemetry succeeded (battery=${telemetry.batteryLevel}%, brightness=${telemetry.screenBrightness}%, mediaVol=${telemetry.mediaVolume}%)")
                }
                response.close()
            }
        })

        // 4. Ghi nhận dự phòng trực tiếp qua REST PATCH vào bảng devices
        val url = "$supabaseUrl/rest/v1/devices?id=eq.$deviceId"
        val payload = JSONObject().apply {
            put("battery_level", telemetry.batteryLevel)
            put("is_charging", telemetry.isCharging)
            put("current_app_name", telemetry.currentApp)
            if (telemetry.currentPackageName != null) {
                put("current_package_name", telemetry.currentPackageName)
            }
            put("agent_version", BuildConfig.VERSION_NAME)
            put("screen_brightness", telemetry.screenBrightness)
            put("is_auto_brightness", telemetry.isAutoBrightness)
            put("screen_mode", telemetry.screenMode)
            put("is_screen_on", telemetry.isScreenOn)
            put("is_dark_mode", telemetry.isDarkMode)
            put("media_volume", telemetry.mediaVolume)
            put("ring_volume", telemetry.ringVolume)
            put("notification_volume", telemetry.notificationVolume)
            put("alarm_volume", telemetry.alarmVolume)
            put("ringer_mode", telemetry.ringerMode)
            put("is_media_muted", telemetry.isMediaMuted)
            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            put("last_seen_at", sdf.format(Date()))
            put("status", "active")
            put("updated_at", sdf.format(Date()))
        }
        val requestBody = payload.toString().toRequestBody(mediaType)

        val request = Request.Builder()
            .url(url)
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .addHeader("Prefer", "return=minimal")
            .patch(requestBody)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.w(TAG, "REST PATCH devices failed: ${e.message}")
            }
            override fun onResponse(call: Call, response: Response) {
                if (!response.isSuccessful) {
                    val err = response.body?.string()
                    Log.w(TAG, "REST PATCH devices HTTP ${response.code}: $err")
                } else {
                    Log.d(TAG, "REST PATCH devices succeeded (${telemetry.batteryLevel}%, ⚡${telemetry.isCharging})")
                }
                response.close()
            }
        })
    }

    fun updateTelemetry(
        deviceId: String,
        batteryLevel: Int,
        isCharging: Boolean,
        currentApp: String
    ) {
        val base = lastKnownTelemetry ?: DeviceTelemetry()
        updateTelemetry(
            deviceId,
            base.copy(
                batteryLevel = batteryLevel,
                isCharging = isCharging,
                currentApp = currentApp
            )
        )
    }

    /**
     * Kiểm tra trạng thái đã được ghép nối hay chưa từ bảng pairing_sessions
     */
    fun checkPairingStatus(deviceId: String, onResult: (isClaimed: Boolean) -> Unit) {
        val url = "$supabaseUrl/rest/v1/pairing_sessions?device_id=eq.$deviceId&is_claimed=eq.true&limit=1"
        val request = Request.Builder()
            .url(url)
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .get()
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "checkPairingStatus failed", e)
                onResult(false)
            }

            override fun onResponse(call: Call, response: Response) {
                val body = response.body?.string()
                if (response.isSuccessful && !body.isNullOrEmpty()) {
                    try {
                        val array = JSONArray(body)
                        if (array.length() > 0) {
                            onResult(true)
                            return
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to parse pairing status", e)
                    }
                }
                onResult(false)
            }
        })
    }

    /**
     * Kết nối Supabase Realtime WebSocket (Phoenix Channels Protocol)
     * Hỗ trợ đa listener (Service + UI), tự động duy trì kết nối ngầm 24/7 và auto-reconnect sau 5s nếu rớt mạng
     */
    fun connectRealtime(
        deviceId: String,
        onPanicLockdown: (Boolean) -> Unit,
        onExtraTime: (Int) -> Unit,
        onAdjustTime: ((deltaMinutes: Int, reason: String?) -> Unit)? = null,
        onRemoteMessage: ((messageId: String, title: String, body: String, templateKey: String?) -> Unit)? = null,
        onTimeRequestResolved: ((status: String, grantedMinutes: Int) -> Unit)? = null,
        onDeviceUnpaired: (() -> Unit)? = null,
        onPairingSuccess: (() -> Unit)? = null
    ) {
        val callbacks = RealtimeCallbacks(
            onPanicLockdown, onExtraTime, onAdjustTime, onRemoteMessage, onTimeRequestResolved, onDeviceUnpaired, onPairingSuccess
        )
        callbackList.add(callbacks)
        currentConnectedDeviceId = deviceId

        if (isConnected && webSocket != null) {
            Log.i(TAG, "⚡ Supabase Realtime already connected, registered new listener.")
            return
        }

        reconnectHandler?.removeCallbacksAndMessages(null)
        establishWebSocket(deviceId)
    }

    private fun establishWebSocket(deviceId: String) {
        val host = supabaseUrl.replace("https://", "").replace("http://", "")
        val wsUrl = "wss://$host/realtime/v1/websocket?apikey=$anonKey&vsn=1.0.0"
        val topic = "realtime:device:$deviceId"

        val request = Request.Builder().url(wsUrl).build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.i(TAG, "⚡ Connected to Supabase Realtime WebSocket")
                isConnected = true
                reconnectHandler?.removeCallbacksAndMessages(null)

                // 1. Join Topic realtime:device:{deviceId}
                val joinMsg = JSONObject().apply {
                    put("topic", topic)
                    put("event", "phx_join")
                    put("payload", JSONObject().apply {
                        put("config", JSONObject().apply {
                            put("broadcast", JSONObject().apply {
                                put("ack", false)
                                put("self", false)
                            })
                            put("presence", JSONObject().apply {
                                put("key", deviceId)
                            })
                            val pgChanges = JSONArray().apply {
                                put(JSONObject().apply {
                                    put("event", "UPDATE")
                                    put("schema", "public")
                                    put("table", "devices")
                                    put("filter", "id=eq.$deviceId")
                                })
                                put(JSONObject().apply {
                                    put("event", "UPDATE")
                                    put("schema", "public")
                                    put("table", "pairing_sessions")
                                    put("filter", "device_id=eq.$deviceId")
                                })
                                put(JSONObject().apply {
                                    put("event", "INSERT")
                                    put("schema", "public")
                                    put("table", "device_messages")
                                    put("filter", "device_id=eq.$deviceId")
                                })
                                put(JSONObject().apply {
                                    put("event", "UPDATE")
                                    put("schema", "public")
                                    put("table", "time_requests")
                                    put("filter", "device_id=eq.$deviceId")
                                })
                            }
                            put("postgres_changes", pgChanges)
                        })
                    })
                    put("ref", "1")
                }
                webSocket.send(joinMsg.toString())

                // 2. Track Presence (Online state & Telemetry)
                trackPresence(deviceId)

                // 3. Heartbeat loop (every 25 seconds)
                startHeartbeat(webSocket)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val msg = JSONObject(text)
                    val event = msg.optString("event")

                    if (event == "broadcast") {
                        val payload = msg.optJSONObject("payload")
                        val innerEvent = payload?.optString("event")
                        val innerPayload = payload?.optJSONObject("payload") ?: payload

                        when (innerEvent) {
                            "PANIC_LOCKDOWN" -> {
                                val isLocked = innerPayload?.optBoolean("is_locked", true) ?: true
                                Log.w(TAG, "🚨 Supabase Realtime received PANIC_LOCKDOWN: $isLocked")
                                callbackList.forEach { it.onPanicLockdown?.invoke(isLocked) }
                            }
                            "GRANT_EXTRA_TIME" -> {
                                val minutes = innerPayload?.optInt("extra_minutes", 15) ?: 15
                                Log.i(TAG, "⏳ Supabase Realtime received GRANT_EXTRA_TIME: +$minutes minutes")
                                callbackList.forEach {
                                    if (it.onAdjustTime != null) {
                                        it.onAdjustTime.invoke(minutes, "Thưởng giờ chơi")
                                    } else {
                                        it.onExtraTime?.invoke(minutes)
                                    }
                                }
                            }
                            "ADJUST_SCREEN_TIME" -> {
                                val delta = innerPayload?.optInt("delta_minutes", 15) ?: 15
                                val reason = innerPayload?.optString("reason", "")
                                Log.i(TAG, "⚡ Supabase Realtime received ADJUST_SCREEN_TIME: delta=$delta, reason=$reason")
                                callbackList.forEach {
                                    it.onAdjustTime?.invoke(delta, reason)
                                }
                            }
                            "REMOTE_MESSAGE" -> {
                                val msgId = innerPayload?.optString("message_id", "") ?: ""
                                val title = innerPayload?.optString("title", "🔔 Nhắc nhở từ Ba Mẹ") ?: "🔔 Nhắc nhở từ Ba Mẹ"
                                val body = innerPayload?.optString("body", "") ?: ""
                                val template = innerPayload?.optString("template_key", "custom")
                                Log.i(TAG, "💬 Supabase Realtime received REMOTE_MESSAGE: $title - $body")
                                callbackList.forEach { it.onRemoteMessage?.invoke(msgId, title, body, template) }
                            }
                            "TIME_REQUEST_RESOLVED" -> {
                                val status = innerPayload?.optString("status", "pending") ?: "pending"
                                val granted = innerPayload?.optInt("granted_minutes", 0) ?: 0
                                Log.i(TAG, "✅ Supabase Realtime received TIME_REQUEST_RESOLVED: $status (+$granted min)")
                                callbackList.forEach { it.onTimeRequestResolved?.invoke(status, granted) }
                            }
                            "DEVICE_UNPAIRED" -> {
                                Log.w(TAG, "⚠️ Supabase Realtime received DEVICE_UNPAIRED")
                                callbackList.forEach { it.onDeviceUnpaired?.invoke() }
                            }
                            "PAIRING_SUCCESS" -> {
                                Log.i(TAG, "✨ Supabase Realtime received PAIRING_SUCCESS!")
                                callbackList.forEach { it.onPairingSuccess?.invoke() }
                            }
                        }
                    } else if (event == "postgres_changes") {
                        val payload = msg.optJSONObject("payload")
                        val data = payload?.optJSONObject("data")
                        val record = data?.optJSONObject("record")
                        val table = data?.optString("table")
                        if (record != null) {
                            if (table == "device_messages") {
                                val isAck = record.optBoolean("is_acknowledged", false)
                                if (!isAck) {
                                    val msgId = record.optString("id", "")
                                    val title = record.optString("title", "🔔 Nhắc nhở từ Ba Mẹ")
                                    val body = record.optString("body", "")
                                    val template = record.optString("template_key", "custom")
                                    Log.i(TAG, "💬 Supabase Postgres Changes: device_messages INSERT: $title - $body")
                                    callbackList.forEach { it.onRemoteMessage?.invoke(msgId, title, body, template) }
                                }
                            } else if (table == "time_requests") {
                                val status = record.optString("status", "")
                                val grantedMinutes = record.optInt("granted_minutes", 0)
                                if (status == "approved" || status == "rejected") {
                                    Log.i(TAG, "✅ Supabase Postgres Changes: time_requests UPDATE: $status (+$grantedMinutes min)")
                                    callbackList.forEach { it.onTimeRequestResolved?.invoke(status, grantedMinutes) }
                                }
                            } else if (table == "pairing_sessions") {
                                val isClaimed = record.optBoolean("is_claimed", false)
                                if (isClaimed) {
                                    Log.i(TAG, "✨ Supabase Postgres Changes: pairing_sessions is_claimed=true")
                                    callbackList.forEach { it.onPairingSuccess?.invoke() }
                                }
                            } else {
                                val isLocked = record.optBoolean("is_locked", false)
                                val extraMins = record.optInt("extra_time_minutes", 0)
                                val familyId = record.optString("family_id", "")
                                val isUnpaired = record.optBoolean("is_unpaired", false)

                                if (isUnpaired) {
                                    Log.w(TAG, "⚡ Supabase Postgres Changes: device is_unpaired=true")
                                    callbackList.forEach { it.onDeviceUnpaired?.invoke() }
                                } else if (familyId.isNotEmpty() && familyId != "null") {
                                    callbackList.forEach { it.onPairingSuccess?.invoke() }
                                }

                                Log.w(TAG, "⚡ Supabase Postgres Changes: is_locked=$isLocked, extra_time=$extraMins")
                                callbackList.forEach {
                                    it.onPanicLockdown?.invoke(isLocked)
                                    if (extraMins > 0) it.onExtraTime?.invoke(extraMins)
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error parsing Supabase message: $text", e)
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "Supabase WebSocket failure, auto-reconnecting in 5s...", t)
                isConnected = false
                scheduleReconnect()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "Supabase WebSocket closed: $reason, auto-reconnecting in 5s...")
                isConnected = false
                scheduleReconnect()
            }
        })
    }

    private fun scheduleReconnect() {
        val devId = currentConnectedDeviceId ?: return
        reconnectHandler?.removeCallbacksAndMessages(null)
        reconnectHandler = Handler(Looper.getMainLooper())
        reconnectRunnable = Runnable {
            if (!isConnected) {
                Log.i(TAG, "Auto-reconnecting to Supabase Realtime for device: $devId")
                establishWebSocket(devId)
            }
        }
        reconnectHandler?.postDelayed(reconnectRunnable!!, 5000L)
    }

    /**
     * Gửi Broadcast Event qua Supabase Realtime Phoenix WebSocket
     */
    fun sendBroadcast(topic: String, eventName: String, payload: JSONObject) {
        val socket = webSocket ?: return
        val innerPayload = JSONObject().apply {
            put("type", "broadcast")
            put("event", eventName)
            val keys = payload.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                put(key, payload.get(key))
            }
            put("payload", payload)
        }
        val broadcastMsg = JSONObject().apply {
            put("topic", topic)
            put("event", "broadcast")
            put("payload", innerPayload)
            put("ref", System.currentTimeMillis().toString())
        }
        socket.send(broadcastMsg.toString())
    }

    /**
     * Gửi yêu cầu kích hoạt Edge Function notify-family-parents tới phụ huynh (FCM HTTP v1 + iOS APNs)
     */
    fun invokeNotifyFamilyParents(payload: JSONObject, onDone: ((Boolean) -> Unit)? = null) {
        val url = "$supabaseUrl/functions/v1/notify-family-parents"
        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
        val request = Request.Builder()
            .url(url)
            .post(payload.toString().toRequestBody(mediaType))
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.w(TAG, "notify-family-parents Edge Function call failed: ${e.message}")
                onDone?.invoke(false)
            }

            override fun onResponse(call: Call, response: Response) {
                val ok = response.isSuccessful
                val body = response.body?.string()
                response.close()
                Log.i(TAG, "notify-family-parents Edge Function response HTTP ${response.code}: $body")
                onDone?.invoke(ok)
            }
        })
    }

    /**
     * Máy con phản hồi xác nhận (ACK) khi bé nhấn vào tin nhắn nhắc nhở của phụ huynh
     */
    fun sendAckMessage(
        deviceId: String,
        messageId: String,
        replyText: String? = null,
        onComplete: ((Boolean) -> Unit)? = null
    ) {
        val topic = "realtime:device:$deviceId"
        val broadcastPayload = JSONObject().apply {
            put("message_id", messageId)
            put("device_id", deviceId)
            put("status", "acknowledged")
            put("reply_text", replyText ?: "Dạ con nghe rồi! 👍")
            put("timestamp", System.currentTimeMillis())
        }
        sendBroadcast(topic, "ACK_MESSAGE", broadcastPayload)
        Log.i(TAG, "Sent ACK_MESSAGE for msgId: $messageId, replyText=$replyText")

        // 1. Gọi RPC acknowledge_device_message (SECURITY DEFINER)
        val rpcUrl = "$supabaseUrl/rest/v1/rpc/acknowledge_device_message"
        val rpcPayload = JSONObject().apply {
            put("p_device_id", deviceId)
            if (messageId.contains("-")) {
                put("p_message_id", messageId)
            }
            if (!replyText.isNullOrBlank()) {
                put("p_reply_text", replyText)
            }
        }
        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
        val request = Request.Builder()
            .url(rpcUrl)
            .post(rpcPayload.toString().toRequestBody(mediaType))
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.w(TAG, "Failed to call acknowledge_device_message RPC: ${e.message}")
                onComplete?.invoke(false)
            }

            override fun onResponse(call: Call, response: Response) {
                val bodyStr = response.body?.string()
                val success = response.isSuccessful
                response.close()
                var ackRecordId: String = messageId
                if (success && !bodyStr.isNullOrEmpty()) {
                    try {
                        val json = JSONObject(bodyStr)
                        val id = json.optString("id", "")
                        if (id.isNotEmpty()) ackRecordId = id
                    } catch (_: Exception) {}
                }

                // 2. Gửi đẩy Edge Function notify-family-parents tới Phụ huynh (FCM Android + iOS APNs)
                val notifyPayload = JSONObject().apply {
                    put("device_id", deviceId)
                    put("event_type", if (!replyText.isNullOrBlank()) "DEVICE_MESSAGE_REPLY" else "DEVICE_MESSAGE_ACK")
                    if (ackRecordId.isNotEmpty() && ackRecordId.contains("-")) {
                        put("record_id", ackRecordId)
                    }
                    put("title", "Bé đã phản hồi lời nhắc")
                    put("body", replyText ?: "Dạ con nghe rồi! 👍")
                    put("data", JSONObject().apply {
                        put("reply_text", replyText ?: "Dạ con nghe rồi! 👍")
                        if (ackRecordId.isNotEmpty()) {
                            put("record_id", ackRecordId)
                        }
                    })
                }
                invokeNotifyFamilyParents(notifyPayload)
                onComplete?.invoke(success)
            }
        })
    }

    /**
     * Gửi yêu cầu xin thêm thời gian sử dụng từ máy con lên cho Ba Mẹ
     */
    fun sendTimeRequest(
        deviceId: String,
        minutes: Int,
        reason: String,
        onResult: (Boolean) -> Unit
    ) {
        val topic = "realtime:device:$deviceId"
        val broadcastPayload = JSONObject().apply {
            put("device_id", deviceId)
            put("requested_minutes", minutes)
            put("reason", reason)
            put("timestamp", System.currentTimeMillis())
        }
        sendBroadcast(topic, "TIME_REQUEST", broadcastPayload)
        Log.i(TAG, "Sent TIME_REQUEST: +$minutes mins, reason=$reason")

        // 1. Tạo bản ghi qua RPC create_time_request (SECURITY DEFINER tự động gán family_id)
        val rpcUrl = "$supabaseUrl/rest/v1/rpc/create_time_request"
        val rpcPayload = JSONObject().apply {
            put("p_device_id", deviceId)
            put("p_requested_minutes", minutes)
            put("p_reason", reason)
        }
        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
        val request = Request.Builder()
            .url(rpcUrl)
            .post(rpcPayload.toString().toRequestBody(mediaType))
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.w(TAG, "Failed to call create_time_request RPC: ${e.message}")
                onResult(true) // Broadcast was already sent
            }

            override fun onResponse(call: Call, response: Response) {
                val bodyStr = response.body?.string()
                response.close()
                var requestId: String? = null
                if (response.isSuccessful && !bodyStr.isNullOrEmpty()) {
                    try {
                        val json = JSONObject(bodyStr)
                        requestId = json.optString("id", json.optString("request_id", ""))
                    } catch (_: Exception) {}
                }
                Log.i(TAG, "create_time_request RPC status=${response.code}, requestId=$requestId")

                // 2. Gửi đẩy Edge Function notify-family-parents tới máy Phụ huynh (FCM Android + iOS APNs)
                val notifyPayload = JSONObject().apply {
                    put("device_id", deviceId)
                    put("event_type", "TIME_REQUEST")
                    if (!requestId.isNullOrEmpty()) {
                        put("record_id", requestId)
                    }
                    put("title", "Yêu cầu thêm giờ chơi")
                    put("body", if (reason.isNotBlank()) reason else "Bé xin thêm $minutes phút sử dụng")
                    put("data", JSONObject().apply {
                        put("requested_minutes", minutes.toString())
                        put("reason", reason)
                        if (!requestId.isNullOrEmpty()) {
                            put("record_id", requestId)
                        }
                    })
                }
                invokeNotifyFamilyParents(notifyPayload)
                onResult(true)
            }
        })
    }

    /**
     * Đồng bộ thời gian sử dụng chính xác lên Backend qua RPC sync_device_daily_usage
     */
    fun syncDeviceDailyUsage(
        deviceId: String,
        usageDate: String,
        totalSeconds: Int,
        apps: List<DailyAppUsageItem>,
        timezone: String = TimeZone.getDefault().id,
        onResult: ((Boolean) -> Unit)? = null
    ) {
        val url = "$supabaseUrl/rest/v1/rpc/sync_device_daily_usage"
        val appsArray = JSONArray()
        for (app in apps) {
            appsArray.put(JSONObject().apply {
                put("package_name", app.packageName)
                put("app_name", app.appName)
                put("app_category", app.appCategory)
                put("duration_seconds", app.durationSeconds)
            })
        }
        val payload = JSONObject().apply {
            put("p_device_id", deviceId)
            put("p_usage_date", usageDate)
            put("p_total_seconds", totalSeconds)
            put("p_apps", appsArray)
            put("p_timezone", timezone)
        }
        val mediaType = "application/json; charset=utf-8".toMediaTypeOrNull()
        val request = Request.Builder()
            .url(url)
            .post(payload.toString().toRequestBody(mediaType))
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.w(TAG, "RPC sync_device_daily_usage failed: ${e.message}")
                onResult?.invoke(false)
            }

            override fun onResponse(call: Call, response: Response) {
                val ok = response.isSuccessful
                val body = response.body?.string()
                response.close()
                if (ok) {
                    Log.i(TAG, "RPC sync_device_daily_usage succeeded: date=$usageDate, total=${totalSeconds}s, apps=${apps.size}")
                } else {
                    Log.w(TAG, "RPC sync_device_daily_usage HTTP ${response.code}: $body")
                }
                onResult?.invoke(ok)
            }
        })
    }

    private fun startHeartbeat(ws: WebSocket) {
        heartbeatHandler = Handler(Looper.getMainLooper())
        heartbeatRunnable = object : Runnable {
            override fun run() {
                if (isConnected) {
                    val hbMsg = JSONObject().apply {
                        put("topic", "phoenix")
                        put("event", "heartbeat")
                        put("payload", JSONObject())
                        put("ref", "hb")
                    }
                    ws.send(hbMsg.toString())
                    heartbeatHandler?.postDelayed(this, 25000L)
                }
            }
        }
        heartbeatHandler?.postDelayed(heartbeatRunnable!!, 25000L)
    }

    fun disconnect() {
        reconnectHandler?.removeCallbacksAndMessages(null)
        reconnectHandler = null
        heartbeatHandler?.removeCallbacksAndMessages(null)
        heartbeatHandler = null
        webSocket?.close(1000, "Normal closure")
        webSocket = null
        isConnected = false
    }

    data class UnreadMessage(
        val id: String,
        val title: String,
        val body: String,
        val templateKey: String?,
        val createdAt: String
    )

    fun fetchLatestUnreadMessage(deviceId: String, onResult: (UnreadMessage?) -> Unit) {
        val url = "$supabaseUrl/rest/v1/device_messages?device_id=eq.$deviceId&is_acknowledged=eq.false&order=created_at.desc&limit=1"
        val request = Request.Builder()
            .url(url)
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .get()
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                onResult(null)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use { res ->
                    if (res.isSuccessful) {
                        val bodyStr = res.body?.string()
                        if (!bodyStr.isNullOrEmpty()) {
                            try {
                                val array = JSONArray(bodyStr)
                                if (array.length() > 0) {
                                    val item = array.getJSONObject(0)
                                    val msg = UnreadMessage(
                                        id = item.optString("id", ""),
                                        title = item.optString("title", "🔔 Nhắc nhở từ Ba Mẹ"),
                                        body = item.optString("body", ""),
                                        templateKey = item.optString("template_key", "custom"),
                                        createdAt = item.optString("created_at", "")
                                    )
                                    onResult(msg)
                                    return
                                }
                            } catch (_: Exception) {}
                        }
                    }
                    onResult(null)
                }
            }
        })
    }

    data class DeviceRemoteStatus(
        val isLocked: Boolean,
        val extraMinutes: Int
    )

    fun fetchDeviceStatus(deviceId: String, onResult: (DeviceRemoteStatus?) -> Unit) {
        val url = "$supabaseUrl/rest/v1/devices?id=eq.$deviceId&select=is_locked,extra_time_minutes"
        val request = Request.Builder()
            .url(url)
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .get()
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                onResult(null)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use { res ->
                    if (res.isSuccessful) {
                        val bodyStr = res.body?.string()
                        if (!bodyStr.isNullOrEmpty()) {
                            try {
                                val array = JSONArray(bodyStr)
                                if (array.length() > 0) {
                                    val item = array.getJSONObject(0)
                                    val status = DeviceRemoteStatus(
                                        isLocked = item.optBoolean("is_locked", false),
                                        extraMinutes = item.optInt("extra_time_minutes", 0)
                                    )
                                    onResult(status)
                                    return
                                }
                            } catch (_: Exception) {}
                        }
                    }
                    onResult(null)
                }
            }
        })
    }

    companion object {
        private const val TAG = "MdmSupabaseClient"
    }
}
