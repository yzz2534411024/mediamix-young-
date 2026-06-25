import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import '../models/video_models.dart';
import '../services/tbox_api_service.dart';
import '../services/spider/spider_service.dart';
import '../services/spider/java_bridge_manager.dart';
import '../services/spider/tvbox_config_parser.dart';
import '../../../core/database/database.dart' hide VideoSource;
import '../../../core/database/database_provider.dart';
import '../../../core/services/player_metrics_service.dart';
import '../../../core/services/video_cache_service.dart';
import '../../../core/services/preload_service.dart';
import '../../../core/services/power_manager_service.dart';
import '../../../core/services/privacy_manager_service.dart';
import '../../../core/services/metrics_collector_service.dart';
import '../../../core/services/data_reporter_service.dart';
import '../../../core/network/network_engine.dart' hide CacheStats;
import 'package:logger/logger.dart';

final _logger = Logger(printer: SimplePrinter());

// ===== API 服务 Provider =====
final videoApiServiceProvider = Provider<VideoApiService>((ref) => VideoApiService());

final spiderServiceProvider = Provider<SpiderService>((ref) {
  final service = SpiderService();
  ref.onDispose(() => service.disposeAll());
  return service;
});

final tvboxConfigProvider = FutureProvider.family<TvBoxConfig, String>((ref, configUrl) async {
  final service = ref.read(spiderServiceProvider);
  return service.fetchTvBoxConfig(configUrl);
});

// ===== TVBox 源检测与蜘蛛分类 =====

/// 检测当前站点是否为 TVBox 配置源
final isTvBoxSourceProvider = Provider<bool>((ref) {
  final site = ref.watch(currentSiteProvider);
  if (site == null) return false;
  return site.isTvBox;
});

/// 蜘蛛分类列表（TVBox 子站点映射为分类）
final spiderCategoriesProvider = FutureProvider<List<VideoCategory>>((ref) async {
  final site = ref.watch(currentSiteProvider);
  if (site == null || !site.isTvBox) return [];

  final config = ref.watch(tvboxConfigProvider(site.apiUrl));
  return config.when(
    data: (tvboxConfig) {
      return tvboxConfig.sites.asMap().entries.map((entry) {
        final tvboxSite = entry.value;
        return VideoCategory(
          typeId: entry.key + 1,
          typeName: tvboxSite.name,
          typePid: 0,
        );
      }).toList();
    },
    loading: () => <VideoCategory>[],
    error: (_, __) => <VideoCategory>[],
  );
});

/// Java Bridge 是否可用
final javaBridgeAvailableProvider = Provider<bool>((ref) {
  return JavaBridgeManager.instance.isRunning &&
      JavaBridgeManager.instance.client != null;
});

// ===== 站点列表 Provider =====
final cmsSiteListProvider = StateProvider<List<CmsApiSite>>((ref) => CmsApiSite.defaultSites.toList());

/// 启用的站点列表（过滤掉 disabled 的源）
final enabledSitesProvider = Provider<List<CmsApiSite>>((ref) {
  final sites = ref.watch(cmsSiteListProvider);
  return sites.where((s) => s.enabled).toList();
});

/// 源状态检测结果 Provider
final sourceStatusProvider = StateProvider<Map<String, SourceStatus>>((ref) => const {});

/// 源管理操作 Provider
final sourceActionsProvider = Provider<SourceActions>((ref) => SourceActions(ref));

class SourceActions {
  final Ref _ref;
  SourceActions(this._ref);

  /// 添加自定义源
  void addSource(CmsApiSite site) {
    final sites = _ref.read(cmsSiteListProvider);
    // 检查 key 是否重复
    if (sites.any((s) => s.key == site.key)) return;
    _ref.read(cmsSiteListProvider.notifier).state = [...sites, site];
  }

