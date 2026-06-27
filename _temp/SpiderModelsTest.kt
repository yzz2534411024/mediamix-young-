package com.mediamix.shared.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.*

class SpiderModelsTest {

    private val json = Json { ignoreUnknownKeys = true }

    // SpiderType tests

    @Test
    fun test_spiderType_hasFiveValues() {
        assertEquals(5, SpiderType.entries.size)
    }

    @Test
    fun test_spiderType_values() {
        assertNotNull(SpiderType.CMS)
        assertNotNull(SpiderType.XPATH)
        assertNotNull(SpiderType.JSON)
        assertNotNull(SpiderType.SITE)
        assertNotNull(SpiderType.JAVA_BRIDGE)
    }

    @Test
    fun test_spiderType_valueOf() {
        assertEquals(SpiderType.CMS, SpiderType.valueOf("CMS"))
        assertEquals(SpiderType.JAVA_BRIDGE, SpiderType.valueOf("JAVA_BRIDGE"))
    }

    // SpiderHomeResult tests

    @Test
    fun test_spiderHomeResult_defaultValues() {
        val result = SpiderHomeResult()
        assertTrue(result.categories.isEmpty())
        assertTrue(result.recommend.isEmpty())
        assertNull(result.classList)
    }

    @Test
    fun test_spiderHomeResult_withData() {
        val cat = SpiderCategory(typeId = "1", typeName = "Movies")
        val item = VideoItem(vodId = "1", vodName = "Test")
        val result = SpiderHomeResult(
            categories = listOf(cat),
            recommend = listOf(item),
            classList = mapOf("1" to listOf(item))
        )
        assertEquals(1, result.categories.size)
        assertEquals(1, result.recommend.size)
        assertNotNull(result.classList)
        assertEquals(1, result.classList!!["1"]?.size)
    }

    @Test
    fun test_spiderHomeResult_serialization() {
        val result = SpiderHomeResult(
            categories = listOf(SpiderCategory("1", "Action")),
            recommend = listOf(VideoItem("1", "V1"))
        )
        val encoded = json.encodeToString(result)
        val decoded = json.decodeFromString<SpiderHomeResult>(encoded)
        assertEquals(result, decoded)
    }

    // SpiderListResult tests

    @Test
    fun test_spiderListResult_defaults() {
        val result = SpiderListResult()
        assertTrue(result.list.isEmpty())
        assertEquals(1, result.page)
        assertEquals(1, result.pageCount)
        assertEquals(0, result.total)
    }

    @Test
    fun test_spiderListResult_withValues() {
        val result = SpiderListResult(
            list = listOf(VideoItem("1", "V")),
            page = 3,
            pageCount = 10,
            total = 100
        )
        assertEquals(3, result.page)
        assertEquals(10, result.pageCount)
        assertEquals(100, result.total)
        assertEquals(1, result.list.size)
    }

    // SpiderDetailResult tests

    @Test
    fun test_spiderDetailResult_defaultNull() {
        val result = SpiderDetailResult()
        assertNull(result.detail)
    }

    @Test
    fun test_spiderDetailResult_withDetail() {
        val detail = VideoDetail(vodId = "1", vodName = "Movie", sourceKey = "src")
        val result = SpiderDetailResult(detail = detail)
        assertNotNull(result.detail)
        assertEquals("1", result.detail!!.vodId)
    }

    // SpiderPlayResult tests

    @Test
    fun test_spiderPlayResult_defaultUrl() {
        val result = SpiderPlayResult()
        assertEquals("", result.url)
        assertNull(result.headers)
        assertNull(result.parse)
        assertNull(result.playUrl)
    }

    @Test
    fun test_spiderPlayResult_needsParse_true() {
        val result = SpiderPlayResult(parse = "1")
        assertTrue(result.needsParse, "parse=1 should mean needsParse=true")
    }

    @Test
    fun test_spiderPlayResult_needsParse_false() {
        val result = SpiderPlayResult(parse = "0")
        assertFalse(result.needsParse, "parse=0 should mean needsParse=false")
    }

    @Test
    fun test_spiderPlayResult_needsParse_null() {
        val result = SpiderPlayResult(parse = null)
        assertFalse(result.needsParse, "null parse should mean needsParse=false")
    }

