package com.mediamix.shared.spider

import com.mediamix.shared.models.*
import com.mediamix.shared.network.HttpClientFactory
import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.serialization.json.Json
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

/**
 * XPath / CSS 选择器蜘蛛适配器
 *
 * 基于 TVBox 站点配置，通过 Ktor 拉取 HTML 并使用 jsoup 解析。
 * 选择器语法：
 * - `"selector"` 提取元素文本
 * - `"selector@attr"` 提取元素属性
 */
class XpathSpider(
    private val site: TvBoxSite,
) : SpiderAdapter {

    private val httpClient: HttpClient = HttpClientFactory.createHttpClient()
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }
    private var config: Map<String, Any> = emptyMap()

    override val key: String get() = site.key
    override val name: String get() = site.name
    override val type: SpiderType get() = SpiderType.XPATH
    override val isSearchSupported: Boolean get() = true

    override suspend fun init(config: Map<String, Any>) {
        this.config = config.toMutableMap()

        val extUrl = this.config["extUrl"]?.toString()
        if (extUrl != null) {
            try {
                val response = httpClient.get(extUrl)
                val body = response.bodyAsText()
                val element = json.parseToJsonElement(body)
                val remoteConfig = JsonSpider.jsonElementToMap(element)
                if (remoteConfig != null) {
                    val merged = this.config.toMutableMap()
                    merged.putAll(remoteConfig)
                    this.config = merged
                }
            } catch (_: Exception) {
                // 远程配置加载失败时保持原有配置
            }
        }
    }

    override suspend fun homeContent(page: Int): SpiderHomeResult {
        val url = buildUrl(config["homeUrl"]?.toString() ?: site.api)
        val doc = fetchHtml(url)
        val categories = parseCategories()
        @Suppress("UNCHECKED_CAST")
        val items = extractList(doc, config["list"] as? Map<String, Any>)
        return SpiderHomeResult(categories = categories, recommend = items)
    }

    override suspend fun categoryContent(
        tid: String,
        page: Int,
        filter: Map<String, String>?,
    ): SpiderListResult {
        var url = (config["cateUrl"]?.toString() ?: "")
            .replace("{tid}", tid)
            .replace("{pg}", page.toString())
        if (url.isEmpty()) url = site.api

        val doc = fetchHtml(buildUrl(url))
        @Suppress("UNCHECKED_CAST")
        val items = extractList(doc, config["list"] as? Map<String, Any>)
        return SpiderListResult(
            list = items,
            page = page,
            pageCount = 1,
            total = items.size,
        )
    }

    override suspend fun detailContent(id: String): SpiderDetailResult {
        var url = (config["detailUrl"]?.toString() ?: "").replace("{id}", id)
        if (url.isEmpty()) url = id

        val doc = fetchHtml(buildUrl(url))
        val detail = extractDetail(doc, id)
        return SpiderDetailResult(detail = detail)
    }

    override suspend fun searchContent(keyword: String, page: Int): SpiderListResult {
        var url = (config["searchUrl"]?.toString() ?: "")
            .replace("{wd}", JsonSpider.encodeUrlComponent(keyword))
            .replace("{pg}", page.toString())
        if (url.isEmpty()) {
            return SpiderListResult(list = emptyList(), page = 1, pageCount = 1, total = 0)
        }

        val doc = fetchHtml(buildUrl(url))
        @Suppress("UNCHECKED_CAST")
        val items = extractList(doc, config["list"] as? Map<String, Any>)
        return SpiderListResult(
            list = items,
            page = page,
            pageCount = 1,
            total = items.size,
        )
    }

    override suspend fun playerContent(flag: String, id: String): SpiderPlayResult {
        @Suppress("UNCHECKED_CAST")
        val playConfig = config["playUrl"] as? Map<String, Any> ?: emptyMap<String, Any>()
        val parseFlag = playConfig["parse"]?.toString() ?: "0"
        val selector = playConfig["selector"]?.toString()
            ?: playConfig["url"]?.toString()
            ?: ""

        if (selector.isEmpty()) {
            return SpiderPlayResult(url = id, parse = parseFlag)
        }

        val requestUrl = buildUrl(id)
        val doc = fetchHtml(requestUrl)
        val playUrl = extractFirstValue(
            doc.body() ?: doc,
            selector,
            baseUrl = requestUrl,
        )

        return SpiderPlayResult(
            url = playUrl,
            parse = parseFlag,
            playUrl = if (parseFlag == "1") playUrl else null,
        )
    }

    override fun dispose() {
        httpClient.close()
    }

    // ==================== 内部方法 ====================

    /** 解析配置中的分类列表 */
    private fun parseCategories(): List<SpiderCategory> {
        @Suppress("UNCHECKED_CAST")
        val cats = config["categories"] as? List<Any> ?: return emptyList()
        return cats.mapNotNull { c ->
            (c as? Map<String, Any>)?.let { m ->
                SpiderCategory(
                    typeId = m["id"]?.toString() ?: "",
                    typeName = m["name"]?.toString() ?: "",
                )
            }
        }
    }

    /** 拉取并解析 HTML 文档 */
    private suspend fun fetchHtml(url: String): Document {
        val response = httpClient.get(url)
        val body = response.bodyAsText()
        return Jsoup.parse(body)
    }

    /**
     * 从文档中提取视频列表
     *
     * 对应 Dart 的 _extractList()：
     * - doc.querySelectorAll(selector) → doc.select(selector)
     */
    fun extractList(doc: Document, listConfig: Map<String, Any>?): List<VideoItem> {
        if (listConfig == null) return emptyList()

        val containerSelector = listConfig["container"]?.toString() ?: ""
        if (containerSelector.isEmpty()) return emptyList()

        @Suppress("UNCHECKED_CAST")
        val fields = listConfig["fields"] as? Map<String, Any> ?: emptyMap<String, Any>()
        val nodes = doc.select(containerSelector)

        val result = mutableListOf<VideoItem>()
        for (node in nodes) {
            val vodId = extractField(node, fields["vod_id"]?.toString() ?: "")
            val vodName = extractField(node, fields["vod_name"]?.toString() ?: "")
            if (vodName.isEmpty()) continue

            result.add(
                VideoItem(
                    vodId = vodId,
                    vodName = vodName,
                    vodPic = extractField(node, fields["vod_pic"]?.toString() ?: ""),
                    vodRemarks = extractField(node, fields["vod_remarks"]?.toString() ?: ""),
                    sourceKey = key,
                )
            )
        }
        return result
    }

    /** 从文档中提取详情 */
    private fun extractDetail(doc: Document, id: String): VideoDetail {
        @Suppress("UNCHECKED_CAST")
        val detailConfig = config["detail"] as? Map<String, Any>
        @Suppress("UNCHECKED_CAST")
        val fields = (detailConfig?.get("fields") as? Map<String, Any>) ?: emptyMap<String, Any>()

        val playSources = extractPlaySources(doc)

        val root: Element = doc.body() ?: doc
        return VideoDetail(
            vodId = id,
            vodName = extractFirstValue(root, fields["vod_name"]?.toString() ?: "").ifEmpty { "未知" },
            vodPic = extractFirstValue(root, fields["vod_pic"]?.toString() ?: "").nullIfEmpty(),
            vodContent = extractFirstValue(root, fields["vod_content"]?.toString() ?: "").nullIfEmpty(),
            vodActor = extractFirstValue(root, fields["vod_actor"]?.toString() ?: "").nullIfEmpty(),
            vodDirector = extractFirstValue(root, fields["vod_director"]?.toString() ?: "").nullIfEmpty(),
            sourceKey = key,
            playSources = playSources,
        )
    }

    /**
     * 从详情页提取播放源与选集
     *
     * 对应 Dart 的 _extractPlaySources()：
     * - tab.querySelectorAll(listSelector) → tab.select(listSelector)
     */
    fun extractPlaySources(doc: Document): List<PlaySource> {
        @Suppress("UNCHECKED_CAST")
        val playConfig = config["playUrl"] as? Map<String, Any> ?: return emptyList()

        val tabSelector = playConfig["tab"]?.toString() ?: ""
        val listSelector = playConfig["list"]?.toString() ?: ""
        val nameSelector = playConfig["name"]?.toString() ?: ""
        val urlSelector = playConfig["url"]?.toString() ?: ""

        if (tabSelector.isEmpty() || listSelector.isEmpty()) return emptyList()

        val tabs = doc.select(tabSelector)
        val sources = mutableListOf<PlaySource>()

        for (tab in tabs) {
            val sourceName = tab.text().trim()
            val episodes = mutableListOf<VideoEpisode>()

            // listSelector 优先在 tab 上下文内查找，未命中则在文档范围内查找
            var items = tab.select(listSelector)
            if (items.isEmpty()) {
                items = doc.select(listSelector)
            }

            for (item in items) {
                val epName = extractField(item, nameSelector)
                val epUrl = extractField(item, urlSelector)
                if (epName.isNotEmpty() && epUrl.isNotEmpty()) {
                    episodes.add(VideoEpisode(name = epName, url = epUrl))
                }
            }

            if (episodes.isNotEmpty()) {
                sources.add(
                    PlaySource(
                        name = if (sourceName.isEmpty()) "默认源" else sourceName,
                        episodes = episodes,
                    )
                )
            }
        }

        return sources
    }

    /**
     * 在节点上按选择器提取字段值
     *
     * 对应 Dart 的 _extractField()
     */
    fun extractField(root: Element, rawSelector: String): String {
        if (rawSelector.isEmpty()) return ""
        return extractFirstValue(root, rawSelector)
    }

    /**
     * 解析选择器并提取首个匹配值
     *
     * 选择器支持 `"selector"` 和 `"selector@attr"` 两种形式。
     * 当选择器未包含 `@` 时，依次尝试 `src`、`href` 属性，最后取文本。
     *
     * 对应 Dart 的 _extractFirstValue()：
     * - root.querySelector(selector) → root.selectFirst(selector)
     * - element.attributes[attr] → element.attr(attr)
     */
    fun extractFirstValue(root: Element?, rawSelector: String, baseUrl: String? = null): String {
        if (root == null || rawSelector.isEmpty()) return ""

        val (selector, attr) = parseSelector(rawSelector)
        if (selector.isEmpty()) return ""

        val element = root.selectFirst(selector) ?: return ""

        val value: String = if (attr != null) {
            element.attr(attr)
        } else {
            val src = element.attr("src")
            val href = element.attr("href")
            when {
                src.isNotEmpty() -> src
                href.isNotEmpty() -> href
                else -> element.text().trim()
            }
        }

        return if (baseUrl != null && value.isNotEmpty()) {
            resolveUrl(value, baseUrl)
        } else {
            value
        }
    }

    /**
     * 解析选择器字符串
     *
     * 对应 Dart 的 _parseSelector()：
     * `"selector@attr"` → (selector, attr)
     * `"selector"` → (selector, null)
     */
    fun parseSelector(raw: String): Pair<String, String?> {
        val atIndex = raw.lastIndexOf('@')
        if (atIndex == -1) return raw to null
        return raw.substring(0, atIndex) to raw.substring(atIndex + 1)
    }

    /**
     * 处理 URL：为空或协议头缺失时补充 site.api 作为 base
     *
     * 对应 Dart 的 _buildUrl()
     */
    fun buildUrl(url: String): String {
        if (url.trim().isEmpty()) return site.api
        if (url.startsWith("http://") || url.startsWith("https://")) return url
        val base = site.api
        return if (base.endsWith("/")) {
            if (url.startsWith("/")) "$base${url.substring(1)}" else "$base$url"
        } else {
            if (url.startsWith("/")) "$base$url" else "$base/$url"
        }
    }

    /**
     * 将相对 URL 转为绝对 URL
     *
     * 对应 Dart 的 _resolveUrl()
     */
    fun resolveUrl(url: String, baseUrl: String): String {
        if (url.startsWith("http://") || url.startsWith("https://")) return url
        return try {
            val base = java.net.URI(baseUrl)
            base.resolve(url).toString()
        } catch (_: Exception) {
            url
        }
    }

    // ==================== 扩展函数 ====================

    private fun String.ifEmpty(fallback: String): String = if (isEmpty()) fallback else this
    private fun String.nullIfEmpty(): String? = if (isEmpty()) null else this
}