  /// 删除自定义源（内置源不可删）
  void removeSource(String key) {
    final sites = _ref.read(cmsSiteListProvider);
    final site = sites.where((s) => s.key == key).firstOrNull;
    if (site == null || site.isBuiltIn) return;
    _ref.read(cmsSiteListProvider.notifier).state = sites.where((s) => s.key != key).toList();
    // 如果删除的是当前选中源，切换到第一个可用源
    final current = _ref.read(currentSiteProvider);
    if (current?.key == key) {
      final remaining = _ref.read(cmsSiteListProvider).where((s) => s.enabled).toList();
      _ref.read(currentSiteProvider.notifier).state = remaining.isNotEmpty ? remaining.first : null;
    }
  }

  /// 启用/禁用源
  void toggleSourceEnabled(String key) {
    final sites = _ref.read(cmsSiteListProvider);
    _ref.read(cmsSiteListProvider.notifier).state = sites.map((s) {
      if (s.key == key) return s.copyWith(enabled: !s.enabled);
      return s;
    }).toList();
    // 如果禁用的是当前选中源，切换到第一个可用源
    final current = _ref.read(currentSiteProvider);
    if (current?.key == key) {
      final enabledSites = _ref.read(cmsSiteListProvider).where((s) => s.enabled).toList();
      if (!enabledSites.any((s) => s.key == key)) {
        _ref.read(currentSiteProvider.notifier).state = enabledSites.isNotEmpty ? enabledSites.first : null;
      }
    }
  }

  /// 检测单个源可用性
  Future<SourceStatus> checkSource(CmsApiSite site) async {
    final api = _ref.read(videoApiServiceProvider);
    final stopwatch = Stopwatch()..start();
    try {
      await api.fetchCategories(site.apiUrl).timeout(const Duration(seconds: 10));
      stopwatch.stop();
      final status = SourceStatus(key: site.key, isAvailable: true, latencyMs: stopwatch.elapsedMilliseconds);
      _updateStatus(site.key, status);
      return status;
    } catch (e) {
      stopwatch.stop();
      final status = SourceStatus(key: site.key, isAvailable: false, latencyMs: -1, error: e.toString());
      _updateStatus(site.key, status);
      return status;
    }
  }

  /// 检测所有源
  Future<void> checkAllSources() async {
    final sites = _ref.read(cmsSiteListProvider);
    final futures = sites.map((site) => checkSource(site));
    await Future.wait(futures);
  }

  void _updateStatus(String key, SourceStatus status) {
    final current = _ref.read(sourceStatusProvider);
    _ref.read(sourceStatusProvider.notifier).state = {...current, key: status};
  }
}

// ===== 当前选中站点 =====
final currentSiteProvider = StateProvider<CmsApiSite?>((ref) {
  final sites = ref.watch(enabledSitesProvider);
  return sites.isNotEmpty ? sites.first : null;
});

// ===== 分类列表 Provider（缓存24小时） =====
final categoryListProvider = FutureProvider<List<VideoCategory>>((ref) async {
  // ignore: unused_result
  ref.keepAlive();
  final site = ref.watch(currentSiteProvider);
  if (site == null) return [];
  final api = ref.read(videoApiServiceProvider);
  return api.fetchCategories(site.apiUrl);
});

// ===== 当前选中分类 =====
final selectedCategoryProvider = StateProvider<VideoCategory?>((ref) => null);

// ===== 首页影片列表 Provider（追加加载） =====
final videoListProvider = AsyncNotifierProvider<VideoListNotifier, VideoListState>(
  VideoListNotifier.new,
);

/// 影片列表状态（支持追加）
class VideoListState {
  final List<VideoItem> items;
  final int currentPage;
  final int totalPages;
  final bool hasMore;
  final bool isLoadingMore;

