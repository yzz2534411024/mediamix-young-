package com.mediamix.ui.di

import com.mediamix.ui.viewmodel.*
import org.koin.core.module.Module
import org.koin.dsl.module

/**
 * UI 层 Koin DI 模块
 *
 * 注册所有 ViewModel，依赖由 sharedModule 提供
 */
val uiModule: Module = module {
    factory { VideoHomeViewModel(spiderService = get(), httpClient = get()) }
    factory { VideoDetailViewModel(httpClient = get(), spiderService = get()) }
    factory { PlayerViewModel(playerCoreManager = get()) }
    factory { SearchViewModel(httpClient = get(), spiderService = get()) }
    factory { HistoryViewModel() }
    factory { FavoriteViewModel() }
    factory { SettingsViewModel(settings = get()) }
    factory { SourceManageViewModel(httpClient = get(), spiderService = get()) }
}
