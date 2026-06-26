package com.mediamix.shared.spider

import com.mediamix.shared.models.*
import org.jsoup.Jsoup
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * XpathSpider 单元测试
 *
 * 测试 CSS 选择器提取、URL 解析等纯逻辑部分
 */
class XpathSpiderTest {

    private val testSite = TvBoxSite(
        key = "test_xpath",
        name = "测试XPath",
        type = 1,
        api = "http://test.example.com",
    )

    // ==================== parseSelector 测试 ====================

    @Test
    fun testParseSelector_noAttr() {
        val spider = XpathSpider(testSite)
        val (selector, attr) = spider.parseSelector(".item .title")
        assertEquals(".item .title", selector)
        assertEquals(null, attr)
    }

    @Test
    fun testParseSelector_withAttr() {
        val spider = XpathSpider(testSite)
        val (selector, attr) = spider.parseSelector(".item img@src")
        assertEquals(".item img", selector)
        assertEquals("src", attr)
    }

    @Test
    fun testParseSelector_hrefAttr() {
        val spider = XpathSpider(testSite)
        val (selector, attr) = spider.parseSelector("a.title@href")
        assertEquals("a.title", selector)
        assertEquals("href", attr)
    }

    @Test
    fun testParseSelector_multipleAtSigns() {
        // lastIndexOf('@') 应取最后一个 @
        val spider = XpathSpider(testSite)
        val (selector, attr) = spider.parseSelector("div[data-x@y]@title")
        assertEquals("div[data-x@y]", selector)
        assertEquals("title", attr)
    }

    // ==================== buildUrl 测试 ====================

    @Test
    fun testBuildUrl_absoluteUrl() {
        val spider = XpathSpider(testSite)
        assertEquals("http://other.com/page", spider.buildUrl("http://other.com/page"))
        assertEquals("https://secure.com/page", spider.buildUrl("https://secure.com/page"))
    }

    @Test
    fun testBuildUrl_relativeWithSlash() {
        val spider = XpathSpider(testSite)
        // site.api = "http://test.example.com" (no trailing slash)
        assertEquals("http://test.example.com/page", spider.buildUrl("/page"))
    }

    @Test
    fun testBuildUrl_relativeWithoutSlash() {
        val spider = XpathSpider(testSite)
        assertEquals("http://test.example.com/page", spider.buildUrl("page"))
    }

    @Test
    fun testBuildUrl_emptyUrl() {
        val spider = XpathSpider(testSite)
        assertEquals("http://test.example.com", spider.buildUrl(""))
        assertEquals("http://test.example.com", spider.buildUrl("  "))
    }

    @Test
    fun testBuildUrl_baseWithTrailingSlash() {
        val siteWithSlash = testSite.copy(api = "http://test.example.com/")
        val spider = XpathSpider(siteWithSlash)
        assertEquals("http://test.example.com/page", spider.buildUrl("/page"))
        assertEquals("http://test.example.com/page", spider.buildUrl("page"))
    }

    // ==================== resolveUrl 测试 ====================

    @Test
    fun testResolveUrl_absolute() {
        val spider = XpathSpider(testSite)
        assertEquals("http://other.com/img.jpg", spider.resolveUrl("http://other.com/img.jpg", "http://base.com"))
    }

    @Test
    fun testResolveUrl_relative() {
        val spider = XpathSpider(testSite)
        val resolved = spider.resolveUrl("/images/pic.jpg", "http://test.example.com/page/detail")
        assertEquals("http://test.example.com/images/pic.jpg", resolved)
    }

    // ==================== extractField 测试 ====================

    @Test
    fun testExtractField_textContent() {
        val spider = XpathSpider(testSite)
        val doc = Jsoup.parse("""<div class="title">影片名称</div>""")
        val result = spider.extractField(doc.body(), ".title")
        assertEquals("影片名称", result)
    }

    @Test
    fun testExtractField_srcAttr() {
        val spider = XpathSpider(testSite)
        val doc = Jsoup.parse("""<img class="cover" src="http://img.com/1.jpg">""")
        // 无 @attr 时，优先取 src
        val result = spider.extractField(doc.body(), ".cover")
        assertEquals("http://img.com/1.jpg", result)
    }

    @Test
    fun testExtractField_explicitAttr() {
        val spider = XpathSpider(testSite)
        val doc = Jsoup.parse("""<img class="cover" src="http://img.com/1.jpg" data-original="http://img.com/hd.jpg">""")
        val result = spider.extractField(doc.body(), ".cover@data-original")
        assertEquals("http://img.com/hd.jpg", result)
    }

