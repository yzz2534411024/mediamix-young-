package com.mediamix.shared.models

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.*

class VideoModelsTest {

    private val json = Json { ignoreUnknownKeys = true }

    // CmsApiSite tests

    @Test
    fun test_cmsApiSite_creation() {
        val site = CmsApiSite(key = "test", name = "Test", apiUrl = "http://test.com/api")
        assertEquals("test", site.key)
        assertEquals("Test", site.name)
        assertEquals("http://test.com/api", site.apiUrl)
        assertTrue(site.enabled)
        assertFalse(site.isBuiltIn)
        assertFalse(site.isTvBox)
    }

    @Test
    fun test_cmsApiSite_defaultSites_notEmpty() {
        assertTrue(CmsApiSite.defaultSites.isNotEmpty(), "Default sites should not be empty")
    }

    @Test
    fun test_cmsApiSite_defaultSites_allHaveRequiredFields() {
        CmsApiSite.defaultSites.forEach { site ->
            assertTrue(site.key.isNotEmpty(), "Site key should not be empty")
            assertTrue(site.name.isNotEmpty(), "Site name should not be empty")
            assertTrue(site.apiUrl.isNotEmpty(), "Site apiUrl should not be empty")
            assertTrue(site.isBuiltIn, "Default site should be built-in: ${site.key}")
        }
    }

    @Test
    fun test_cmsApiSite_serialization() {
        val site = CmsApiSite(key = "k", name = "n", apiUrl = "http://a.com")
        val encoded = json.encodeToString(site)
        val decoded = json.decodeFromString<CmsApiSite>(encoded)
        assertEquals(site, decoded)
    }

    // SourceType tests

    @Test
    fun test_sourceType_hasTwoValues() {
        assertEquals(2, SourceType.entries.size)
    }

    @Test
    fun test_sourceType_values() {
        assertNotNull(SourceType.CMS)
        assertNotNull(SourceType.SPIDER)
    }

    // VideoSource tests

    @Test
    fun test_videoSource_creation() {
        val source = VideoSource(key = "s1", name = "Source1", apiUrl = "http://api.com")
        assertEquals("s1", source.key)
        assertTrue(source.enabled)
        assertEquals(SourceType.CMS, source.sourceType)
        assertNull(source.spiderKey)
        assertNull(source.playerType)
    }

    @Test
    fun test_videoSource_fromCmsSite() {
        val site = CmsApiSite(key = "k1", name = "N1", apiUrl = "http://a.com", enabled = true, isBuiltIn = true)
        val source = VideoSource.fromCmsSite(site)
        assertEquals("k1", source.key)
        assertEquals("N1", source.name)
        assertEquals(SourceType.CMS, source.sourceType)
        assertTrue(source.isBuiltIn)
    }

    @Test
    fun test_videoSource_serialization() {
        val source = VideoSource(key = "k", name = "n", apiUrl = "http://a.com", sourceType = SourceType.SPIDER, spiderKey = "sp1")
        val encoded = json.encodeToString(source)
        val decoded = json.decodeFromString<VideoSource>(encoded)
        assertEquals(source, decoded)
    }

    // SourceStatus tests

    @Test
    fun test_sourceStatus_defaultValues() {
        val status = SourceStatus(key = "k", isAvailable = true)
        assertEquals(-1, status.latencyMs)
        assertNull(status.error)
    }

    @Test
    fun test_sourceStatus_withError() {
        val status = SourceStatus(key = "k", isAvailable = false, latencyMs = 500, error = "timeout")
        assertFalse(status.isAvailable)
        assertEquals(500, status.latencyMs)
        assertEquals("timeout", status.error)
    }

    // VideoItem tests

    @Test
    fun test_videoItem_creation_minimalFields() {
        val item = VideoItem(vodId = "1", vodName = "Test Video")
        assertEquals("1", item.vodId)
        assertEquals("Test Video", item.vodName)
        assertNull(item.vodPic)
        assertNull(item.vodRemarks)
        assertNull(item.vodYear)
        assertNull(item.vodArea)
        assertNull(item.typeName)
        assertNull(item.sourceKey)
    }

    @Test
    fun test_videoItem_copy() {
        val item = VideoItem(vodId = "1", vodName = "Video")
        val copied = item.copy(vodName = "New Name", vodYear = "2026")
        assertEquals("1", copied.vodId)
        assertEquals("New Name", copied.vodName)
        assertEquals("2026", copied.vodYear)
    }

    @Test
    fun test_videoItem_equality() {
        val a = VideoItem(vodId = "1", vodName = "V")
        val b = VideoItem(vodId = "1", vodName = "V")
        assertEquals(a, b)
        assertEquals(a.hashCode(), b.hashCode())
    }

    @Test
    fun test_videoItem_fromJson() {
        val map = mapOf(
            "vod_id" to "42",
            "vod_name" to "MyVideo",
            "vod_pic" to "http://img.com/pic.jpg",
            "vod_year" to "2025",
            "vod_area" to "CN"
        )
        val item = VideoItem.fromJson(map, sourceKey = "src1")
        assertEquals("42", item.vodId)
        assertEquals("MyVideo", item.vodName)
        assertEquals("http://img.com/pic.jpg", item.vodPic)
        assertEquals("2025", item.vodYear)
        assertEquals("CN", item.vodArea)
        assertEquals("src1", item.sourceKey)
    }

    @Test
    fun test_videoItem_fromJson_emptyMap() {
        val item = VideoItem.fromJson(emptyMap())
        assertEquals("", item.vodId)
        assertEquals("未知", item.vodName)
        assertNull(item.vodPic)
    }

