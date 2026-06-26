package com.mediamix.shared.spider

import com.mediamix.shared.models.*

/**
 * CMS 采集站蜘蛛适配器
 *
 * 基于 TVBox 站点配置，通过 [VideoApiService] 调用标准 CMS API。
 */
class CmsSpider(
    private val site: TvBoxSite,
    // TODO: VideoApiService 尚未完全迁移，此处使用延迟初始化
    // private val apiService: VideoApiService = VideoApiService(),
) : SpiderAdapter {

    override val key: String get() = site.key
    override val name: String get() = site.name
    override val type: SpiderType get() = SpiderType.CMS
    override val isSearchSupported: Boolean get() = true

    override suspend fun init(config: Map<String, Any>) {
        // CMS 蜘蛛无需额外初始化
    }

    override suspend fun homeContent(page: Int): SpiderHomeResult {
        // TODO: 依赖 VideoApiService 迁移完成后实现
        // val categories = apiService.fetchCategories(site.api)
        // val videoList = apiService.fetchVideoList(site.api, page = page)
        //
        // val spiderCategories = categories.map { c ->
        //     SpiderCategory(
        //         typeId = c.typeId.toString(),
        //         typeName = c.typeName,
        //     )
        // }
        //
        // val classList = mutableMapOf<String, List<VideoItem>>()
        // for (category in categories) {
        //     classList[category.typeId.toString()] = emptyList()
        // }
        //
        // return SpiderHomeResult(
        //     categories = spiderCategories,
        //     recommend = videoList.list,
        //     classList = classList,
        // )
        return SpiderHomeResult()
    }

    override suspend fun categoryContent(
        tid: String,
        page: Int,
        filter: Map<String, String>?,
    ): SpiderListResult {
        // TODO: 依赖 VideoApiService 迁移完成后实现
        // val typeId = tid.toIntOrNull()
        // val videoList = apiService.fetchVideoList(site.api, page = page, typeId = typeId)
        // return SpiderListResult(
        //     list = videoList.list,
        //     page = videoList.page,
        //     pageCount = videoList.pageCount,
        //     total = videoList.total,
        // )
        return SpiderListResult()
    }

    override suspend fun detailContent(id: String): SpiderDetailResult {
        // TODO: 依赖 VideoApiService 迁移完成后实现
        // val detail = apiService.fetchVideoDetail(site.api, id, sourceKey = key)
        // return SpiderDetailResult(detail = detail)
        return SpiderDetailResult(
            detail = VideoDetail(vodId = id, vodName = "未知", sourceKey = key)
        )
    }

    override suspend fun searchContent(keyword: String, page: Int): SpiderListResult {
        // TODO: 依赖 VideoApiService 迁移完成后实现
        // val videoList = apiService.searchVideos(site.api, keyword)
        // return SpiderListResult(
        //     list = videoList.list,
        //     page = videoList.page,
        //     pageCount = videoList.pageCount,
        //     total = videoList.total,
        // )
        return SpiderListResult()
    }

    override suspend fun playerContent(flag: String, id: String): SpiderPlayResult {
        return SpiderPlayResult(url = id, parse = "0")
    }

    override fun dispose() {
        // TODO: apiService.clearAllCache()
    }
}
