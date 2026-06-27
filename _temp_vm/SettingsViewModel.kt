package com.mediamix.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.russhwolf.settings.Settings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import co.touchlab.kermit.Logger

/**
 * 主题模式枚举
 */
enum class ThemeModeOption {
    SYSTEM, LIGHT, DARK
}

/**
 * 缓存统计信息
 */
data class CacheStatsInfo(
    val memoryCacheSize: Long = 0L,
    val diskCacheSize: Long = 0L,
    val totalSize: Long = 0L,
)

/**
 * 设置 ViewModel
 * 替代: themeModeProvider, privacyPreferencesProvider, cacheStatsProvider
 */
class SettingsViewModel(
    private val settings: Settings,
) : ViewModel() {

    private val logger = Logger.withTag("SettingsViewModel")
    private val themeKey = "theme_mode"

    private val _themeMode = MutableStateFlow(ThemeModeOption.SYSTEM)
    val themeMode: StateFlow<ThemeModeOption> = _themeMode.asStateFlow()

    private val _cacheStats = MutableStateFlow(CacheStatsInfo())
    val cacheStats: StateFlow<CacheStatsInfo> = _cacheStats.asStateFlow()

    init {
        val savedIndex = settings.getInt(themeKey, 0)
        _themeMode.value = ThemeModeOption.entries.getOrElse(savedIndex) { ThemeModeOption.SYSTEM }
    }

    fun setThemeMode(mode: ThemeModeOption) {
        _themeMode.value = mode
        settings.putInt(themeKey, mode.ordinal)
        logger.d { "Theme mode set: $mode" }
    }

    fun exportData(): String {
        // TODO: export user data (favorites, history) as JSON
        logger.d { "Export data (placeholder)" }
        return "{}"
    }

    fun clearCache() {
        viewModelScope.launch {
            try {
                // TODO: clear VideoCacheService and DiskCache
                _cacheStats.value = CacheStatsInfo()
                logger.d { "Cache cleared" }
            } catch (e: Exception) {
                logger.e { "Clear cache failed: ${e.message}" }
            }
        }
    }

    fun refreshCacheStats() {
        viewModelScope.launch {
            // TODO: get actual stats from VideoCacheService
            _cacheStats.value = CacheStatsInfo()
        }
    }
}
