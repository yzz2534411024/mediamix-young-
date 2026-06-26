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
