package vn.hanoi.khuongnv.vfam.admin

import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.fonts.SystemFonts
import android.os.Build
import java.io.File
import kotlin.math.abs

object SystemFontHelper {
    /**
     * Lấy dữ liệu font hệ thống Android đang kích hoạt (cả regular và bold nếu có).
     * Trả về Map chứa byte array của regular và bold font.
     */
    fun getSystemFontData(): Map<String, ByteArray>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val fallback = File("/system/fonts/Roboto-Regular.ttf")
            return if (fallback.exists() && fallback.canRead()) {
                mapOf("regular" to fallback.readBytes())
            } else null
        }

        try {
            val availableFonts = SystemFonts.getAvailableFonts()
            val regularFile = findMatchingFont(Typeface.DEFAULT, availableFonts)
            val boldFile = findMatchingFont(Typeface.defaultFromStyle(Typeface.BOLD), availableFonts)

            val resultMap = mutableMapOf<String, ByteArray>()
            if (regularFile != null && regularFile.exists() && regularFile.canRead()) {
                resultMap["regular"] = regularFile.readBytes()
            }
            if (boldFile != null && boldFile.exists() && boldFile.canRead() && boldFile.absolutePath != regularFile?.absolutePath) {
                resultMap["bold"] = boldFile.readBytes()
            }

            if (resultMap.isNotEmpty()) {
                return resultMap
            }

            // Fallback danh sách font phổ biến trên Samsung/Android
            val candidates = listOf(
                "/system/fonts/SamsungSans.ttf",
                "/system/fonts/SECRobotoLight-Regular.ttf",
                "/system/fonts/SamsungOne-Regular.ttf",
                "/system/fonts/Roboto-Regular.ttf"
            )
            for (path in candidates) {
                val f = File(path)
                if (f.exists() && f.canRead()) {
                    return mapOf("regular" to f.readBytes())
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return null
    }

    private fun findMatchingFont(targetTypeface: Typeface, availableFonts: Set<android.graphics.fonts.Font>): File? {
        val targetMetrics = Paint().apply {
            typeface = targetTypeface
            textSize = 100f
        }.fontMetrics

        var bestFile: File? = null
        var minDiff = Float.MAX_VALUE

        for (font in availableFonts) {
            val file = font.file ?: continue
            if (!file.exists() || !file.canRead()) continue
            val path = file.absolutePath

            // Bỏ qua font biểu tượng cảm xúc hoặc đơn khoảng
            if (path.contains("Mono", ignoreCase = true) ||
                path.contains("Emoji", ignoreCase = true) ||
                path.contains("Color", ignoreCase = true) ||
                path.contains("Clock", ignoreCase = true)
            ) {
                continue
            }

            val testMetrics = Paint().apply {
                typeface = Typeface.createFromFile(file)
                textSize = 100f
            }.fontMetrics

            val diff = abs(targetMetrics.ascent - testMetrics.ascent) +
                    abs(targetMetrics.descent - testMetrics.descent) +
                    abs(targetMetrics.top - testMetrics.top) +
                    abs(targetMetrics.bottom - testMetrics.bottom)

            if (diff < minDiff) {
                minDiff = diff
                bestFile = file
                if (diff < 0.0001f) {
                    break
                }
            }
        }

        return if (minDiff < 0.05f) bestFile else null
    }
}
