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

    private val callbackList = java.util.concurrent.CopyOnWriteArrayList<RealtimeCallbacks>()
    private var currentConnectedDeviceId: String? = null
    private var reconnectHandler: Handler? = null
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
     * Cập nhật Telemetry máy con lên Supabase: mức pin, trạng thái sạc, app đang mở
     */
    fun updateTelemetry(
        deviceId: String,
        batteryLevel: Int,
        isCharging: Boolean,
        currentApp: String
    ) {
        // 1. Phát Broadcast realtime tới máy phụ huynh tức thì
        val topic = "realtime:device:$deviceId"
        val broadcastPayload = JSONObject().apply {
            put("device_id", deviceId)
            put("battery_level", batteryLevel)
            put("is_charging", isCharging)
            put("current_app", currentApp)
            put("current_app_name", currentApp)
            put("agent_version", BuildConfig.VERSION_NAME)
            put("timestamp", System.currentTimeMillis())
        }
        sendBroadcast(topic, "TELEMETRY_UPDATE", broadcastPayload)

        // 2. Ghi nhận vào DB qua REST API
        val url = "$supabaseUrl/rest/v1/devices?id=eq.$deviceId"
        val payload = JSONObject().apply {
            put("battery_level", batteryLevel)
            put("is_charging", isCharging)
            put("current_app_name", currentApp)
            put("agent_version", BuildConfig.VERSION_NAME)
            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            put("last_seen_at", sdf.format(Date()))
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
                Log.w(TAG, "Failed to update telemetry: ${e.message}")
            }
            override fun onResponse(call: Call, response: Response) {
                // Silently updated
            }
        })
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
                            }
                            put("postgres_changes", pgChanges)
                        })
                    })
                    put("ref", "1")
                }
                webSocket.send(joinMsg.toString())

                // 2. Track Presence (Online state)
                val presenceMsg = JSONObject().apply {
                    put("topic", topic)
                    put("event", "presence")
                    put("payload", JSONObject().apply {
                        put("type", "track")
                        put("payload", JSONObject().apply {
                            put("status", "online")
                            put("device_id", deviceId)
                            put("timestamp", System.currentTimeMillis())
                        })
                    })
                    put("ref", "2")
                }
                webSocket.send(presenceMsg.toString())

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
                        val innerPayload = payload?.optJSONObject("payload")

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
                                    it.onExtraTime?.invoke(minutes)
                                    it.onAdjustTime?.invoke(minutes, "Thưởng giờ chơi")
                                }
                            }
                            "ADJUST_SCREEN_TIME" -> {
                                val delta = innerPayload?.optInt("delta_minutes", 15) ?: 15
                                val reason = innerPayload?.optString("reason", "")
                                Log.i(TAG, "⚡ Supabase Realtime received ADJUST_SCREEN_TIME: delta=$delta, reason=$reason")
                                callbackList.forEach {
                                    it.onAdjustTime?.invoke(delta, reason)
                                    if (delta > 0) it.onExtraTime?.invoke(delta)
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
                            if (table == "pairing_sessions") {
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
     * Máy con phản hồi xác nhận (ACK) khi bé nhấn vào tin nhắn nhắc nhở của phụ huynh
     */
    fun sendAckMessage(deviceId: String, messageId: String, onComplete: ((Boolean) -> Unit)? = null) {
        val topic = "realtime:device:$deviceId"
        val payload = JSONObject().apply {
            put("message_id", messageId)
            put("device_id", deviceId)
            put("status", "acknowledged")
            put("timestamp", System.currentTimeMillis())
        }
        sendBroadcast(topic, "ACK_MESSAGE", payload)
        Log.i(TAG, "Sent ACK_MESSAGE for msgId: $messageId")

        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val nowIso = sdf.format(Date())

        // 1. Cập nhật bảng device_messages (hỗ trợ cả UUID hoặc fallback theo device_id)
        val url = if (messageId.contains("-")) {
            "$supabaseUrl/rest/v1/device_messages?id=eq.$messageId"
        } else {
            "$supabaseUrl/rest/v1/device_messages?device_id=eq.$deviceId&is_acknowledged=eq.false"
        }

        val updatePayload = JSONObject().apply {
            put("is_acknowledged", true)
            put("acknowledged_at", nowIso)
        }

        val request = Request.Builder()
            .url(url)
            .patch(updatePayload.toString().toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()))
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .addHeader("Prefer", "return=minimal")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.w(TAG, "Failed to update device_messages in DB: ${e.message}")
                onComplete?.invoke(false)
            }
            override fun onResponse(call: Call, response: Response) {
                val success = response.isSuccessful
                response.close()
                Log.i(TAG, "Updated device_messages in DB: success=$success")
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
        val payload = JSONObject().apply {
            put("device_id", deviceId)
            put("requested_minutes", minutes)
            put("reason", reason)
            put("timestamp", System.currentTimeMillis())
        }
        sendBroadcast(topic, "TIME_REQUEST", payload)
        Log.i(TAG, "Sent TIME_REQUEST: +$minutes mins, reason=$reason")

        // Ghi nhận bản ghi vào bảng time_requests để kích hoạt Postgres Realtime trên Admin
        val url = "$supabaseUrl/rest/v1/time_requests"
        val postPayload = JSONObject().apply {
            put("device_id", deviceId)
            put("requested_minutes", minutes)
            put("reason", reason)
            put("status", "pending")
        }

        val request = Request.Builder()
            .url(url)
            .post(postPayload.toString().toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull()))
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .addHeader("Prefer", "return=minimal")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.w(TAG, "Failed to insert time_requests in DB: ${e.message}")
                onResult(true) // Broadcast was already sent
            }
            override fun onResponse(call: Call, response: Response) {
                response.close()
                Log.i(TAG, "Inserted time_requests in DB: status=${response.code}")
                onResult(true)
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

    companion object {
        private const val TAG = "MdmSupabaseClient"
    }
}
