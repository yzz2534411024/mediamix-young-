package com.mediamix.shared.spider

import com.mediamix.shared.models.*
import com.mediamix.shared.network.HttpClientFactory
import io.ktor.client.call.*
import io.ktor.client.request.*
import kotlinx.serialization.json.*

/**
 * JSON 蜘蛛 — 通过 JSON 路径 + 字段映射提取数据
 *
 * 迁移自：lib/features/video/services/spider/json_spider.dart
 */
class JsonSpider : SpiderAdapter {

    override val key: String = "json"
    override val name: String = "JSON 蜘蛛"
    override val type: SpiderType = SpiderType.JSON

    // 配置
    private var homeUrl: String = ""
    private var categoryUrl: String = ""
    private var detailUrl: String = ""
    private var searchUrl: String = ""
    private var playUrl: String = ""

    // 路径 / 映射
    private var homeListPath: String = ""
    private var homeListMap: Map<String, Any> = emptyMap()

    private var categoryListPath: String = ""
    private var categoryListMap: Map<String, Any> = emptyMap()

    private var detailPath: String = ""
    private var detailMap: Map<String, Any> = emptyMap()

    private var searchListPath: String = ""
    private var searchListMap: Map<String, Any> = emptyMap()

    private var playPath: String = ""
    private var playMap: Map<String, Any> = emptyMap()

    // 解析器
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    override suspend fun init(config: Map<String, Any>) {
        homeUrl = config["homeUrl"] as? String ?: ""
        categoryUrl = config["categoryUrl"] as? String ?: ""
        detailUrl = config["detailUrl"] as? String ?: ""
        searchUrl = config["searchUrl"] as? String ?: ""
        playUrl = config["playUrl"] as? String ?: ""

        homeListPath = config["homeListPath"] as? String ?: ""
        homeListMap = asStringMap(config["homeListMap"]) ?: emptyMap()

        categoryListPath = config["categoryListPath"] as? String ?: ""
        categoryListMap = asStringMap(config["categoryListMap"]) ?: emptyMap()

        detailPath = config["detailPath"] as? String ?: ""
        detailMap = asStringMap(config["detailMap"]) ?: emptyMap()

        searchListPath = config["searchListPath"] as? String ?: ""
        searchListMap = asStringMap(config["searchListMap"]) ?: emptyMap()

        playPath = config["playPath"] as? String ?: ""
        playMap = asStringMap(config["playMap"]) ?: emptyMap()
    }

    // ==================== 首页 ====================

    override suspend fun homeContent(page: Int): SpiderHomeResult {
        val data = fetchJson(homeUrl, mapOf("page" to page.toString()))
        val items = extractList(data, homeListPath, homeListMap)
        return SpiderHomeResult(
            categories = emptyList(),
            recommend = items.mapNotNull { VideoItem.fromJson(it) }
        )
    }

    // ==================== 分类 ====================

    override suspend fun categoryContent(tid: String, page: Int, filter: Map<String, String>?): SpiderListResult {
        val params = mutableMapOf("tid" to tid, "page" to page.toString())
        filter?.let { params.putAll(it) }
        val data = fetchJson(categoryUrl, params)
        val items = extractList(data, categoryListPath, categoryListMap)
        return SpiderListResult(list = items.mapNotNull { VideoItem.fromJson(it) })
    }

    // ==================== 详情 ====================

    override suspend fun detailContent(id: String): SpiderDetailResult {
        val data = fetchJson(detailUrl, mapOf("id" to id))
        val items = extractList(data, detailPath, detailMap)
        val item = items.firstOrNull()
        return SpiderDetailResult(detail = item?.let { VideoDetail.fromJson(it) })
    }

    // ==================== 搜索 ====================

    override suspend fun searchContent(keyword: String, page: Int): SpiderListResult {
        val data = fetchJson(searchUrl, mapOf("keyword" to keyword, "page" to page.toString()))
        val items = extractList(data, searchListPath, searchListMap)
        return SpiderListResult(list = items.mapNotNull { VideoItem.fromJson(it) })
    }

    // ==================== 播放 ====================

    override suspend fun playerContent(flag: String, id: String): SpiderPlayResult {
        if (playUrl.isEmpty()) {
            return SpiderPlayResult(url = id, parse = "0")
        }
        val data = fetchJson(playUrl, mapOf("flag" to flag, "id" to id))
        val playData = extractDetail(data, playPath, playMap)
        return SpiderPlayResult(
            url = playData["url"] as? String ?: id,
            parse = playData["parse"] as? String ?: "0",
            headers = asStringMap(playData["headers"])?.mapValues { it.value.toString() }
        )
    }

    override fun dispose() {}

    // ==================== 核心提取逻辑 ====================

    /**
     * 发起 HTTP 请求并返回解析后的 JSON
     */
    private suspend fun fetchJson(url: String, params: Map<String, String>): JsonElement {
        val resolvedUrl = buildUrl(url, params)
        val client = HttpClientFactory.createHttpClient()
        try {
            val response = client.get(resolvedUrl)
            val body = response.body<String>()
            return json.parseToJsonElement(body)
        } finally {
            client.close()
        }
    }

