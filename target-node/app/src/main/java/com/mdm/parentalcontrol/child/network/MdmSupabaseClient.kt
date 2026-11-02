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
            put("p_agent_version", "1.0.0")
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
        val url = "$supabaseUrl/rest/v1/devices?id=eq.$deviceId"
        val payload = JSONObject().apply {
            put("battery_level", batteryLevel)
            put("is_charging", isCharging)
            put("current_app_name", currentApp)
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
     * Hỗ trợ đầy đủ các sự kiện Giai đoạn 2: Panic Lockdown, Thưởng/Phạt động, Tin nhắn phụ huynh, Duyệt xin giờ, Hủy ghép nối
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
        disconnect()

        val host = supabaseUrl.replace("https://", "").replace("http://", "")
        val wsUrl = "wss://$host/realtime/v1/websocket?apikey=$anonKey&vsn=1.0.0"
        val topic = "realtime:device:$deviceId"

        val request = Request.Builder().url(wsUrl).build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.i(TAG, "Connected to Supabase Realtime WebSocket")
                isConnected = true

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
                                onPanicLockdown(isLocked)
                            }
                            "GRANT_EXTRA_TIME" -> {
                                val minutes = innerPayload?.optInt("extra_minutes", 15) ?: 15
                                Log.i(TAG, "⏳ Supabase Realtime received GRANT_EXTRA_TIME: +$minutes minutes")
                                onExtraTime(minutes)
                                onAdjustTime?.invoke(minutes, "Thưởng giờ chơi")
                            }
                            "ADJUST_SCREEN_TIME" -> {
                                val delta = innerPayload?.optInt("delta_minutes", 15) ?: 15
                                val reason = innerPayload?.optString("reason", "")
                                Log.i(TAG, "⚡ Supabase Realtime received ADJUST_SCREEN_TIME: delta=$delta, reason=$reason")
                                onAdjustTime?.invoke(delta, reason)
                                if (delta > 0) {
                                    onExtraTime(delta)
                                }
                            }
                            "REMOTE_MESSAGE" -> {
                                val msgId = innerPayload?.optString("message_id", "") ?: ""
                                val title = innerPayload?.optString("title", "🔔 Nhắc nhở từ Ba Mẹ") ?: "🔔 Nhắc nhở từ Ba Mẹ"
                                val body = innerPayload?.optString("body", "") ?: ""
                                val template = innerPayload?.optString("template_key", "custom")
                                Log.i(TAG, "💬 Supabase Realtime received REMOTE_MESSAGE: $title - $body")
                                onRemoteMessage?.invoke(msgId, title, body, template)
                            }
                            "TIME_REQUEST_RESOLVED" -> {
                                val status = innerPayload?.optString("status", "pending") ?: "pending"
                                val granted = innerPayload?.optInt("granted_minutes", 0) ?: 0
                                Log.i(TAG, "✅ Supabase Realtime received TIME_REQUEST_RESOLVED: $status (+$granted min)")
                                onTimeRequestResolved?.invoke(status, granted)
                            }
                            "DEVICE_UNPAIRED" -> {
                                Log.w(TAG, "⚠️ Supabase Realtime received DEVICE_UNPAIRED")
                                onDeviceUnpaired?.invoke()
                            }
                            "PAIRING_SUCCESS" -> {
                                Log.i(TAG, "✨ Supabase Realtime received PAIRING_SUCCESS!")
                                onPairingSuccess?.invoke()
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
                                    onPairingSuccess?.invoke()
                                }
                            } else {
                                val isLocked = record.optBoolean("is_locked", false)
                                val extraMins = record.optInt("extra_time_minutes", 0)
                                val familyId = record.optString("family_id", "")
                                val isUnpaired = record.optBoolean("is_unpaired", false)

                                if (isUnpaired) {
                                    Log.w(TAG, "⚡ Supabase Postgres Changes: device is_unpaired=true")
                                    onDeviceUnpaired?.invoke()
                                } else if (familyId.isNotEmpty() && familyId != "null") {
                                    onPairingSuccess?.invoke()
                                }

                                Log.w(TAG, "⚡ Supabase Postgres Changes: is_locked=$isLocked, extra_time=$extraMins")
                                onPanicLockdown(isLocked)
                                if (extraMins > 0) {
                                    onExtraTime(extraMins)
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error parsing Supabase message: $text", e)
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "Supabase WebSocket failure", t)
                isConnected = false
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "Supabase WebSocket closed: $reason")
                isConnected = false
            }
        })
    }

    /**
     * Gửi Broadcast Event qua Supabase Realtime Phoenix WebSocket
     */
    fun sendBroadcast(topic: String, eventName: String, payload: JSONObject) {
        val socket = webSocket ?: return
        val broadcastMsg = JSONObject().apply {
            put("topic", topic)
            put("event", "broadcast")
            put("payload", JSONObject().apply {
                put("type", "broadcast")
                put("event", eventName)
                put("payload", payload)
            })
            put("ref", System.currentTimeMillis().toString())
        }
        socket.send(broadcastMsg.toString())
    }

    /**
     * Máy con phản hồi xác nhận (ACK) khi bé nhấn vào tin nhắn nhắc nhở của phụ huynh
     */
    fun sendAckMessage(deviceId: String, messageId: String) {
        val topic = "realtime:device:$deviceId"
        val payload = JSONObject().apply {
            put("message_id", messageId)
            put("device_id", deviceId)
            put("status", "acknowledged")
            put("timestamp", System.currentTimeMillis())
        }
        sendBroadcast(topic, "ACK_MESSAGE", payload)
        Log.i(TAG, "Sent ACK_MESSAGE for msgId: $messageId")
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
        onResult(true)
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
