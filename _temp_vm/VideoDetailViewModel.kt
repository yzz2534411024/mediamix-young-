package com.mediamix.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mediamix.shared.models.VideoDetail
import com.mediamix.shared.models.VideoItem
import com.mediamix.shared.spider.SpiderService
import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonArray
import co.touchlab.kermit.Logger

/**
 * 详情页 ViewModel
 * 替代: videoDetailProvider, isFavoriteProvider, relatedVideosProvider
 */
class VideoDetailViewModel(
    private val httpClient: HttpClient,
    private val spiderService: SpiderService,
) : ViewModel() {

    private val logger = Logger.withTag("VideoDetailViewModel")
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val _detail = MutableStateFlow<VideoDetail?>(null)
    val detail: StateFlow<VideoDetail?> = _detail.asStateFlow()

    private val _isFavorite = MutableStateFlow(false)
    val isFavorite: StateFlow<Boolean> = _isFavorite.asStateFlow()

    private val _relatedVideos = MutableStateFlow<List<VideoItem>>(emptyList())
    val relatedVideos: StateFlow<List<VideoItem>> = _relatedVideos.asStateFlow()

    private val _selectedSourceIndex = MutableStateFlow(0)
    val selectedSourceIndex: StateFlow<Int> = _selectedSourceIndex.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    fun loadDetail(vodId: String, sourceKey: String, apiUrl: String) {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            try {
                val url = "${apiUrl}?ac=detail&ids=${vodId}"
                val response = httpClient.get(url)
                val text = response.bodyAsText()
                val jsonObj = json.parseToJsonElement(text).jsonObject
                val listArr = jsonObj["list"]?.jsonArray
                if (!listArr.isNullOrEmpty()) {
                    val firstObj = listArr[0].jsonObject
                    _detail.value = VideoDetail.fromJson(firstObj.toMap().mapValues { it.value }, sourceKey = sourceKey)
                }
            } catch (e: Exception) {
                logger.e { "Load detail failed: ${e.message}" }
                _error.value = e.message
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun toggleFavorite() {
        _isFavorite.value = !_isFavorite.value
        // TODO: persist via SQLDelight DAO
    }

    fun selectSource(index: Int) {
        _selectedSourceIndex.value = index
    }

    fun loadRelated(apiUrl: String, typeId: Int?, excludeVodId: String) {
        if (typeId == null) return
        viewModelScope.launch {
            try {
                val url = "${apiUrl}?ac=detail&t=${typeId}&pg=1"
                val response = httpClient.get(url)
                val text = response.bodyAsText()
                val jsonObj = json.parseToJsonElement(text).jsonObject
                val listArr = jsonObj["list"]?.jsonArray ?: emptyList()
                _relatedVideos.value = listArr
                    .mapNotNull { it.jsonObject.let { obj ->
                        VideoItem(
                            vodId = obj["vod_id"]?.toString()?.trim('"') ?: "",
                            vodName = obj["vod_name"]?.toString()?.trim('"') ?: "",
                            vodPic = obj["vod_pic"]?.toString()?.trim('"'),
                        )
                    }}
                    .filter { it.vodId != excludeVodId }
                    .take(20)
            } catch (e: Exception) {
                logger.e { "Load related failed: ${e.message}" }
                _relatedVideos.value = emptyList()
            }
        }
    }
}