  const VideoListState({
    this.items = const [],
    this.currentPage = 1,
    this.totalPages = 1,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  VideoListState copyWith({
    List<VideoItem>? items,
    int? currentPage,
    int? totalPages,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return VideoListState(
      items: items ?? this.items,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class VideoListNotifier extends AsyncNotifier<VideoListState> {
  @override
  Future<VideoListState> build() async {
    final site = ref.watch(currentSiteProvider);
    final category = ref.watch(selectedCategoryProvider);
    if (site == null) return const VideoListState();

    // TVBox 源走蜘蛛引擎
    if (site.isTvBox) {
      return _loadSpiderContent(site, category);
    }

    // 标准 CMS 路径
    return _loadCmsContent(site, category);
  }

  /// CMS 标准加载（原有逻辑）
  Future<VideoListState> _loadCmsContent(CmsApiSite site, VideoCategory? category) async {
    final api = ref.read(videoApiServiceProvider);

    // 首次加载合并两页数据，增加首页推荐数量
    final page1Future = api.fetchVideoList(site.apiUrl, page: 1, typeId: category?.typeId);
    final page2Future = api.fetchVideoList(site.apiUrl, page: 2, typeId: category?.typeId);

    final results = await Future.wait([page1Future, page2Future], eagerError: true);
    final page1 = results[0];
    final page2 = results[1];

    // 合并去重（按 vodId 去重）
    final seenIds = <String>{};
    final allItems = <VideoItem>[];
    for (final item in [...page1.list, ...page2.list]) {
      if (!seenIds.contains(item.vodId)) {
        seenIds.add(item.vodId);
        allItems.add(item);
      }
    }

    return VideoListState(
      items: allItems,
      currentPage: 2, // 已加载到第2页
      totalPages: page1.pageCount,
      hasMore: 2 < page1.pageCount,
    );
  }

  /// 蜘蛛引擎加载（TVBox 源）
  Future<VideoListState> _loadSpiderContent(CmsApiSite site, VideoCategory? category) async {
    final spiderService = ref.read(spiderServiceProvider);

    // 获取 TVBox 配置
    final config = await spiderService.fetchTvBoxConfig(site.apiUrl);

    // 初始化蜘蛛（会自动启动 Java Bridge）
    final spiders = await spiderService.initFromConfig(config);
    if (spiders.isEmpty) {
      // 检查 Java Bridge 是否可用
      if (!JavaBridgeManager.instance.isRunning) {
        throw const SpiderEngineException(
          '该源需要 Java 环境支持，请在设置中配置 Java 运行时',
        );
      }
      return const VideoListState();
    }

    if (category != null) {
      // 选中了特定分类（子站点），加载该蜘蛛的内容
      final siteIndex = category.typeId - 1;
      if (siteIndex >= 0 && siteIndex < config.sites.length) {
        final tvboxSite = config.sites[siteIndex];
        final spider = spiderService.getSpider(tvboxSite.key);
        if (spider != null) {
          final result = await spider.homeContent(page: 1);
          return VideoListState(
            items: result.recommend,
            currentPage: 1,
            totalPages: 1,
            hasMore: false,
          );
        }
      }
      return const VideoListState();
    }

    // 未选分类：加载所有蜘蛛的首页推荐
    final allItems = <VideoItem>[];
    final seenIds = <String>{};
    for (final spider in spiders) {
      try {
        final result = await spider.homeContent(page: 1);
        for (final item in result.recommend) {
          if (!seenIds.contains(item.vodId)) {
            seenIds.add(item.vodId);
            allItems.add(item);
          }
        }
      } catch (e) {
        _logger.w('蜘蛛 ${spider.key} 首页加载失败: $e');
      }
    }

    if (allItems.isEmpty && !JavaBridgeManager.instance.isRunning) {
      throw const SpiderEngineException(
        '该源需要 Java 环境支持，请在设置中配置 Java 运行时',
      );
    }

    return VideoListState(
      items: allItems,
      currentPage: 1,
      totalPages: 1,
      hasMore: false,
    );
  }

  /// 加载下一页（追加模式，仅 CMS 源支持）
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    // 蜘蛛源不支持分页
    final site = ref.read(currentSiteProvider);
    if (site == null) return;
    if (site.isTvBox) return;

    // 标记加载中
    state = AsyncData(current.copyWith(isLoadingMore: true));

    final category = ref.read(selectedCategoryProvider);

    final api = ref.read(videoApiServiceProvider);
    final nextPage = current.currentPage + 1;

    try {
      final response = await api.fetchVideoList(
        site.apiUrl,
        page: nextPage,
        typeId: category?.typeId,
      );

      state = AsyncData(VideoListState(
        items: [...current.items, ...response.list],
        currentPage: response.page,
        totalPages: response.pageCount,
        hasMore: response.page < response.pageCount,
        isLoadingMore: false,
      ));
    } catch (e) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// 刷新
  Future<void> refresh() async {
    state = const AsyncLoading();
    final site = ref.read(currentSiteProvider);
    final category = ref.read(selectedCategoryProvider);
    if (site == null) {
      state = const AsyncData(VideoListState());
      return;
    }

    // TVBox 源走蜘蛛引擎
    if (site.isTvBox) {
      try {
        final result = await _loadSpiderContent(site, category);
        state = AsyncData(result);
      } catch (e) {
        state = AsyncError(e, StackTrace.current);
      }
      return;
    }

    // 标准 CMS 路径
    final api = ref.read(videoApiServiceProvider);
    try {
      // 刷新时也合并两页数据，增加首页推荐数量
      final page1Future = api.fetchVideoList(site.apiUrl, page: 1, typeId: category?.typeId);
      final page2Future = api.fetchVideoList(site.apiUrl, page: 2, typeId: category?.typeId);

      final results = await Future.wait([page1Future, page2Future], eagerError: true);
      final page1 = results[0];
      final page2 = results[1];

      // 合并去重（按 vodId 去重）
      final seenIds = <String>{};
      final allItems = <VideoItem>[];
      for (final item in [...page1.list, ...page2.list]) {
        if (!seenIds.contains(item.vodId)) {
          seenIds.add(item.vodId);
          allItems.add(item);
        }
      }

      state = AsyncData(VideoListState(
        items: allItems,
        currentPage: 2, // 已加载到第2页
        totalPages: page1.pageCount,
        hasMore: 2 < page1.pageCount,
      ));
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }
}

// ===== 影片详情 Provider（换源并行化，缓存，DNS预解析） =====
final videoDetailProvider = FutureProvider.family<VideoDetail, ({String vodId, String sourceKey})>((ref, params) async {
  // 保持缓存，返回详情页时不重新加载
  // ignore: unused_result
  ref.keepAlive();
  final sites = ref.read(enabledSitesProvider);
  final api = ref.read(videoApiServiceProvider);

  // DNS 预解析：提前解析所有站点域名（不阻塞主流程）
  final allApiUrls = sites.map((s) => s.apiUrl).toList();
  api.prefetchDns(allApiUrls);

  // 使用优化后的并行请求方法
  final otherSites = sites.where((s) => s.key != params.sourceKey).toList();
  try {
    final detail = await api.fetchVideoDetailParallel(
      sites.firstWhere((s) => s.key == params.sourceKey).apiUrl,
      params.vodId,
      sourceKey: params.sourceKey,
      otherSites: otherSites,
    );
    return detail;
  } catch (e) {
    _logger.e('并行获取详情失败，回退到单源获取: $e');
    // 回退：仅从原始站点获取
    final originalSite = sites.where((s) => s.key == params.sourceKey).firstOrNull;
    if (originalSite == null) throw Exception('站点不存在');
    return api.fetchVideoDetail(originalSite.apiUrl, params.vodId, sourceKey: params.sourceKey);
  }
});

/// 相关推荐 Provider（同分类影片）
final relatedVideosProvider = FutureProvider.family<List<VideoItem>, ({String sourceKey, int? typeId, String excludeVodId})>((ref, params) async {
  if (params.typeId == null) return [];
  final site = ref.watch(currentSiteProvider);
  if (site == null) return [];
  final api = ref.read(videoApiServiceProvider);
  try {
    final response = await api.fetchVideoList(site.apiUrl, page: 1, typeId: params.typeId);
    return response.list.where((item) => item.vodId != params.excludeVodId).take(20).toList();
  } catch (e) {
    return [];
  }
});

// ===== 搜索 Provider（防抖 + 多源搜索） =====

/// 搜索防抖控制器
// ignore: unused_element
final _searchDebounceProvider = Provider<Timer?>((ref) => null);

/// 搜索查询（带防抖）
final searchQueryProvider = StateProvider<String>((ref) => '');

/// 防抖后的搜索查询
final debouncedSearchQueryProvider = StateProvider<String>((ref) => '');

/// 搜索结果（多源合并）
final searchResultProvider = FutureProvider<VideoListResponse>((ref) async {
  final query = ref.watch(debouncedSearchQueryProvider);
  if (query.isEmpty) return const VideoListResponse(list: [], page: 1, pageCount: 1, total: 0);

  final sites = ref.read(enabledSitesProvider);
  final api = ref.read(videoApiServiceProvider);

  // 并行搜索所有站点
  final futures = sites.map((site) async {
    try {
      final result = await api.searchVideos(site.apiUrl, query).timeout(const Duration(seconds: 5));
      // 给每个结果标记来源
      return result.list.map((item) => VideoItem(
        vodId: item.vodId,
        vodName: item.vodName,
        vodPic: item.vodPic,
        vodRemarks: item.vodRemarks,
        vodYear: item.vodYear,
        vodArea: item.vodArea,
        typeName: item.typeName,
        sourceKey: site.key, // 标记来源
      )).toList();
    } catch (e) {
      return <VideoItem>[];
    }
  }).toList();

  final results = await Future.wait(futures);

  // 合并去重（按 vodName 去重，保留第一个）
  final seen = <String>{};
  final allItems = <VideoItem>[];
  for (final items in results) {
    for (final item in items) {
      if (!seen.contains(item.vodName)) {
        seen.add(item.vodName);
        allItems.add(item);
      }
    }
  }

  return VideoListResponse(
    list: allItems,
    page: 1,
    pageCount: 1,
    total: allItems.length,
  );
});

// ===== 历史观看记录 Provider =====
final watchHistoryProvider = StreamProvider<List<WatchHistory>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllWatchHistories();
});

final watchHistoryActionsProvider = Provider<WatchHistoryActions>((ref) {
  return WatchHistoryActions(ref);
});

class WatchHistoryActions {
  final Ref _ref;
  WatchHistoryActions(this._ref);

  /// 添加/更新观看历史
  Future<void> addOrUpdateHistory({
    required String vodId,
    required String vodName,
    String? vodPic,
    required String sourceKey,
    String? episodeName,
  }) async {
    final db = _ref.read(databaseProvider);
    await db.insertWatchHistory(WatchHistoriesCompanion.insert(
      vodId: vodId,
      vodName: vodName,
      vodPic: Value(vodPic),
      sourceKey: sourceKey,
      episodeName: Value(episodeName),
      lastWatchTime: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// 删除单条历史
  Future<void> deleteHistory(String vodId) async {
    final db = _ref.read(databaseProvider);
    await db.deleteWatchHistory(vodId);
  }

  /// 清空所有历史
  Future<void> clearAllHistory() async {
    final db = _ref.read(databaseProvider);
    await db.clearAllWatchHistories();
  }
}

// ===== 收藏 Provider =====

/// 收藏列表（Stream 实时监听）
final favoriteListProvider = StreamProvider<List<Favorite>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllFavorites();
});

/// 检查是否已收藏
final isFavoriteProvider = StreamProvider.family<bool, String>((ref, vodId) {
  final db = ref.watch(databaseProvider);
  return db.isFavoriteStream(vodId);
});

/// 收藏操作
final favoriteActionsProvider = Provider<FavoriteActions>((ref) {
  return FavoriteActions(ref);
});

class FavoriteActions {
  final Ref _ref;
  FavoriteActions(this._ref);

  /// 添加收藏
  Future<void> addFavorite({
    required String vodId,
    required String vodName,
    String? vodPic,
    required String sourceKey,
    String? typeName,
    int episodeCount = 0,
  }) async {
    final db = _ref.read(databaseProvider);
    await db.insertFavorite(FavoritesCompanion.insert(
      vodId: vodId,
      vodName: vodName,
      vodPic: Value(vodPic),
      sourceKey: sourceKey,
      typeName: Value(typeName),
      lastEpisodeCount: Value(episodeCount),
      addTime: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// 取消收藏
  Future<void> removeFavorite(String vodId) async {
    final db = _ref.read(databaseProvider);
    await db.deleteFavorite(vodId);
  }

  /// 切换收藏状态
  Future<void> toggleFavorite({
    required String vodId,
    required String vodName,
    String? vodPic,
    required String sourceKey,
    String? typeName,
    int episodeCount = 0,
  }) async {
    final db = _ref.read(databaseProvider);
    final existing = await db.getFavorite(vodId);
    if (existing != null) {
      await db.deleteFavorite(vodId);
    } else {
      await addFavorite(
        vodId: vodId,
        vodName: vodName,
        vodPic: vodPic,
        sourceKey: sourceKey,
        typeName: typeName,
        episodeCount: episodeCount,
      );
    }
  }

  /// 检测追番更新：比对当前集数与收藏时记录的集数
  Future<bool> hasUpdate(String vodId, int currentEpisodeCount) async {
    final db = _ref.read(databaseProvider);
    final fav = await db.getFavorite(vodId);
    if (fav == null) return false;
    return currentEpisodeCount > fav.lastEpisodeCount;
  }

  /// 更新追番集数（用户查看后标记已读）
  Future<void> markAsRead(String vodId, int currentEpisodeCount) async {
    final db = _ref.read(databaseProvider);
    await db.updateEpisodeCount(vodId, currentEpisodeCount);
  }
}

// ===== 下载任务 Provider =====
final downloadTasksProvider = StreamProvider<List<DownloadTask>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllDownloadTasks();
});

// ===== 优化服务 Provider =====

/// 播放器性能监控服务
final playerMetricsServiceProvider = Provider<PlayerMetricsService>((ref) {
  return PlayerMetricsService.instance;
});

/// 视频缓存服务
final videoCacheServiceProvider = Provider<VideoCacheService>((ref) {
  final service = VideoCacheService.instance;
  ref.onDispose(() => service.dispose());
  return service;
});

/// 预加载服务
final preloadServiceProvider = Provider<PreloadService>((ref) {
  final cacheService = ref.read(videoCacheServiceProvider);
  return PreloadService(cacheService: cacheService);
});

/// 功耗管理服务
final powerManagerServiceProvider = Provider<PowerManagerService>((ref) {
  final service = PowerManagerService.instance;
  ref.onDispose(() => service.dispose());
  return service;
});

/// 网络引擎
final networkEngineProvider = Provider<NetworkEngine>((ref) {
  return NetworkEngine.instance;
});

/// 网络状态 Provider（实时监听网络条件变化）
final networkConditionProvider = StreamProvider<NetworkCondition>((ref) {
  return NetworkEngine.instance.onConditionChanged;
});

/// 缓存统计 Provider
final cacheStatsProvider = StreamProvider<CacheStats>((ref) {
  return VideoCacheService.instance.statsStream;
});

/// 播放指标 Provider（实时监听播放质量变化）
final playbackMetricsProvider = StreamProvider<PlaybackMetrics>((ref) {
  return PlayerMetricsService.instance.metricsStream;
});

/// 功耗模式 Provider
final powerModeProvider = StreamProvider<PowerMode>((ref) {
  return PowerManagerService.instance.onModeChanged;
});

// ===== 隐私与数据采集 Provider =====

/// 隐私管理服务
final privacyManagerProvider = Provider<PrivacyManagerService>((ref) {
  return PrivacyManagerService.instance;
});

/// 指标采集服务
final metricsCollectorProvider = Provider<MetricsCollectorService>((ref) {
  return MetricsCollectorService.instance;
});

/// 数据上报服务
final dataReporterProvider = Provider<DataReporterService>((ref) {
  return DataReporterService.instance;
});

/// 隐私偏好 Provider（实时监听开关变化）
final privacyPreferencesProvider = StreamProvider<PrivacyPreferences>((ref) {
  final service = PrivacyManagerService.instance;
  return service.preferencesStream;
});
