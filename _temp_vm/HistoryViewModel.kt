package com.mediamix.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import co.touchlab.kermit.Logger

/**
 * 观看历史数据模型
 */
data class WatchHistoryItem(
    val id: String,
    val vodId: String,
    val vodName: String,
    val vodPic: String? = null,
    val sourceKey: String,
    val episodeName: String? = null,
    val lastWatchTime: Long = 0L,
)

/**
 * 观看历史 ViewModel
 * 替代: watchHistoryProvider (StreamProvider), watchHistoryActionsProvider
 * SQLDelight DAO 占位实现，预留 Flow 接口。
 */
class HistoryViewModel : ViewModel() {

    private val logger = Logger.withTag("HistoryViewModel")

    private val _histories = MutableStateFlow<List<WatchHistoryItem>>(emptyList())
    val histories: StateFlow<List<WatchHistoryItem>> = _histories.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    fun loadHistories() {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                // TODO: connect SQLDelight DAO
                logger.d { "Loading watch history (placeholder)" }
            } catch (e: Exception) {
                logger.e { "Load history failed: ${e.message}" }
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun addOrUpdateHistory(
        vodId: String,
        vodName: String,
        vodPic: String?,
        sourceKey: String,
        episodeName: String?,
    ) {
        viewModelScope.launch {
            // TODO: connect SQLDelight DAO
            logger.d { "Add/update history: $vodName" }
        }
    }

    fun deleteHistory(id: String) {
        viewModelScope.launch {
            _histories.value = _histories.value.filter { it.id != id }
            logger.d { "Delete history: $id" }
        }
    }

    fun clearAll() {
        viewModelScope.launch {
            _histories.value = emptyList()
            logger.d { "Clear all history" }
        }
    }
}