    // SpiderCategory tests

    @Test
    fun test_spiderCategory_creation() {
        val cat = SpiderCategory(typeId = "1", typeName = "Action")
        assertEquals("1", cat.typeId)
        assertEquals("Action", cat.typeName)
        assertNull(cat.filters)
    }

    @Test
    fun test_spiderCategory_withFilters() {
        val filter = SpiderFilter(
            key = "area",
            name = "Region",
            values = listOf(SpiderFilterValue("cn", "China"), SpiderFilterValue("us", "USA"))
        )
        val cat = SpiderCategory(typeId = "1", typeName = "Movies", filters = listOf(filter))
        assertNotNull(cat.filters)
        assertEquals(1, cat.filters!!.size)
        assertEquals(2, cat.filters!![0].values.size)
    }

    @Test
    fun test_spiderCategory_serialization() {
        val cat = SpiderCategory("1", "Drama", filters = null)
        val encoded = json.encodeToString(cat)
        val decoded = json.decodeFromString<SpiderCategory>(encoded)
        assertEquals(cat, decoded)
    }

    // SpiderFilter tests

    @Test
    fun test_spiderFilter_creation() {
        val filter = SpiderFilter(key = "year", name = "Year", values = listOf(SpiderFilterValue("2025", "2025")))
        assertEquals("year", filter.key)
        assertEquals("Year", filter.name)
        assertEquals(1, filter.values.size)
    }

    // TvBoxConfig tests

    @Test
    fun test_tvBoxConfig_defaults() {
        val config = TvBoxConfig()
        assertNull(config.spiderUrl)
        assertTrue(config.sites.isEmpty())
        assertTrue(config.lives.isEmpty())
        assertTrue(config.flags.isEmpty())
    }

    @Test
    fun test_tvBoxConfig_withData() {
        val site = TvBoxSite(key = "k", name = "N", api = "http://api.com")
        val config = TvBoxConfig(spiderUrl = "http://spider.jar", sites = listOf(site), flags = listOf("flag1"))
        assertEquals("http://spider.jar", config.spiderUrl)
        assertEquals(1, config.sites.size)
        assertEquals(1, config.flags.size)
    }

    @Test
    fun test_tvBoxConfig_serialization() {
        val config = TvBoxConfig(spiderUrl = "http://s.jar", sites = listOf(TvBoxSite("k", "N", api = "http://a.com")))
        val encoded = json.encodeToString(config)
        val decoded = json.decodeFromString<TvBoxConfig>(encoded)
        assertEquals(config, decoded)
    }

    // TvBoxSite tests

    @Test
    fun test_tvBoxSite_defaults() {
        val site = TvBoxSite(key = "k", name = "N", api = "http://api.com")
        assertEquals(0, site.type)
        assertNull(site.ext)
        assertNull(site.jar)
        assertNull(site.playerType)
        assertTrue(site.searchable)
        assertFalse(site.quickSearch)
        assertFalse(site.changeable)
    }

    @Test
    fun test_tvBoxSite_isJavaSpider_true() {
        val site = TvBoxSite(key = "k", name = "N", api = "csp_MySpider")
        assertTrue(site.isJavaSpider, "api starting with csp_ should be Java spider")
    }

    @Test
    fun test_tvBoxSite_isJavaSpider_false() {
        val site = TvBoxSite(key = "k", name = "N", api = "http://api.com")
        assertFalse(site.isJavaSpider, "Regular API URL should not be Java spider")
    }

    // TvBoxLive tests

    @Test
    fun test_tvBoxLive_creation() {
        val live = TvBoxLive(name = "CCTV1", url = "http://live.com/cctv1")
        assertEquals("CCTV1", live.name)
        assertEquals("http://live.com/cctv1", live.url)
        assertNull(live.type)
        assertNull(live.playerType)
    }

    @Test
    fun test_tvBoxLive_serialization() {
        val live = TvBoxLive(name = "L1", type = "iptv", url = "http://u.com/1", playerType = 1)
        val encoded = json.encodeToString(live)
        val decoded = json.decodeFromString<TvBoxLive>(encoded)
        assertEquals(live, decoded)
    }
}
