import '../../../../core/services/video_cache_service.dart';
import '../../../../core/services/player_metrics_service.dart';
import '../../../../core/services/metrics_collector_service.dart';
import '../../../../core/services/local_proxy_server.dart';
import '../../../../core/services/power_manager_service.dart';
import 'engine_interfaces.dart';
import 'package:logger/logger.dart';

class CacheEngineImpl implements CacheEngine {
  final Logger _logger = Logger(printer: SimplePrinter());

  bool _isUsingCache = false;

  /// 预加载服务回调（由外部注入）
  void Function(String videoId, String url)? _preloadNextEpisode;
  void Function(List<int> indices, String title, List<String> episodeUrls)?
      _preloadAdjacent;
  void Function(bool isBuffering)? _notifyPreloadBuffering;

  /// 已预加载但未使用的 videoId 集合（用于回收）
  final Set<String> _preloadedVideoIds = {};

  CacheEngineImpl({
    void Function(String videoId, String url)? onPreloadNextEpisode,
    void Function(List<int> indices, String title, List<String> episodeUrls)?
        onPreloadAdjacent,
    void Function(bool isBuffering)? onNotifyPreloadBuffering,
  }) {
    _preloadNextEpisode = onPreloadNextEpisode;
    _preloadAdjacent = onPreloadAdjacent;
    _notifyPreloadBuffering = onNotifyPreloadBuffering;
  }

  @override
  bool get isUsingCache => _isUsingCache;

  @override
  Future<String> resolveVideoUrl(String url, String videoId) async {
    try {
      // 检查完整缓存（L3 磁盘缓存）
      final cachedPath =
          await VideoCacheService.instance.getCachePath(videoId);
      if (cachedPath != null) {
        _logger.i('缓存命中，使用本地文件: $videoId');
        _isUsingCache = true;
        PlayerMetricsService.instance.recordEvent(MetricsEvent.cacheHit);
        MetricsCollectorService.instance.recordEvent(MetricsEvent.cacheHit);
        // 命中缓存时从预加载集合移除（已被使用）
        _preloadedVideoIds.remove(videoId);
        return cachedPath;
      }

      PlayerMetricsService.instance.recordEvent(MetricsEvent.cacheMiss);
      MetricsCollectorService.instance.recordEvent(MetricsEvent.cacheMiss);
      _isUsingCache = false;

      // 启动本地代理，走边播边缓存通道（添加超时保护）
      try {
        await LocalProxyServer.instance.start()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        _logger.w('本地代理启动失败，使用原始URL: $e');
        _isUsingCache = false;
        return url;
      }
      final proxyUrl = LocalProxyServer.instance.proxyUrl(url, videoId);
      _logger.i(
          '通过本地代理播放: $videoId → 127.0.0.1:${LocalProxyServer.instance.port}');
      return proxyUrl;
    } catch (e) {
      _logger.w('缓存/代理查询失败，使用网络URL: $e');
      _isUsingCache = false;
    }
    return url;
  }

  @override
  Future<CacheResolveResult> resolveVideoUrlWithFallback(String url, String videoId, {String? preferredQuality}) async {
    try {
      // 1. 精确匹配：请求的清晰度有缓存
      final exactPath = await VideoCacheService.instance.getCachePath(videoId, quality: preferredQuality ?? '720p');
      if (exactPath != null) {
        _logger.i('缓存精确命中: $videoId@${preferredQuality ?? "720p"}');
        _isUsingCache = true;
        PlayerMetricsService.instance.recordEvent(MetricsEvent.cacheHit);
        MetricsCollectorService.instance.recordEvent(MetricsEvent.cacheHit);
        _preloadedVideoIds.remove(videoId);
        return CacheResolveResult(url: exactPath, isUsingCache: true);
      }

      // 2. 降级匹配：其他清晰度有缓存
      final fallback = await VideoCacheService.instance.getAnyQualityCachePath(videoId, preferredQuality: preferredQuality);
      if (fallback != null) {
        _logger.i('缓存降级命中: $videoId 请求${preferredQuality ?? "默认"}，使用${fallback.quality}');
        _isUsingCache = true;
        PlayerMetricsService.instance.recordEvent(MetricsEvent.cacheHit);
        MetricsCollectorService.instance.recordEvent(MetricsEvent.cacheHit);
        _preloadedVideoIds.remove(videoId);
        return CacheResolveResult(
          url: fallback.path,
          isUsingCache: true,
          fallbackQuality: fallback.quality,
        );
      }

      // 3. 未命中：走代理（添加超时保护）
      PlayerMetricsService.instance.recordEvent(MetricsEvent.cacheMiss);
      MetricsCollectorService.instance.recordEvent(MetricsEvent.cacheMiss);
      _isUsingCache = false;

      try {
        await LocalProxyServer.instance.start()
            .timeout(const Duration(seconds: 5));
        final proxyUrl = LocalProxyServer.instance.proxyUrl(url, videoId);
        return CacheResolveResult(url: proxyUrl, isUsingCache: false);
      } catch (e) {
        _logger.w('本地代理启动失败，使用原始URL: $e');
        return CacheResolveResult(url: url, isUsingCache: false);
      }
    } catch (e) {
      _logger.w('缓存/代理查询失败，使用网络URL: $e');
      _isUsingCache = false;
      return CacheResolveResult(url: url, isUsingCache: false);
    }
  }

  @override
  void notifyPreloadBuffering(bool isBuffering) {
    _notifyPreloadBuffering?.call(isBuffering);
  }

  @override
  void preloadNextEpisode(String videoId, String url) {
    _preloadedVideoIds.add(videoId);
    _preloadNextEpisode?.call(videoId, url);
  }

  @override
  void preloadAdjacentEpisodes(List<int> indices, String title,
      List<String> episodeUrls, PowerMode powerMode) {
    if (powerMode == PowerMode.powerSaving) {
      _logger.d('省电模式，跳过预加载');
      return;
    }
    // 记录预加载的 videoId
    for (final i in indices) {
      if (i >= 0 && i < episodeUrls.length) {
        _preloadedVideoIds.add('${title}_$i');
      }
    }
    _preloadAdjacent?.call(indices, title, episodeUrls);
  }

  @override
  void cancelPreloads() {
    // 标记未使用的预加载为非活跃，让缓存服务自身的淘汰策略回收
    final unusedIds = List<String>.from(_preloadedVideoIds);
    _preloadedVideoIds.clear();

    for (final videoId in unusedIds) {
      try {
        VideoCacheService.instance.markVideoInactive(videoId);
        _logger.d('标记未使用预加载为非活跃: $videoId');
      } catch (e) {
        _logger.w('标记预加载非活跃失败: $videoId, 错误: $e');
      }
    }

    // 清空回调引用，阻止后续预加载触发
    _preloadNextEpisode = null;
    _preloadAdjacent = null;
    _logger.i('已取消所有预加载并回收资源（${unusedIds.length} 项）');
  }

  @override
  void dispose() {
    cancelPreloads();
    _notifyPreloadBuffering = null;
  }
}
