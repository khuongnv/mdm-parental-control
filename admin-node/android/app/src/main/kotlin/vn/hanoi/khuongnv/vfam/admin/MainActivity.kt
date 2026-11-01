package vn.hanoi.khuongnv.vfam.admin

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "vn.hanoi.khuongnv.vfam.admin/updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCacheDirectory" -> {
                    result.success(cacheDir.absolutePath)
                }
                "getAppVersion" -> {
                    try {
                        val pInfo = packageManager.getPackageInfo(packageName, 0)
                        result.success(pInfo.versionName ?: "1.1.0")
                    } catch (e: Exception) {
                        result.success("1.1.0")
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_ARGUMENT", "Đường dẫn file APK không hợp lệ", null)
                        return@setMethodCallHandler
                    }

                    val apkFile = File(filePath)
                    if (!apkFile.exists()) {
                        result.error("FILE_NOT_FOUND", "Không tìm thấy file APK tại: $filePath", null)
                        return@setMethodCallHandler
                    }

                    // Kiểm tra quyền cài đặt ứng dụng không rõ nguồn gốc trên Android 8.0+
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        if (!packageManager.canRequestPackageInstalls()) {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.error("PERMISSION_DENIED", "Vui lòng cấp quyền cài đặt ứng dụng từ nguồn này rồi thử lại", null)
                            return@setMethodCallHandler
                        }
                    }

                    try {
                        apkFile.setReadable(true, false)
                        val apkUri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apkFile
                        )

                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(apkUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        // Cấp quyền đọc URI cho installer
                        val resolveList = packageManager.queryIntentActivities(installIntent, 0)
                        for (resolveInfo in resolveList) {
                            grantUriPermission(
                                resolveInfo.activityInfo.packageName,
                                apkUri,
                                Intent.FLAG_GRANT_READ_URI_PERMISSION
                            )
                        }

                        startActivity(installIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", "Lỗi khởi động trình cài đặt: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
