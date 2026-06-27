package com.mediamix.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mediamix.shared.models.CmsApiSite
import com.mediamix.shared.models.SourceStatus
import com.mediamix.shared.spider.SpiderService
import io.ktor.client.HttpClient
import io.ktor.client.request.get
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.datetime.Clock
import co.touchlab.kermit.Logger

/**
 * 源管理 ViewModel
 * 替代: cmsSiteListProvider, sourceStatusProvider, sourceActionsProvider
 */
class SourceManageViewModel(
    private val httpClient: HttpClient,
    private val spiderService: SpiderService,
) : ViewModel() {

    private val logger = Logger.withTag("SourceManageViewModel")

    private val _sites = MutableStateFlow<List<CmsApiSite>>(CmsApiSite.defaultSites)
    val sites: StateFlow<List<CmsApiSite>> = _sites.asStateFlow()

    private val _sourceStatuses = MutableStateFlow<Map<String, SourceStatus>>(emptyMap())
    val sourceStatuses: StateFlow<Map<String, SourceStatus>> = _sourceStatuses.asStateFlow()

    private val _isChecking = MutableStateFlow(false)
    val isChecking: StateFlow<Boolean> = _isChecking.asStateFlow()

    fun loadSources() {
        _sites.value = CmsApiSite.defaultSites
    }

    fun addSource(config: CmsApiSite) {
        val current = _sites.value
        if (current.any { it.key == config.key }) return
        _sites.value = current + config
    }

    fun removeSource(key: String) {
        val current = _sites.value
        val site = current.find { it.key == key } ?: return
        if (site.isBuiltIn) return
        _sites.value = current.filter { it.key != key }
        _sourceStatuses.value = _sourceStatuses.value.toMutableMap().apply { remove(key) }
    }

    fun toggleSourceEnabled(key: String) {
        _sites.value = _sites.value.map { site ->
            if (site.key == key) site.copy(enabled = !site.enabled) else site
        }
    }

    fun checkSource(site: CmsApiSite) {
        viewModelScope.launch {
            try {
                val startTime = Clock.System.now().toEpochMilliseconds()
                withTimeout(10_000) {
                    httpClient.get(site.apiUrl)
                }
                val elapsed = (Clock.System.now().toEpochMilliseconds() - startTime).toInt()
                val status = SourceStatus(key = site.key, isAvailable = true, latencyMs = elapsed)
                _sourceStatuses.value = _sourceStatuses.value + (site.key to status)
            } catch (e: Exception) {
                val status = SourceStatus(key = site.key, isAvailable = false, latencyMs = -1, error = e.message)
                _sourceStatuses.value = _sourceStatuses.value + (site.key to status)
            }
        }
    }

    fun checkAllSources() {
        viewModelScope.launch {
            _isChecking.value = true
            try {
                coroutineScope {
                    val deferredList = _sites.value.map { site ->
                        async {
                            try {
                                val startTime = Clock.System.now().toEpochMilliseconds()
                                withTimeout(10_000) {
                                    httpClient.get(site.apiUrl)
                                }
                                val elapsed = (Clock.System.now().toEpochMilliseconds() - startTime).toInt()
                                SourceStatus(key = site.key, isAvailable = true, latencyMs = elapsed)
                            } catch (e: Exception) {
                                SourceStatus(key = site.key, isAvailable = false, latencyMs = -1, error = e.message)
                            }
                        }
                    }
                    deferredList.forEach { deferred ->
                        val status = deferred.await()
                        _sourceStatuses.value = _sourceStatuses.value + (status.key to status)
                    }
                }
            } catch (e: Exception) {
                logger.e { "Check all sources failed: ${e.message}" }
            } finally {
                _isChecking.value = false
            }
        }
    }
}
