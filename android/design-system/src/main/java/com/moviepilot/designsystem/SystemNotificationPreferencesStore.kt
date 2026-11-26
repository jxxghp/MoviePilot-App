package com.moviepilot.designsystem

import android.content.Context
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Android 手机系统通知栏推送偏好存储：
 * 控制是否将 MoviePilot 系统通知（订阅、入库、下载、站点等）与插件通知（`post_message`）同步投递至系统状态栏。
 */
@Stable
class SystemNotificationPreferencesStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    var systemBarNotificationsEnabled by mutableStateOf(prefs.getBoolean(KEY_ENABLED, true))
        private set

    var includePluginNotifications by mutableStateOf(prefs.getBoolean(KEY_INCLUDE_PLUGIN, true))
        private set

    var includeSystemNotifications by mutableStateOf(prefs.getBoolean(KEY_INCLUDE_SYSTEM, true))
        private set

    var hasPromptedPermission by mutableStateOf(prefs.getBoolean(KEY_PROMPTED_PERMISSION, false))
        private set

    fun updateEnabled(enabled: Boolean) {
        systemBarNotificationsEnabled = enabled
        prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun updateIncludePlugin(enabled: Boolean) {
        includePluginNotifications = enabled
        prefs.edit().putBoolean(KEY_INCLUDE_PLUGIN, enabled).apply()
    }

    fun updateIncludeSystem(enabled: Boolean) {
        includeSystemNotifications = enabled
        prefs.edit().putBoolean(KEY_INCLUDE_SYSTEM, enabled).apply()
    }

    fun markPermissionPrompted() {
        if (!hasPromptedPermission) {
            hasPromptedPermission = true
            prefs.edit().putBoolean(KEY_PROMPTED_PERMISSION, true).apply()
        }
    }

    companion object {
        const val PREFS_NAME = "mp_system_notification_prefs_v1"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_INCLUDE_PLUGIN = "include_plugin"
        private const val KEY_INCLUDE_SYSTEM = "include_system"
        private const val KEY_PROMPTED_PERMISSION = "prompted_permission"
    }
}
