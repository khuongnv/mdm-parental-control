package com.mdm.parentalcontrol.child.updater

import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.net.HttpURLConnection
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GitHubReleaseUpdater @Inject constructor(
    private val context: Context
) {

    data class ReleaseInfo(
        val tagName: String,
        val apkDownloadUrl: String,
        val releaseNotes: String
    )

    /**
     * Kiểm tra phiên bản mới nhất từ GitHub Releases API
     */
    suspend fun checkLatestRelease(repoOwner: String, repoName: String): ReleaseInfo? = withContext(Dispatchers.IO) {
        val apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
        var conn: HttpURLConnection? = null
        try {
            val url = URL(apiUrl)
            conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.setRequestProperty("Accept", "application/vnd.github.v3+json")
            conn.setRequestProperty("User-Agent", "MDM-Child-Agent")
            conn.connectTimeout = 10000
            conn.readTimeout = 10000

            if (conn.responseCode == 200) {
                val responseText = conn.inputStream.bufferedReader().use { it.readText() }
                val json = JSONObject(responseText)
                val tagName = json.getString("tag_name")
                val body = json.optString("body", "")

                val assets = json.getJSONArray("assets")
                var downloadUrl: String? = null
                for (i in 0 until assets.length()) {
                    val asset = assets.getJSONObject(i)
                    val name = asset.getString("name")
                    if (name.contains("target-node") || name.contains("child") || name.endsWith(".apk")) {
                        downloadUrl = asset.getString("browser_download_url")
                        break
                    }
                }

                if (downloadUrl != null) {
                    return@withContext ReleaseInfo(tagName, downloadUrl, body)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking GitHub release", e)
        } finally {
            conn?.disconnect()
        }
        return@withContext null
    }

    /**
     * Tự động cài đặt APK ngầm không cần xác nhận người dùng nhờ đặc quyền Device Owner (Silent Install)
     */
    fun installApkSilentlyAsDeviceOwner(apkFile: File) {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
        if (dpm == null || !dpm.isDeviceOwnerApp(context.packageName)) {
            Log.w(TAG, "Not Device Owner. Cannot perform silent update.")
            return
        }

        try {
            val packageInstaller = context.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            val sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            val outStream = session.openWrite("package", 0, apkFile.length())
            val inStream = FileInputStream(apkFile)

            inStream.use { input ->
                outStream.use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }

            val intent = Intent(context, SilentInstallReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                sessionId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )

            session.commit(pendingIntent.intentSender)
            session.close()
            Log.i(TAG, "Silent install session committed successfully via Device Owner PackageInstaller.")
        } catch (e: Exception) {
            Log.e(TAG, "Failed silent install as DO", e)
        }
    }

    companion object {
        private const val TAG = "GitHubReleaseUpdater"
    }
}

class SilentInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        if (status == PackageInstaller.STATUS_SUCCESS) {
            Log.i("SilentInstallReceiver", "App updated successfully via GitHub Release silent install.")
        } else {
            Log.e("SilentInstallReceiver", "Silent install failed: $message (status: $status)")
        }
    }
}
