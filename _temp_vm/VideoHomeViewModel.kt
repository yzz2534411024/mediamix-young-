package com.mediamix.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mediamix.shared.models.CmsApiSite
import com.mediamix.shared.models.VideoCategory
import com.mediamix.shared.models.VideoItem
import com.mediamix.shared.models.VideoListResponse
import com.mediamix.shared.spider.SpiderService
import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import co.touchlab.kermit.Logger

/**
 * 首页 ViewModel
 * 替代: cmsSiteListProvider, currentSiteProvider, categoryListProvider,
 *       selectedCategoryProvider, videoListProvider, isTvBoxSourceProvider
 */
class VideoHomeViewModel(
    private val spiderService: SpiderService,
    private val httpClient: HttpClient,
) : ViewModel() {

    private val logger = Logger.withTag("VideoHomeViewModel")
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val _sites = MutableStateFlow<List<CmsApiSite>>(CmsApiSite.defaultSites)
    val sites: StateFlow<List<CmsApiSite>> = _sites.asStateFlow()

    private val _currentSite = MutableStateFlow<CmsApiSite?>(null)
    val currentSite: StateFlow<CmsApiSite?> = _currentSite.asStateFlow()

    private val _categories = MutableStateFlow<List<VideoCategory>>(emptyList())
    val categories: StateFlow<List<VideoCategory>> = _categories.asStateFlow()

    private val _selectedCategory = MutableStateFlow<VideoCategory?>(null)
    val selectedCategory: StateFlow<VideoCategory?> = _selectedCategory.asStateFlow()

    private val _videos = MutableStateFlow<List<VideoItem>>(emptyList())
    val videos: StateFlow<List<VideoItem>> = _videos.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _hasMore = MutableStateFlow(true)
    val hasMore: StateFlow<Boolean> = _hasMore.asStateFlow()

    private val _isTvBoxSource = MutableStateFlow(false)
    val isTvBoxSource: StateFlow<Boolean> = _isTvBoxSource.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private var currentPage = 1
    private var totalPages = 1

    init {
        val enabledSites = _sites.value.filter { it.enabled }
        if (enabledSites.isNotEmpty()) {
            _currentSite.value = enabledSites.first()
            _isTvBoxSource.value = enabledSites.first().isTvBox
        }
    }

    fun loadSites() {
        _sites.value = CmsApiSite.defaultSites
        val enabledSites = _sites.value.filter { it.enabled }
        if (enabledSites.isNotEmpty() && _currentSite.value == null) {
            selectSite(enabledSites.first())
        }
    }

    fun selectSite(site: CmsApiSite) {
        _currentSite.value = site
        _isTvBoxSource.value = site.isTvBox
        _selectedCategory.value = null
        _categories.value = emptyList()
        _videos.value = emptyList()
        currentPage = 1
        viewModelScope.launch {
            loadCategories()
            loadVideos()
        }
    }

    fun loadCategories() {
        val site = _currentSite.value ?: return
        viewModelScope.launch {
            try {
                if (site.isTvBox) {
                    val config = spiderService.fetchTvBoxConfig(site.apiUrl)
                    _categories.value = config.sites.mapIndexed { index, tvboxSite ->
                        VideoCategory(typeId = index + 1, typePid = 0, typeName = tvboxSite.name)
                    }
                } else {
                    val response = httpClient.get(site.apiUrl)
                    val text = response.bodyAsText()
                    val jsonObj = json.parseToJsonElement(text).jsonObject
                    val classArr = jsonObj["class"]?.jsonArray ?: emptyList()
                    _categories.value = classArr.map { elem ->
                        val obj = elem.jsonObject
                        VideoCategory(
                            typeId = obj["type_id"]?.jsonPrimitive?.int ?: 0,
                            typePid = obj["type_pid"]?.jsonPrimitive?.int ?: 0,
                            typeName = obj["type_name"]?.jsonPrimitive?.content ?: "",
                        )
                    }
                }
            } catch (e: Exception) {
                logger.e { "Load categories failed: ${e.message}" }
                _categories.value = emptyList()
            }
        }
    }

    fun selectCategory(category: VideoCategory?) {
        _selectedCategory.value = category
        _videos.value = emptyList()
        currentPage = 1
        viewModelScope.launch { loadVideos() }
    }

    fun loadVideos() {
        val site = _currentSite.value ?: return
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            try {
                if (site.isTvBox) {
                    loadSpiderVideos(site)
                } else {
                    loadCmsVideos(site)
                }
            } catch (e: Exception) {
                logger.e { "Load videos failed: ${e.message}" }
                _error.value = e.message
            } finally {
                _isLoading.value = false
            }
        }
    }

    private suspend fun loadCmsVideos(site: CmsApiSite) {
        val typeId = _selectedCategory.value?.typeId
        val page1 = fetchCmsPage(site.apiUrl, 1, typeId)
        val page2 = fetchCmsPage(site.apiUrl, 2, typeId)
        val merged = mergeVideoItems(page1.list + page2.list)
        _videos.value = merged
        currentPage = 2
        totalPages = page1.pageCount
        _hasMore.value = 2 < page1.pageCount
    }

    private suspend fun loadSpiderVideos(site: CmsApiSite) {
        val config = spiderService.fetchTvBoxConfig(site.apiUrl)
        val spiders = spiderService.initFromConfig(config)
        val category = _selectedCategory.value
        if (category != null) {
            val siteIndex = category.typeId - 1
            if (siteIndex in config.sites.indices) {
                val tvboxSite = config.sites[siteIndex]
                val spider = spiderService.getSpider(tvboxSite.key)
                if (spider != null) {
                    val result = spider.homeContent(page = 1)
                    _videos.value = result.recommend
                    _hasMore.value = false
                    return
                }
            }
            _videos.value = emptyList()
            return
        }
        val allItems = mutableListOf<VideoItem>()
        val seenIds = mutableSetOf<String>()
        for (spider in spiders) {
            try {
                val result = spider.homeContent(page = 1)
                for (item in result.recommend) {
                    if (seenIds.add(item.vodId)) allItems.add(item)
                }
            } catch (e: Exception) {
                logger.w { "Spider ${spider.key} home load failed: ${e.message}" }
            }
        }
        _videos.value = allItems
        _hasMore.value = false
    }

    fun loadMore() {
        if (_isLoading.value || !_hasMore.value) return
        val site = _currentSite.value ?: return
        if (site.isTvBox) return
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val nextPage = currentPage + 1
                val typeId = _selectedCategory.value?.typeId
                val response = fetchCmsPage(site.apiUrl, nextPage, typeId)
                _videos.value = _videos.value + response.list
                currentPage = response.page
                totalPages = response.pageCount
                _hasMore.value = response.page < response.pageCount
            } catch (e: Exception) {
                logger.e { "Load more failed: ${e.message}" }
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun refresh() {
        currentPage = 1
        _videos.value = emptyList()
        loadVideos()
    }

    private suspend fun fetchCmsPage(apiUrl: String, page: Int, typeId: Int?): VideoListResponse {
        val url = buildString {
            append(apiUrl)
            append(if (apiUrl.contains("?")) "&" else "?")
            append("pg=$page")
            if (typeId != null) append("&t=$typeId")
        }
        val response = httpClient.get(url)
        val text = response.bodyAsText()
        val jsonObj = json.parseToJsonElement(text).jsonObject
        val list = jsonObj["list"]?.jsonArray ?: emptyList()
        val items = list.map { elem ->
            val obj = elem.jsonObject
            VideoItem(
                vodId = obj["vod_id"]?.jsonPrimitive?.content ?: "",
                vodName = obj["vod_name"]?.jsonPrimitive?.content ?: "",
                vodPic = obj["vod_pic"]?.jsonPrimitive?.content,
                vodRemarks = obj["vod_remarks"]?.jsonPrimitive?.content,
                vodYear = obj["vod_year"]?.jsonPrimitive?.content,
                vodArea = obj["vod_area"]?.jsonPrimitive?.content,
                typeName = obj["type_name"]?.jsonPrimitive?.content,
            )
        }
        val pageCount = jsonObj["pagecount"]?.jsonPrimitive?.content?.toIntOrNull() ?: 1
        val currentPageNum = jsonObj["page"]?.jsonPrimitive?.content?.toIntOrNull() ?: page
        val total = jsonObj["total"]?.jsonPrimitive?.content?.toIntOrNull() ?: 0
        return VideoListResponse(list = items, page = currentPageNum, pageCount = pageCount, total = total)
    }

    private fun mergeVideoItems(items: List<VideoItem>): List<VideoItem> {
        val seen = mutableSetOf<String>()
        return items.filter { seen.add(it.vodId) }
    }
}
