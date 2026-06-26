$utf8 = New-Object System.Text.UTF8Encoding($false)

# ============================================================
# 1. Update VideoModels.kt - add fromJson helpers
# ============================================================
$videoModels = @'
package com.mediamix.shared.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// ============================================================
// 异常
// ============================================================

/** 蜘蛛引擎异常（如 Java Bridge 不可用） */
class SpiderEngineException(message: String) : Exception(message)

// ============================================================
// CMS API 站点
// ============================================================

/** CMS API 站点 */
@Serializable
data class CmsApiSite(
    val key: String,
    val name: String,
    val apiUrl: String,
    val enabled: Boolean = true,
    val isBuiltIn: Boolean = false,
    val isTvBox: Boolean = false,
) {
    companion object {
        /** 内置站点列表（2026-06 实测可用） */
        val defaultSites: List<CmsApiSite> = listOf(
            CmsApiSite(key = "fantaiying", name = "饭太硬", apiUrl = "http://www.xn--sss604efuw.net/tv", isBuiltIn = true, isTvBox = true),
            CmsApiSite(key = "bfzy", name = "暴风资源", apiUrl = "https://bfzyapi.com/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "lzzy", name = "量子资源", apiUrl = "https://cj.lziapi.com/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "ffzy", name = "非凡资源", apiUrl = "http://ffzy5.tv/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "hnzy", name = "红牛资源", apiUrl = "https://hongniuzy2.com/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "tyyszy", name = "天涯资源", apiUrl = "https://tyyszy.com/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "jszyapi", name = "极速资源", apiUrl = "https://jszyapi.com/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "zuidapi", name = "最大资源", apiUrl = "https://api.zuidapi.com/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "apibdzy", name = "百度资源", apiUrl = "https://api.apibdzy.com/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "apiwujin", name = "无尽资源", apiUrl = "https://api.wujinapi.me/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "rycjapi", name = "如意资源", apiUrl = "https://cj.rycjapi.com/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "apiYhzy", name = "樱花资源", apiUrl = "https://m3u8.apiyhzy.com/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "dbzy", name = "豆瓣资源", apiUrl = "https://dbzy.tv/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "mdzyapi", name = "魔都资源", apiUrl = "https://www.mdzyapi.com/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "xiaomaomi", name = "小猫咪资源", apiUrl = "https://zy.xiaomaomi.cc/api.php/provide/vod/", isBuiltIn = true),
            CmsApiSite(key = "dyttzyapi", name = "电影天堂", apiUrl = "http://caiji.dyttzyapi.com/api.php/provide/vod/", isBuiltIn = true),
        )
    }
}

// ============================================================
// 枚举
// ============================================================

/** 视频源类型 */
@Serializable
enum class SourceType {
    @SerialName("cms") CMS,
    @SerialName("spider") SPIDER,
}

// ============================================================
// 视频源
// ============================================================

/** 视频源（CMS 或 Spider） */
@Serializable
data class VideoSource(
    val key: String,
    val name: String,
    val apiUrl: String,
    val enabled: Boolean = true,
    val isBuiltIn: Boolean = false,
    val sourceType: SourceType = SourceType.CMS,
    val spiderKey: String? = null,
    val playerType: String? = null,
) {
    companion object {
        fun fromCmsSite(site: CmsApiSite): VideoSource = VideoSource(
            key = site.key,
            name = site.name,
            apiUrl = site.apiUrl,
            enabled = site.enabled,
            isBuiltIn = site.isBuiltIn,
            sourceType = SourceType.CMS,
        )
    }
}

// ============================================================
// 源状态检测结果
// ============================================================

/** 源状态检测结果 */
@Serializable
data class SourceStatus(
    val key: String,
    val isAvailable: Boolean,
    val latencyMs: Int = -1,
    val error: String? = null,
)

// ============================================================
// 影片条目（列表/搜索结果）
// ============================================================

/** 影片条目（列表/搜索结果） */
@Serializable
data class VideoItem(
    val vodId: String,
    val vodName: String,
    val vodPic: String? = null,
    val vodRemarks: String? = null,
    val vodYear: String? = null,
    val vodArea: String? = null,
    val typeName: String? = null,
    val sourceKey: String? = null,
) {
    companion object {
        fun fromJson(json: Map<String, Any?>, sourceKey: String? = null): VideoItem {
            return VideoItem(
                vodId = json["vod_id"]?.toString() ?: "",
                vodName = json["vod_name"]?.toString() ?: "未知",
                vodPic = json["vod_pic"]?.toString()?.takeIf { it.isNotEmpty() },
                vodRemarks = json["vod_remarks"]?.toString()?.takeIf { it.isNotEmpty() },
                vodYear = json["vod_year"]?.toString()?.takeIf { it.isNotEmpty() },
                vodArea = json["vod_area"]?.toString()?.takeIf { it.isNotEmpty() },
                typeName = json["type_name"]?.toString()?.takeIf { it.isNotEmpty() },
                sourceKey = sourceKey,
            )
        }
    }
}

// ============================================================
// 影片列表响应
// ============================================================

/** 影片列表响应 */
@Serializable
data class VideoListResponse(
    val list: List<VideoItem>,
    val page: Int,
    val pageCount: Int,
    val total: Int,
) {
    companion object {
        fun fromJson(json: Map<String, Any?>): VideoListResponse {
            val rawList = json["list"] as? List<*> ?: emptyList<Any>()
            val items = rawList.mapNotNull { item ->
                (item as? Map<*, *>)?.let { m ->
                    @Suppress("UNCHECKED_CAST")
                    VideoItem.fromJson(m as Map<String, Any?>)
                }
            }
            return VideoListResponse(
                list = items,
                page = json["page"]?.toString()?.toIntOrNull() ?: 1,
                pageCount = json["pagecount"]?.toString()?.toIntOrNull() ?: 1,
                total = json["total"]?.toString()?.toIntOrNull() ?: 0,
            )
        }
    }
}

// ============================================================
// 影片选集
// ============================================================

/** 影片选集 */
@Serializable
data class VideoEpisode(
    val name: String,
    val url: String,
)

// ============================================================
// 播放源（一个源包含多个剧集）
// ============================================================

/** 播放源（一个源包含多个剧集） */
@Serializable
data class PlaySource(
    val name: String,
    val episodes: List<VideoEpisode>,
)

// ============================================================
// 影片详情
// ============================================================

/** 影片详情 */
@Serializable
data class VideoDetail(
    val vodId: String,
    val vodName: String,
    val vodPic: String? = null,
    val vodContent: String? = null,
    val vodActor: String? = null,
    val vodDirector: String? = null,
    val vodYear: String? = null,
    val vodArea: String? = null,
    val vodRemarks: String? = null,
    val typeName: String? = null,
    val typeId: Int? = null,
    val sourceKey: String,
    val playSources: List<PlaySource> = emptyList(),
) {
    companion object {
        fun fromJson(json: Map<String, Any?>, sourceKey: String = ""): VideoDetail {
            val sources = mutableListOf<PlaySource>()
            val vodPlayFrom = json["vod_play_from"]?.toString() ?: ""
            val vodPlayUrl = json["vod_play_url"]?.toString() ?: ""

            if (vodPlayFrom.isNotEmpty() && vodPlayUrl.isNotEmpty()) {
                val fromNames = vodPlayFrom.split("$$$")
                val fromUrls = vodPlayUrl.split("$$$")
                for (i in fromNames.indices) {
                    if (i >= fromUrls.size) break
                    val sourceName = fromNames[i].trim()
                    val episodesStr = fromUrls[i].trim()
                    val episodes = mutableListOf<VideoEpisode>()
                    if (episodesStr.isNotEmpty()) {
                        for (line in episodesStr.split("#")) {
                            val parts = line.split("$")
                            if (parts.size >= 2) {
                                episodes.add(
                                    VideoEpisode(
                                        name = parts[0].trim(),
                                        url = parts[1].trim(),
                                    )
                                )
                            }
                        }
                    }
                    if (episodes.isNotEmpty()) {
                        sources.add(PlaySource(name = sourceName, episodes = episodes))
                    }
                }
            }

            return VideoDetail(
                vodId = json["vod_id"]?.toString() ?: "",
                vodName = json["vod_name"]?.toString() ?: "未知",
                vodPic = json["vod_pic"]?.toString()?.takeIf { it.isNotEmpty() },
                vodContent = json["vod_content"]?.toString()?.takeIf { it.isNotEmpty() },
                vodActor = json["vod_actor"]?.toString()?.takeIf { it.isNotEmpty() },
                vodDirector = json["vod_director"]?.toString()?.takeIf { it.isNotEmpty() },
                vodYear = json["vod_year"]?.toString()?.takeIf { it.isNotEmpty() },
                vodArea = json["vod_area"]?.toString()?.takeIf { it.isNotEmpty() },
                vodRemarks = json["vod_remarks"]?.toString()?.takeIf { it.isNotEmpty() },
                typeName = json["type_name"]?.toString()?.takeIf { it.isNotEmpty() },
                typeId = json["type_id"]?.toString()?.toIntOrNull(),
                sourceKey = sourceKey,
                playSources = sources,
            )
        }
    }
}

// ============================================================
// 影片分类
// ============================================================

/** 影片分类 */
@Serializable
data class VideoCategory(
    val typeId: Int,
    val typePid: Int,
    val typeName: String,
) {
    companion object {
        fun fromJson(json: Map<String, Any?>): VideoCategory {
            return VideoCategory(
                typeId = json["type_id"]?.toString()?.toIntOrNull() ?: 0,
                typePid = json["type_pid"]?.toString()?.toIntOrNull() ?: 0,
                typeName = json["type_name"]?.toString() ?: "",
            )
        }
    }
}

// ============================================================
// 视频解析接口
// ============================================================

/** 视频解析接口 */
@Serializable
data class VideoParser(
    val key: String,
    val name: String,
    val urlTemplate: String,
    val enabled: Boolean = true,
) {
    /** 构建解析后的完整 URL */
    fun buildUrl(videoUrl: String): String =
        urlTemplate.replace("{url}", videoUrl)

    companion object {
        val defaultParsers: List<VideoParser> = listOf(
            VideoParser(key = "yparse", name = "YParse", urlTemplate = "https://yparse.ik9.cc/index.php?url={url}"),
            VideoParser(key = "m3u8tv", name = "M3U8.TV", urlTemplate = "https://jx.m3u8.tv/jiexi/?url={url}"),
            VideoParser(key = "ik9", name = "IK9 自建", urlTemplate = "http://82.156.40.118:1234/jx/?url={url}"),
            VideoParser(key = "oftens", name = "Oftens", urlTemplate = "https://jx.oftens.top/player/?url={url}"),
            VideoParser(key = "jlk", name = "JLK解析", urlTemplate = "https://jlk.jianghu.vip/?url={url}"),
        )
    }
}
'@
[System.IO.File]::WriteAllText("e:\mediamix-kmp\shared\src\commonMain\kotlin\com\mediamix\shared\models\VideoModels.kt", $videoModels, $utf8)
Write-Host "VideoModels.kt written"

# ============================================================
# 2. SpiderAdapter.kt
# ============================================================
$spiderAdapter = @'
package com.mediamix.shared.spider

import com.mediamix.shared.models.*

/**
 * 蜘蛛适配器接口
 *
 * 所有蜘蛛（CMS / JSON / XPath / JavaBridge）实现此接口，
 * 由 SpiderRegistry 统一管理并按需调用。
 */
interface SpiderAdapter {
    /** 唯一标识 */
    val key: String

    /** 显示名称 */
    val name: String

    /** 蜘蛛类型 */
    val type: SpiderType

    /** 是否支持搜索，默认 true */
    val isSearchSupported: Boolean get() = true

    /** 初始化 */
    suspend fun init(config: Map<String, Any>)

    /** 首页内容 */
    suspend fun homeContent(page: Int = 1): SpiderHomeResult

    /** 分类内容 */
    suspend fun categoryContent(
        tid: String,
        page: Int = 1,
        filter: Map<String, String>? = null,
    ): SpiderListResult

    /** 详情内容 */
    suspend fun detailContent(id: String): SpiderDetailResult

    /** 搜索内容 */
    suspend fun searchContent(keyword: String, page: Int = 1): SpiderListResult

    /** 播放内容 */
    suspend fun playerContent(flag: String, id: String): SpiderPlayResult

    /** 释放资源，默认空实现 */
    fun dispose() {}
}
'@
[System.IO.File]::WriteAllText("e:\mediamix-kmp\shared\src\commonMain\kotlin\com\mediamix\shared\spider\SpiderAdapter.kt", $spiderAdapter, $utf8)
Write-Host "SpiderAdapter.kt written"
