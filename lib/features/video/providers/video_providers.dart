import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import '../models/video_models.dart';
import '../services/tbox_api_service.dart';
import '../../../core/database/database.dart' hide VideoSource;
import '../../../core/database/database_provider.dart';
import '../../../core/services/player_metrics_service.dart';
import '../../../core/services/video_cache_service.dart';
import '../../../core/services/preload_service.dart';
import '../../../core/services/power_manager_service.dart';
import '../../../core/network/network_engine.dart' hide CacheStats;
import 'package:logger/logger.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0));

// ===== API 服务 Provider =====
final videoApiServiceProvider = Provider<VideoApiService>((ref) => VideoApiService());

// ===== 站点列表 Provider（修复不可用源） =====
final cmsSiteListProvider = StateProvider<List<CmsApiSite>>((ref) => const [
  CmsApiSite(key: 'bfzy', name: '暴风资源', apiUrl: 'https://bfzyapi.com/api.php/provide/vod/', isBuiltIn: true),
  CmsApiSite(key: 'lzzy', name: '量子资源', apiUrl: 'https://cjhd.lziapi.com/api.php/provide/vod/', isBuiltIn: true),
  CmsApiSite(key: 'ffzy', name: '非凡资源', apiUrl: 'https://cjhd.ffzyapi.com/api.php/provide/vod/', isBuiltIn: true),
  CmsApiSite(key: 'zyk1080', name: '1080资源库', apiUrl: 'http://api.1080zyku.com/inc/api.php/provide/vod/', isBuiltIn: true),
  CmsApiSite(key: 'hnzy', name: '红牛资源', apiUrl: 'http://hongniuzy2.com/api.php/provide/vod/', isBuiltIn: true),
]);

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

    final api = ref.read(videoApiServiceProvider);
    final response = await api.fetchVideoList(
      site.apiUrl,
      page: 1,
      typeId: category?.typeId,
    );

    return VideoListState(
      items: response.list,
      currentPage: response.page,
      totalPages: response.pageCount,
      hasMore: response.page < response.pageCount,
    );
  }

  /// 加载下一页（追加模式）
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    // 标记加载中
    state = AsyncData(current.copyWith(isLoadingMore: true));

    final site = ref.read(currentSiteProvider);
    final category = ref.read(selectedCategoryProvider);
    if (site == null) return;

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
    final api = ref.read(videoApiServiceProvider);
    try {
      final response = await api.fetchVideoList(
        site.apiUrl,
        page: 1,
        typeId: category?.typeId,
      );
      state = AsyncData(VideoListState(
        items: response.list,
        currentPage: response.page,
        totalPages: response.pageCount,
        hasMore: response.page < response.pageCount,
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

// ===== 搜索 Provider（防抖 + 多源搜索） =====

/// 搜索防抖控制器
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