    @Test
    fun testExtractField_hrefAttr() {
        val spider = XpathSpider(testSite)
        val doc = Jsoup.parse("""<a class="link" href="/detail/123">链接</a>""")
        // 无 @attr 时，优先取 href
        val result = spider.extractField(doc.body(), ".link")
        assertEquals("/detail/123", result)
    }

    @Test
    fun testExtractField_emptySelector() {
        val spider = XpathSpider(testSite)
        val doc = Jsoup.parse("""<div>内容</div>""")
        val result = spider.extractField(doc.body(), "")
        assertEquals("", result)
    }

    @Test
    fun testExtractField_noMatch() {
        val spider = XpathSpider(testSite)
        val doc = Jsoup.parse("""<div>内容</div>""")
        val result = spider.extractField(doc.body(), ".nonexistent")
        assertEquals("", result)
    }

    // ==================== extractFirstValue 测试 ====================

    @Test
    fun testExtractFirstValue_withBaseUrl() {
        val spider = XpathSpider(testSite)
        val doc = Jsoup.parse("""<img class="pic" src="/images/cover.jpg">""")
        val result = spider.extractFirstValue(
            doc.body(),
            ".pic",
            baseUrl = "http://test.example.com/page"
        )
        assertEquals("http://test.example.com/images/cover.jpg", result)
    }

    // ==================== extractList 测试 ====================

    @Test
    fun testExtractList_basicHtml() {
        val spider = XpathSpider(testSite)
        val html = """
            <div class="container">
                <div class="item">
                    <span class="id">1</span>
                    <span class="name">影片一</span>
                    <img class="pic" src="http://img.com/1.jpg">
                    <span class="remark">HD</span>
                </div>
                <div class="item">
                    <span class="id">2</span>
                    <span class="name">影片二</span>
                    <img class="pic" src="http://img.com/2.jpg">
                    <span class="remark">BD</span>
                </div>
            </div>
        """.trimIndent()
        val doc = Jsoup.parse(html)

        val listConfig = mapOf<String, Any>(
            "container" to ".item",
            "fields" to mapOf(
                "vod_id" to ".id",
                "vod_name" to ".name",
                "vod_pic" to ".pic",
                "vod_remarks" to ".remark",
            )
        )

        val items = spider.extractList(doc, listConfig)
        assertEquals(2, items.size)
        assertEquals("1", items[0].vodId)
        assertEquals("影片一", items[0].vodName)
        assertEquals("http://img.com/1.jpg", items[0].vodPic)
        assertEquals("HD", items[0].vodRemarks)
        assertEquals("2", items[1].vodId)
        assertEquals("影片二", items[1].vodName)
    }

    @Test
    fun testExtractList_nullConfig() {
        val spider = XpathSpider(testSite)
        val doc = Jsoup.parse("<div></div>")
        val items = spider.extractList(doc, null)
        assertTrue(items.isEmpty())
    }

    @Test
    fun testExtractList_emptyContainer() {
        val spider = XpathSpider(testSite)
        val doc = Jsoup.parse("<div></div>")
        val items = spider.extractList(doc, mapOf("container" to ""))
        assertTrue(items.isEmpty())
    }

    @Test
    fun testExtractList_skipEmptyName() {
        val spider = XpathSpider(testSite)
        val html = """
            <div class="item"><span class="name"></span></div>
            <div class="item"><span class="name">有效影片</span></div>
        """.trimIndent()
        val doc = Jsoup.parse(html)

        val listConfig = mapOf<String, Any>(
            "container" to ".item",
            "fields" to mapOf("vod_name" to ".name")
        )

        val items = spider.extractList(doc, listConfig)
        assertEquals(1, items.size)
        assertEquals("有效影片", items[0].vodName)
    }

    // ==================== extractPlaySources 测试 ====================

    @Test
    fun testExtractPlaySources_basicStructure() {
        // 需要初始化 config，但 extractPlaySources 读取 config["playUrl"]
        // 由于无法直接设置 config，我们验证空 config 返回空列表
        val spider = XpathSpider(testSite)
        val doc = Jsoup.parse("<div></div>")
        val sources = spider.extractPlaySources(doc)
        assertTrue(sources.isEmpty())
    }
}
