package com.mediamix.shared.spider

import com.mediamix.shared.models.*

/**
 * Java Bridge 蜘蛛适配器（骨架）
 *
 * 通过本地 HTTP 桥接调用 TVBox Java 蜘蛛（csp_*Guard 等）。
 * Java 端负责加载 JAR 并通过反射调用蜘蛛方法，
 * Kotlin 端通过 JavaBridgeManager 发起 HTTP 请求获取结果。
 *
 * TODO: JavaBridgeManager 在 Task 34 中实现，此处仅写接口调用桩代码
 */
class JavaBridgeSpider(
    private val site: TvBoxSite,
    // TODO: 依赖 JavaBridgeManager (Task 34)
    // private val bridgeManager: JavaBridgeManager,
) : SpiderAdapter {

    override val key: String get() = site.key
    override val name: String get() = site.name
    override val type: SpiderType get() = SpiderType.JAVA_BRIDGE

    override val isSearchSupported: Boolean
        get() = site.searchable // TVBox 站点的 searchable 字段

    override suspend fun init(config: Map<String, Any>) {
        // TODO: 调用 bridgeManager.initSpider(site.key, config)
    }

    override suspend fun homeContent(page: Int): SpiderHomeResult {
        // TODO: 调用 bridgeManager.homeContent(site.key, page)
        return SpiderHomeResult()
    }

    override suspend fun categoryContent(
        tid: String,
        page: Int,
        filter: Map<String, String>?,
    ): SpiderListResult {
        // TODO: 调用 bridgeManager.categoryContent(site.key, tid, page, filter)
        return SpiderListResult()
    }

    override suspend fun detailContent(id: String): SpiderDetailResult {
        // TODO: 调用 bridgeManager.detailContent(site.key, id)
        return SpiderDetailResult(
            detail = VideoDetail(vodId = id, vodName = "未知", sourceKey = key)
        )
    }

    override suspend fun searchContent(keyword: String, page: Int): SpiderListResult {
        // TODO: 调用 bridgeManager.searchContent(site.key, keyword, page)
        return SpiderListResult()
    }

    override suspend fun playerContent(flag: String, id: String): SpiderPlayResult {
        // TODO: 调用 bridgeManager.playerContent(site.key, flag, id)
        return SpiderPlayResult(url = id)
    }

    override fun dispose() {
        // JavaBridgeSpider 不直接 dispose bridgeManager，由 JavaBridgeManager 统一管理
    }

    // ==================== 响应解析（完整实现，待 JavaBridgeManager 就绪后启用） ====================

    /**
     * 从 Bridge 响应中提取 data 字段
     *
     * 对应 Dart 的 _extractData()
     */
    fun extractData(result: Map<String, Any>): Map<String, Any>? {
        val data = result["data"] ?: return null
        val mapData = JsonSpider.asStringMap(data)
        if (mapData != null) return mapData
        if (data is String) {
            try {
                val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                val element = json.parseToJsonElement(data)
                val map = JsonSpider.jsonElementToMap(element)
                if (map != null) return map
                // 如果是数组，包装为 { "list": [...] }
                if (element is kotlinx.serialization.json.JsonArray) {
                    return mapOf("list" to (JsonSpider.jsonElementToAny(element) ?: emptyList<Any>()))
                }
            } catch (_: Exception) {}
        }
        return null
    }

    /** 解析视频列表 */
    fun parseVideoList(raw: Any?): List<VideoItem> {
        if (raw !is List<*>) return emptyList()
        val result = mutableListOf<VideoItem>()
        for (item in raw) {
            val map = JsonSpider.asStringMap(item) ?: continue
            try {
                result.add(VideoItem.fromJson(map, sourceKey = key))
            } catch (_: Exception) {
                // 跳过解析失败的条目
            }
        }
        return result
    }

    /** 安全转为 Int */
    fun intValue(v: Any?): Int {
        return when (v) {
            is Int -> v
            is String -> v.toIntOrNull() ?: 0
            is Double -> v.toInt()
            is Long -> v.toInt()
            else -> 0
        }
    }
}