    @Test
    fun test_videoItem_fromJson_blankStrings() {
        val map = mapOf("vod_id" to "1", "vod_name" to "V", "vod_pic" to "", "vod_year" to "")
        val item = VideoItem.fromJson(map)
        assertNull(item.vodPic, "Empty string should become null")
        assertNull(item.vodYear, "Empty string should become null")
    }

    // VideoListResponse tests

    @Test
    fun test_videoListResponse_fromJson() {
        val map = mapOf(
            "page" to "2",
            "pagecount" to "10",
            "total" to "100",
            "list" to listOf(
                mapOf("vod_id" to "1", "vod_name" to "V1"),
                mapOf("vod_id" to "2", "vod_name" to "V2")
            )
        )
        val response = VideoListResponse.fromJson(map)
        assertEquals(2, response.page)
        assertEquals(10, response.pageCount)
        assertEquals(100, response.total)
        assertEquals(2, response.list.size)
    }

    @Test
    fun test_videoListResponse_fromJson_emptyList() {
        val response = VideoListResponse.fromJson(emptyMap())
        assertEquals(1, response.page)
        assertEquals(1, response.pageCount)
        assertEquals(0, response.total)
        assertTrue(response.list.isEmpty())
    }

    // VideoEpisode tests

    @Test
    fun test_videoEpisode_creation() {
        val ep = VideoEpisode(name = "EP1", url = "http://video.com/ep1.m3u8")
        assertEquals("EP1", ep.name)
        assertEquals("http://video.com/ep1.m3u8", ep.url)
    }

    @Test
    fun test_videoEpisode_serialization() {
        val ep = VideoEpisode(name = "E1", url = "http://u.com/1")
        val encoded = json.encodeToString(ep)
        val decoded = json.decodeFromString<VideoEpisode>(encoded)
        assertEquals(ep, decoded)
    }

    // PlaySource tests

    @Test
    fun test_playSource_creation() {
        val ps = PlaySource(name = "Source1", episodes = listOf(VideoEpisode("E1", "http://u")))
        assertEquals("Source1", ps.name)
        assertEquals(1, ps.episodes.size)
    }

    // VideoDetail tests

    @Test
    fun test_videoDetail_creation() {
        val detail = VideoDetail(vodId = "1", vodName = "Movie", sourceKey = "src")
        assertEquals("1", detail.vodId)
        assertEquals("src", detail.sourceKey)
        assertTrue(detail.playSources.isEmpty())
        assertNull(detail.vodActor)
    }

    @Test
    fun test_videoDetail_fromJson_parsesPlaySources() {
        val map = mapOf(
            "vod_id" to "10",
            "vod_name" to "TestMovie",
            "vod_play_from" to "SourceA\$\$\$SourceB",
            "vod_play_url" to "EP1\$http://a.com/1#EP2\$http://a.com/2\$\$\$EP3\$http://b.com/3"
        )
        val detail = VideoDetail.fromJson(map, sourceKey = "k")
        assertEquals("10", detail.vodId)
        assertEquals("TestMovie", detail.vodName)
        assertEquals(2, detail.playSources.size)
        assertEquals("SourceA", detail.playSources[0].name)
        assertEquals(2, detail.playSources[0].episodes.size)
        assertEquals("SourceB", detail.playSources[1].name)
        assertEquals(1, detail.playSources[1].episodes.size)
    }

    @Test
    fun test_videoDetail_fromJson_emptyPlayFrom() {
        val map = mapOf("vod_id" to "1", "vod_name" to "V", "vod_play_from" to "", "vod_play_url" to "")
        val detail = VideoDetail.fromJson(map)
        assertTrue(detail.playSources.isEmpty())
    }

    // VideoCategory tests

    @Test
    fun test_videoCategory_fromJson() {
        val map = mapOf("type_id" to "5", "type_pid" to "1", "type_name" to "Action")
        val cat = VideoCategory.fromJson(map)
        assertEquals(5, cat.typeId)
        assertEquals(1, cat.typePid)
        assertEquals("Action", cat.typeName)
    }

    @Test
    fun test_videoCategory_fromJson_invalidNumbers() {
        val map = mapOf("type_id" to "abc", "type_pid" to "xyz", "type_name" to "Drama")
        val cat = VideoCategory.fromJson(map)
        assertEquals(0, cat.typeId)
        assertEquals(0, cat.typePid)
        assertEquals("Drama", cat.typeName)
    }

    // VideoParser tests

    @Test
    fun test_videoParser_buildUrl() {
        val parser = VideoParser(key = "p", name = "P", urlTemplate = "https://jx.com/?url={url}")
        assertEquals("https://jx.com/?url=http://video.com/1.m3u8", parser.buildUrl("http://video.com/1.m3u8"))
    }

    @Test
    fun test_videoParser_defaultParsers_notEmpty() {
        assertTrue(VideoParser.defaultParsers.isNotEmpty())
    }

    @Test
    fun test_videoParser_defaultParsers_allHaveUrlTemplate() {
        VideoParser.defaultParsers.forEach { parser ->
            assertTrue(parser.urlTemplate.contains("{url}"), "Parser ${parser.key} should contain {url} placeholder")
        }
    }

    // SpiderEngineException tests

    @Test
    fun test_spiderEngineException_message() {
        val ex = SpiderEngineException("test error")
        assertEquals("test error", ex.message)
    }

    @Test
    fun test_spiderEngineException_isException() {
        val ex = SpiderEngineException("err")
        assertTrue(ex is Exception)
    }
}
