package com.jarvis.assistant

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {
    private val channelName = "com.jarvis.assistant/device_insights"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openUsageAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(true)
                    }
                    "getWeeklyAppUsage" -> {
                        if (!hasUsageAccess()) {
                            result.error("USAGE_ACCESS_REQUIRED", "Enable Usage Access for Jarvis in Android Settings.", null)
                        } else {
                            result.success(readWeeklyUsage())
                        }
                    }
                    "getDeviceMetrics" -> result.success(readDeviceMetrics())
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun readWeeklyUsage(): List<Map<String, Any>> {
        val now = System.currentTimeMillis()
        val start = Calendar.getInstance().apply { timeInMillis = now; add(Calendar.DAY_OF_YEAR, -7) }.timeInMillis
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, now)
        val totals = mutableMapOf<String, Long>()
        for (item in stats) {
            if (item.packageName == packageName || item.totalTimeInForeground <= 0L) continue
            totals[item.packageName] = (totals[item.packageName] ?: 0L) + item.totalTimeInForeground
        }
        return totals.entries.sortedByDescending { it.value }.take(100).map { entry ->
            val label = try {
                @Suppress("DEPRECATION")
                packageManager.getApplicationLabel(packageManager.getApplicationInfo(entry.key, 0)).toString()
            } catch (_: Exception) { entry.key }
            mapOf("app_id" to entry.key, "app_label" to label, "foreground_seconds" to (entry.value / 1000L))
        }
    }

    private fun readDeviceMetrics(): Map<String, Any?> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        val memory = android.app.ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memory)
        val stat = android.os.StatFs(filesDir.absolutePath)
        val battery = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
        val pct = if (level >= 0 && scale > 0) level * 100.0 / scale else null
        val plugged = (battery?.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        return mapOf(
            "memory_total_bytes" to memory.totalMem,
            "memory_used_bytes" to (memory.totalMem - memory.availMem),
            "memory_percent" to if (memory.totalMem > 0) (memory.totalMem - memory.availMem) * 100.0 / memory.totalMem else null,
            "disk_free_bytes" to stat.availableBytes,
            "disk_percent" to if (stat.totalBytes > 0) (stat.totalBytes - stat.availableBytes) * 100.0 / stat.totalBytes else null,
            "battery_percent" to pct,
            "battery_plugged" to plugged
        )
    }
}
