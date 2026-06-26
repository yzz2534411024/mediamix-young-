package com.mediamix.shared.spider

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * JsonSpider 单元测试
 *
 * 测试 JSON 解析、字段映射、路径提取等纯逻辑部分
 */
class JsonSpiderTest {

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    // ==================== extractByPath 测试 ====================

    @Test
    fun testExtractByPath_simplePath() {
        val spider = JsonSpider()
        val data = json.parseToJsonElement("""
            {"data":{"list":[{"vod_id":"1","vod_name":"测试影片"}]}}
        """)

        val result = spider.extractByPath(data, "$.data.list")
        assertNotNull(result)
        assertTrue(result is JsonArray)
        assertEquals(1, (result as JsonArray).size)
    }

    @Test
    fun testExtractByPath_rootPath() {
        val spider = JsonSpider()
        val data = json.parseToJsonElement("""
            {"list":[{"vod_id":"1","vod_name":"影片1"},{"vod_id":"2","vod_name":"影片2"}]}
        """)

        val result = spider.extractByPath(data, "$.list")
        assertNotNull(result)
        assertTrue(result is JsonArray)
        assertEquals(2, (result as JsonArray).size)
    }

    @Test
    fun testExtractByPath_nonExistentPath() {
        val spider = JsonSpider()
        val data = json.parseToJsonElement("""{"data":{"name":"test"}}""")

        val result = spider.extractByPath(data, "$.data.missing")
        assertNull(result)
    }

    @Test
    fun testExtractByPath_emptyPath() {
        val spider = JsonSpider()
        val data = json.parseToJsonElement("""{"data":{"value":42}}""")

        // 空路径应返回根元素
        val result = spider.extractByPath(data, "")
        assertNotNull(result)
        assertEquals(data, result)
    }

    @Test
    fun testExtractByPath_arrayIndex() {
        val spider = JsonSpider()
        val data = json.parseToJsonElement("""
            {"items":["a","b","c"]}
        """)

        val result = spider.extractByPath(data, "$.items.1")
        assertNotNull(result)
        assertEquals("b", result.toString().trim('"'))
    }

    // ==================== normalizeMap 测试 ====================

    @Test
    fun testNormalizeMap_withFieldMapping() {
        val spider = JsonSpider()
        val source = buildJsonObject {
            put("vod_id", "123")
            put("vod_name", "测试影片")
            put("vod_pic", "http://img.example.com/1.jpg")
        }
        val fieldMap = mapOf<String, Any>(
            "vod_id" to "id",
            "vod_name" to "title",
            "vod_pic" to "cover"
        )

        val result = spider.normalizeMap(source, fieldMap)
        assertEquals("123", result["id"])
        assertEquals("测试影片", result["title"])
        assertEquals("http://img.example.com/1.jpg", result["cover"])
    }

    @Test
    fun testNormalizeMap_noFieldMap() {
        val spider = JsonSpider()
        val source = buildJsonObject {
            put("vod_id", "1")
            put("vod_name", "影片名")
            put("vod_pic", "http://img.com/1.jpg")
        }

        val result = spider.normalizeMap(source, emptyMap())
        assertEquals("1", result["vod_id"])
        assertEquals("影片名", result["vod_name"])
        assertEquals("http://img.com/1.jpg", result["vod_pic"])
    }

    // ==================== extractList 测试 ====================

    @Test
    fun testExtractList_basic() {
        val spider = JsonSpider()
        val data = json.parseToJsonElement("""
            {"data":{"list":[
                {"vod_id":"1","vod_name":"影片1"},
                {"vod_id":"2","vod_name":"影片2"}
            ]}}
        """)
        val fieldMap = mapOf<String, Any>(
            "vod_id" to "id",
            "vod_name" to "title"
        )

        val result = spider.extractList(data, "$.data.list", fieldMap)
        assertEquals(2, result.size)
        assertEquals("1", result[0]["id"])
        assertEquals("影片2", result[1]["title"])
    }

    // ==================== jsonElementToAny 测试 ====================

    @Test
    fun testJsonElementToMap_object() {
        val jsonStr = """{"vod_id":"1","vod_name":"测试","type_id":5}"""
        val element = json.parseToJsonElement(jsonStr)
        val result = JsonSpider.jsonElementToMap(element)

        assertNotNull(result)
        assertEquals("1", result["vod_id"])
        assertEquals("测试", result["vod_name"])
        assertEquals(5, result["type_id"])
    }

    @Test
    fun testJsonElementToAny_nestedObject() {
        val jsonStr = """{"data":{"list":[{"id":1},{"id":2}]}}"""
        val element = json.parseToJsonElement(jsonStr)
        val result = JsonSpider.jsonElementToAny(element)

        assertNotNull(result)
        assertTrue(result is Map<*, *>)
        @Suppress("UNCHECKED_CAST")
        val data = (result as Map<String, Any>)["data"] as Map<String, Any>
        @Suppress("UNCHECKED_CAST")
        val list = data["list"] as List<Any>
        assertEquals(2, list.size)
    }

    @Test
    fun testJsonElementToAny_primitiveTypes() {
        // 字符串
        val strElement = json.parseToJsonElement("\"hello\"")
        assertEquals("hello", JsonSpider.jsonElementToAny(strElement))

        // 整数
        val intElement = json.parseToJsonElement("42")
        assertEquals(42, JsonSpider.jsonElementToAny(intElement))

        // 布尔
        val boolElement = json.parseToJsonElement("true")
        assertEquals(true, JsonSpider.jsonElementToAny(boolElement))

        // null
        val nullElement = json.parseToJsonElement("null")
        assertNull(JsonSpider.jsonElementToAny(nullElement))
    }

    // ==================== encodeUrlComponent 测试 ====================

    @Test
    fun testEncodeUrlComponent_ascii() {
        assertEquals("hello", JsonSpider.encodeUrlComponent("hello"))
        assertEquals("hello+world", JsonSpider.encodeUrlComponent("hello world"))
    }

    @Test
    fun testEncodeUrlComponent_chinese() {
        val encoded = JsonSpider.encodeUrlComponent("测试")
        assertTrue(encoded.contains("%"))
        assertTrue(encoded.isNotEmpty())
    }

    @Test
    fun testEncodeUrlComponent_specialChars() {
        val encoded = JsonSpider.encodeUrlComponent("a&b=c")
        assertTrue(encoded.contains("%26") || encoded.contains("%3D"))
    }
}