    /**
     * 通过 JSON 路径提取数据
     *
     * 路径格式：`data.list` 或 `$.data.list`
     */
    fun extractByPath(root: JsonElement, path: String): JsonElement? {
        if (path.isEmpty()) return root
        val segments = path.trimStart('$').trimStart('.').split('.').filter { it.isNotEmpty() }
        var current: JsonElement = root
        for (seg in segments) {
            current = when (current) {
                is JsonObject -> current[seg] ?: return null
                is JsonArray -> {
                    val index = seg.toIntOrNull() ?: return null
                    if (index < 0 || index >= current.size) return null
                    current[index]
                }
                else -> return null
            }
        }
        return current
    }

    /**
     * 提取列表
     */
    fun extractList(root: JsonElement, listPath: String, fieldMap: Map<String, Any>): List<Map<String, Any>> {
        val listElement = extractByPath(root, listPath) ?: return emptyList()
        val array = listElement as? JsonArray ?: return emptyList()
        return array.mapNotNull { element ->
            val obj = element as? JsonObject ?: return@mapNotNull null
            normalizeMap(obj, fieldMap)
        }
    }

    /**
     * 提取单条详情
     */
    private fun extractDetail(root: JsonElement, path: String, fieldMap: Map<String, Any>): Map<String, Any> {
        val element = extractByPath(root, path)
        if (element is JsonObject) {
            return normalizeMap(element, fieldMap)
        }
        return emptyMap()
    }

    /**
     * 字段映射：将 JSON 对象的字段按 fieldMap 映射为目标字段名
     *
     * fieldMap 格式：`{"vod_name": "title", "vod_pic": "cover", ...}`
     * 也支持嵌套路径：`{"vod_play_url.items": "sources"}`
     */
    fun normalizeMap(obj: JsonObject, fieldMap: Map<String, Any>): Map<String, Any> {
        if (fieldMap.isEmpty()) {
            // 无映射 — 直接转为 Map
            return jsonElementToMap(obj) ?: return emptyMap()
        }
        val result = mutableMapOf<String, Any>()
        for ((sourceKey, targetKey) in fieldMap) {
            val target = targetKey as? String ?: continue
            val value = extractByPath(obj, sourceKey)
            if (value != null && value !is JsonNull) {
                result[target] = jsonElementToAny(value) ?: continue
            }
        }
        return result
    }

    /**
     * 构建 URL（附加查询参数）
     */
    private fun buildUrl(base: String, params: Map<String, String>): String {
        if (params.isEmpty()) return base
        val query = params.entries.joinToString("&") { (k, v) ->
            "${encodeUrlComponent(k)}=${encodeUrlComponent(v)}"
        }
        return if (base.contains('?')) "$base&$query" else "$base?$query"
    }

    // ==================== 工具方法 ====================

    companion object {
        /** URL 编码 */
        fun encodeUrlComponent(value: String): String {
            return buildString {
                for (c in value) {
                    when {
                        c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c in "-_.~" -> append(c)
                        c == ' ' -> append("+")
                        else -> {
                            val bytes = c.toString().encodeToByteArray()
                            for (b in bytes) {
                                append('%')
                                append(((b.toInt() shr 4) and 0xF).toString(16).uppercase())
                                append((b.toInt() and 0xF).toString(16).uppercase())
                            }
                        }
                    }
                }
            }
        }

        /**
         * 安全地将 Any? 转为 Map<String, Any>
         * 避免泛型类型擦除导致的 is Map<String, Any> 检查失败
         */
        @Suppress("UNCHECKED_CAST")
        fun asStringMap(value: Any?): Map<String, Any>? {
            if (value is Map<*, *>) return value as Map<String, Any>
            return null
        }

        /**
         * 将 JsonElement 安全转为 Map<String, Any>
         */
        fun jsonElementToMap(element: JsonElement): Map<String, Any>? {
            val obj = element as? JsonObject ?: return null
            return obj.entries.associate { (k, v) -> k to jsonElementToAny(v) }
                .filterValues { it != null } as Map<String, Any>
        }

        /**
         * 将 JsonElement 递归转为普通 Kotlin 对象
         */
        fun jsonElementToAny(element: JsonElement): Any? {
            return when (element) {
                is JsonNull -> null
                is JsonObject -> {
                    element.entries.associate { (k, v) -> k to jsonElementToAny(v) }
                }
                is JsonArray -> {
                    element.map { jsonElementToAny(it) }
                }
                is JsonPrimitive -> {
                    if (element.isString) element.content
                    else {
                        val content = element.content
                        content.toBooleanStrictOrNull()
                            ?: content.toIntOrNull()
                            ?: content.toLongOrNull()
                            ?: content.toDoubleOrNull()
                            ?: content
                    }
                }
                else -> null
            }
        }
    }
}
