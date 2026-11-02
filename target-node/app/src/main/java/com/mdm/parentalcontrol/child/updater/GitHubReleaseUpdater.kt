package com.mdm.parentalcontrol.child.updater

import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import com.mdm.parentalcontrol.child.BuildConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GitHubReleaseUpdater @Inject constructor(
    @ApplicationContext private val context: Context
) {

    data class ReleaseInfo(
        val tagName: String,
        val apkDownloadUrl: String,
        val releaseNotes: String,
        val isNewer: Boolean
    )

    /**
     * So sánh Semantic Versioning: latestTag vs currentVersion
     */
    fun isNewerVersion(currentVersion: String, latestTag: String): Boolean {
        try {
            val curClean = currentVersion.trim().removePrefix("v").split("-")[0]
            val latClean = latestTag.trim().removePrefix("v").split("-")[0]

            val curParts = curClean.split(".").map { it.toIntOrNull() ?: 0 }
            val latParts = latClean.split(".").map { it.toIntOrNull() ?: 0 }

            val maxLen = maxOf(curParts.size, latParts.size)
            for (i in 0 until maxLen) {
                val cur = if (i < curParts.size) curParts[i] else 0
                val lat = if (i < latParts.size) latParts[i] else 0
                if (lat > cur) return true
                if (lat < cur) return false
            }
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error comparing versions", e)
            return false
        }
    }

    /**
     * Kiểm tra phiên bản mới nhất từ GitHub Releases API
     */
    suspend fun checkLatestRelease(
        repoOwner: String = "khuongnv",
        repoName: String = "mdm-parental-control",
        currentVersion: String = BuildConfig.VERSION_NAME
    ): ReleaseInfo? = withContext(Dispatchers.IO) {
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

                // 1. Ưu tiên tìm tệp apk dành riêng cho child
                for (i in 0 until assets.length()) {
                    val asset = assets.getJSONObject(i)
                    val name = asset.getString("name").lowercase()
                    if (name.contains("child") || name.contains("target")) {
                        downloadUrl = asset.getString("browser_download_url")
                        break
                    }
                }

                // 2. Fallback nếu không thấy tag child riêng nhưng là file apk đơn lẻ
                if (downloadUrl == null) {
                    for (i in 0 until assets.length()) {
                        val asset = assets.getJSONObject(i)
                        val name = asset.getString("name").lowercase()
                        if (name.endsWith(".apk") && !name.contains("admin")) {
                            downloadUrl = asset.getString("browser_download_url")
                            break
                        }
                    }
                }

                if (downloadUrl != null) {
                    val isNewer = isNewerVersion(currentVersion, tagName)
                    return@withContext ReleaseInfo(tagName, downloadUrl, body, isNewer)
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
     * Tải tệp APK về thư mục cache với báo cáo tiến độ %
     */
    suspend fun downloadApk(
        downloadUrl: String,
        destinationFile: File,
        onProgress: (Int) -> Unit
    ): Boolean = withContext(Dispatchers.IO) {
        var conn: HttpURLConnection? = null
        try {
            val url = URL(downloadUrl)
            conn = url.openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = true
            conn.connectTimeout = 15000
            conn.readTimeout = 15000

            // Xử lý chuyển hướng nếu có
            var redirectCode = conn.responseCode
            var redirectedUrl = downloadUrl
            var redirectCount = 0
            while ((redirectCode == HttpURLConnection.HTTP_MOVED_TEMP ||
                        redirectCode == HttpURLConnection.HTTP_MOVED_PERM ||
                        redirectCode == 307 || redirectCode == 308) && redirectCount < 5) {
                redirectedUrl = conn?.getHeaderField("Location") ?: break
                conn?.disconnect()
                val nextUrl = URL(redirectedUrl)
                conn = nextUrl.openConnection() as HttpURLConnection
                conn.instanceFollowRedirects = true
                redirectCode = conn.responseCode
                redirectCount++
            }

            val activeConn = conn ?: return@withContext false
            if (activeConn.responseCode != HttpURLConnection.HTTP_OK) {
                Log.e(TAG, "Server returned HTTP ${activeConn.responseCode}")
                return@withContext false
            }

            val totalBytes = activeConn.contentLength.toLong()
            var downloadedBytes = 0L

            activeConn.inputStream.use { input ->
                FileOutputStream(destinationFile).use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        downloadedBytes += bytesRead
                        if (totalBytes > 0) {
                            val percent = ((downloadedBytes * 100) / totalBytes).toInt()
                            onProgress(percent)
                        }
                    }
                    output.flush()
                }
            }
            onProgress(100)
            return@withContext true
        } catch (e: Exception) {
            Log.e(TAG, "Error downloading APK", e)
            return@withContext false
        } finally {
            conn?.disconnect()
        }
    }

    /**
     * Cài đặt APK: Nếu là Device Owner thì silent install ngầm, nếu không thì mở Intent PackageInstaller
     */
    fun installApk(apkFile: File) {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
        if (dpm != null && dpm.isDeviceOwnerApp(context.packageName)) {
            Log.i(TAG, "Installing APK silently as Device Owner")
            installApkSilentlyAsDeviceOwner(apkFile)
        } else {
            Log.i(TAG, "Installing APK via standard Intent")
            try {
                val contentUri: Uri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    apkFile
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(contentUri, "application/vnd.android.package-archive")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch standard APK installer", e)
            }
        }
    }

    /**
     * Tự động cài đặt APK ngầm không cần xác nhận người dùng nhờ đặc quyền Device Owner (Silent Install)
     */
    fun installApkSilentlyAsDeviceOwner(apkFile: File) {
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
