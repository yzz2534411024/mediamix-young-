package com.mediamix.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import co.touchlab.kermit.Logger

/**
 * 收藏数据模型
 */
data class FavoriteItem(
    val id: String,
    val vodId: String,
    val vodName: String,
    val vodPic: String? = null,
    val sourceKey: String,
    val typeName: String? = null,
    val lastEpisodeCount: Int = 0,
    val addTime: Long = 0L,
)

/**
 * 收藏 ViewModel
 * 替代: favoriteListProvider (StreamProvider), favoriteActionsProvider
 * SQLDelight DAO 占位实现。
 */
class FavoriteViewModel : ViewModel() {

    private val logger = Logger.withTag("FavoriteViewModel")

    private val _favorites = MutableStateFlow<List<FavoriteItem>>(emptyList())
    val favorites: StateFlow<List<FavoriteItem>> = _favorites.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    fun loadFavorites() {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                // TODO: connect SQLDelight DAO
                logger.d { "Loading favorites (placeholder)" }
            } catch (e: Exception) {
                logger.e { "Load favorites failed: ${e.message}" }
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun toggleFavorite(
        vodId: String,
        vodName: String,
        vodPic: String?,
        sourceKey: String,
        typeName: String?,
        episodeCount: Int,
    ) {
        viewModelScope.launch {
            val existing = _favorites.value.find { it.vodId == vodId }
            if (existing != null) {
                _favorites.value = _favorites.value.filter { it.vodId != vodId }
                logger.d { "Removed favorite: $vodName" }
            } else {
                val newItem = FavoriteItem(
                    id = vodId,
                    vodId = vodId,
                    vodName = vodName,
                    vodPic = vodPic,
                    sourceKey = sourceKey,
                    typeName = typeName,
                    lastEpisodeCount = episodeCount,
                    addTime = Clock.System.now().toEpochMilliseconds(),
                )
                _favorites.value = _favorites.value + newItem
                logger.d { "Added favorite: $vodName" }
            }
        }
    }

    fun removeFavorite(id: String) {
        viewModelScope.launch {
            _favorites.value = _favorites.value.filter { it.id != id }
            logger.d { "Removed favorite: $id" }
        }
    }

    fun isFavorite(vodId: String): Boolean {
        return _favorites.value.any { it.vodId == vodId }
    }
}
