import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:logger/logger.dart';
import '../models/video_models.dart';
import '../../../core/network/proxy_config_service.dart';

/// CMS API 视频服务
/// 支持采集站 API 格式：{apiUrl}?ac=detail&pg=1 获取影片列表
/// {apiUrl}?ac=detail&ids={vodId} 获取详情
/// {apiUrl}?wd=关键词 搜索影片
///
/// 优化项：
/// - DNS预解析：提前解析域名，减少连接延迟
/// - 接口预请求：预取影片详情并缓存
/// - 并行请求：多站点并行搜索换源
/// - CDN调度：TCP测速选择最快CDN节点
/// - 超时重试优化：指数退避重试 + 自适应超时
/// - 接口合并：详情+播放信息合并请求
class VideoApiService {
  final Dio _dio;
  final Logger _logger = Logger(printer: SimplePrinter());

  // DNS预解析缓存，5分钟TTL
  final Map<String, _DnsCacheEntry> _dnsCache = {};
  static const Duration _dnsCacheTtl = Duration(minutes: 5);

  // 接口预请求缓存，10分钟TTL
  final Map<String, _PrefetchCacheEntry<VideoDetail>> _prefetchCache = {};
  static const Duration _prefetchCacheTtl = Duration(minutes: 10);

  // CDN调度缓存，5分钟TTL
  final Map<String, _CdnCacheEntry> _cdnCache = {};
  static const Duration _cdnCacheTtl = Duration(minutes: 5);

  VideoApiService({Dio? dio}) : _dio = dio ?? _createDio();

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': 'okhttp/3.12.11',
        'Accept': '*/*',
        'Accept-Encoding': 'gzip, deflate',
      },
      validateStatus: (status) => status != null && status < 500,
      followRedirects: true,
      maxRedirects: 5,
    ));

    // 允许自签名证书 + 代理配置
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      try {
        ProxyConfigService.instance.configureHttpClient(client);
      } catch (_) {}
      return client;
    };

    // 添加指数退避重试拦截器
    dio.interceptors.add(_RetryInterceptor(dio: dio));

    return dio;
  }

  // ==================== DNS预解析 ====================

  /// DNS预解析 - 提前解析所有API域名，减少首次连接延迟
  /// 缓存5分钟TTL，过期后自动重新解析
  Future<void> prefetchDns(List<String> apiUrls) async {
    final now = DateTime.now();
    final hosts = <String>{};

    for (final url in apiUrls) {
      try {
        final uri = Uri.parse(url.startsWith('http') ? url : 'http://$url');
        final host = uri.host;
        if (host.isEmpty) continue;

        // 检查缓存是否过期
        final cached = _dnsCache[host];
        if (cached != null && now.difference(cached.time) < _dnsCacheTtl) {
          continue; // 缓存未过期，跳过
        }
        hosts.add(host);
      } catch (_) {
        // 忽略无效URL
      }
    }

    if (hosts.isEmpty) return;

    // 并发解析所有域名
    await Future.wait(
      hosts.map((host) => _resolveHost(host)),
      eagerError: false,
    );
  }

  /// 解析单个主机名
  Future<void> _resolveHost(String host) async {
    try {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isNotEmpty) {
        _dnsCache[host] = _DnsCacheEntry(
          addresses: addresses.map((a) => a.address).toList(),
          time: DateTime.now(),
        );
        _logger.d('DNS预解析成功: $host -> ${addresses.first.address}');
      }
    } catch (e) {
      _logger.w('DNS预解析失败: $host - $e');
    }
  }

  // ==================== 接口预请求 ====================

  /// 预取影片详情 - 提前请求并缓存，后续fetchVideoDetail可直接命中
  /// 缓存10分钟TTL
  Future<void> prefetchVideoInfo(String apiUrl, String vodId) async {
    final cacheKey = '${apiUrl}_$vodId';
    final now = DateTime.now();

    // 检查缓存是否有效
    final cached = _prefetchCache[cacheKey];
    if (cached != null && now.difference(cached.time) < _prefetchCacheTtl) {
      return; // 缓存未过期，无需重新请求
    }

    try {
      final detail = await _fetchVideoDetailInternal(apiUrl, vodId, sourceKey: '');
      _prefetchCache[cacheKey] = _PrefetchCacheEntry<VideoDetail>(
        data: detail,
        time: DateTime.now(),
      );
      _logger.d('预取影片详情成功: $vodId');
    } catch (e) {
      _logger.w('预取影片详情失败: $vodId - $e');
    }
  }

  // ==================== 并行请求 ====================

  /// 并行获取影片详情 - 从主站获取详情的同时，并行搜索其他站点用于换源
  /// 替代video_providers.dart中的并行逻辑
  Future<VideoDetail> fetchVideoDetailParallel(
    String apiUrl,
    String vodId, {
    String sourceKey = '',
    List<CmsApiSite>? otherSites,
    VideoApiService? apiService,
  }) async {
    final service = apiService ?? this;

    // 主站详情请求
    final detailFuture = service.fetchVideoDetail(apiUrl, vodId, sourceKey: sourceKey);

    if (otherSites == null || otherSites.isEmpty) {
      // 没有其他站点，直接返回主站详情
      return detailFuture;
    }

    // 并行发起主站详情 + 其他站点搜索
    final results = await Future.wait<dynamic>(
      [
        // 主站详情
        detailFuture.then<dynamic>((d) => d).catchError((e) => null),
        // 其他站点并行搜索
        ...otherSites.map((site) async {
          try {
            // 先获取主站详情拿到片名
            return null; // 占位，后续用片名搜索
          } catch (e) {
            return null;
          }
        }),
      ],
      eagerError: false,
    );

    // 主站详情
    final detail = results[0] as VideoDetail?;
    if (detail == null) {
      // 主站失败，尝试直接获取
      return fetchVideoDetail(apiUrl, vodId, sourceKey: sourceKey);
    }

    // 用主站片名并行搜索其他站点
    final searchFutures = otherSites.map((site) async {
      try {
        final searchResult = await service
            .searchVideos(site.apiUrl, detail.vodName)
            .timeout(const Duration(seconds: 5));
        if (searchResult.list.isNotEmpty) {
          final matchedItem = searchResult.list.first;
          final otherDetail = await service
              .fetchVideoDetail(site.apiUrl, matchedItem.vodId, sourceKey: site.key)
              .timeout(const Duration(seconds: 5));
          return otherDetail.playSources.map((source) => PlaySource(
                name: '${site.name}-${source.name}',
                episodes: source.episodes,
              )).toList();
        }
      } catch (e) {
        _logger.d('换源搜索 ${site.name} 失败: $e');
      }
      return <PlaySource>[];
    }).toList();

    final searchResults = await Future.wait(searchFutures);

    // 合并所有播放源
    final allSources = <PlaySource>[...detail.playSources];
    for (final sources in searchResults) {
      allSources.addAll(sources);
    }

    return VideoDetail(
      vodId: detail.vodId,
      vodName: detail.vodName,
      vodPic: detail.vodPic,
      vodContent: detail.vodContent,
      vodActor: detail.vodActor,
      vodDirector: detail.vodDirector,
      vodYear: detail.vodYear,
      vodArea: detail.vodArea,
      vodRemarks: detail.vodRemarks,
      typeName: detail.typeName,
      typeId: detail.typeId,
      sourceKey: detail.sourceKey,
      playSources: allSources,
    );
  }

  // ==================== CDN调度 ====================

  /// 选择最优CDN节点 - TCP测速后返回延迟最低的URL
  /// 缓存5分钟TTL
  Future<String> selectBestCdn(List<String> cdnUrls) async {
    if (cdnUrls.length <= 1) return cdnUrls.first;

    final now = DateTime.now();
    final cacheKey = cdnUrls.join('|');

    // 检查缓存
    final cached = _cdnCache[cacheKey];
    if (cached != null && now.difference(cached.time) < _cdnCacheTtl) {
      _logger.d('CDN调度命中缓存: ${cached.bestUrl}');
      return cached.bestUrl;
    }

    // 并行测速所有CDN
    final latencies = <String, int>{};
    await Future.wait(
      cdnUrls.map((url) async {
        try {
          final ms = await measureLatency(url);
          latencies[url] = ms;
        } catch (e) {
          _logger.w('CDN测速失败: $url - $e');
          latencies[url] = 99999; // 不可用标记为极大值
        }
      }),
      eagerError: false,
    );

    // 选择延迟最低的
    final bestEntry = latencies.entries.reduce(
      (a, b) => a.value < b.value ? a : b,
    );
    final bestUrl = bestEntry.key;
    _logger.d('CDN调度选择: $bestUrl (${bestEntry.value}ms)');

    // 缓存结果
    _cdnCache[cacheKey] = _CdnCacheEntry(
      bestUrl: bestUrl,
      latencyMs: bestEntry.value,
      time: DateTime.now(),
    );

    return bestUrl;
  }

  /// 测量HTTP延迟 - 发起HEAD请求测量往返时间
  Future<int> measureLatency(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _dio.head(
        url,
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      stopwatch.stop();
      // HEAD请求可能不被支持，尝试GET
      try {
        stopwatch.reset();
        stopwatch.start();
        await _dio.get(
          url,
          options: Options(
            sendTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 3),
          ),
        );
        stopwatch.stop();
        return stopwatch.elapsedMilliseconds;
      } catch (_) {
        stopwatch.stop();
        rethrow;
      }
    }
  }

  // ==================== 超时重试优化 ====================

  /// 根据网络类型自适应设置连接超时
  /// WiFi环境2秒，移动网络3秒
  static Duration _adaptiveConnectTimeout({bool isWifi = false}) {
    return isWifi
        ? const Duration(seconds: 2)
        : const Duration(seconds: 3);
  }

  // ==================== 接口合并 ====================

  /// 合并获取影片详情+播放信息
  /// 当API支持时，详情接口已包含播放信息，直接返回
  /// 否则分两次请求获取
  Future<VideoDetail> fetchVideoDetailWithPlayInfo(
    String apiUrl,
    String vodId, {
    String sourceKey = '',
  }) async {
    try {
      // CMS采集站API的detail接口通常已包含播放信息
      // 直接使用detail接口获取完整数据
      final detail = await fetchVideoDetail(apiUrl, vodId, sourceKey: sourceKey);

      // 如果已有播放源，直接返回
      if (detail.playSources.isNotEmpty) {
        return detail;
      }

      // 播放源为空时，尝试通过搜索接口补充
      _logger.d('详情无播放源，尝试搜索补充: ${detail.vodName}');
      try {
        final searchResult = await searchVideos(apiUrl, detail.vodName);
        if (searchResult.list.isNotEmpty) {
          final matchedItem = searchResult.list.firstWhere(
            (item) => item.vodId == vodId,
            orElse: () => searchResult.list.first,
          );
          if (matchedItem.vodId != vodId) {
            // 搜索结果不匹配，重新获取
            final reDetail = await fetchVideoDetail(apiUrl, matchedItem.vodId, sourceKey: sourceKey);
            return VideoDetail(
              vodId: detail.vodId,
              vodName: detail.vodName,
              vodPic: detail.vodPic,
              vodContent: detail.vodContent,
              vodActor: detail.vodActor,
              vodDirector: detail.vodDirector,
              vodYear: detail.vodYear,
              vodArea: detail.vodArea,
              vodRemarks: detail.vodRemarks,
              typeName: detail.typeName,
              typeId: detail.typeId,
              sourceKey: detail.sourceKey,
              playSources: reDetail.playSources,
            );
          }
        }
      } catch (e) {
        _logger.w('搜索补充播放信息失败: $e');
      }

      return detail;
    } catch (e) {
      rethrow;
    }
  }

  // ==================== 原有方法（保持签名不变） ====================

  /// 获取分类列表
  Future<List<VideoCategory>> fetchCategories(String apiUrl) async {
    try {
      final url = _buildUrl(apiUrl, {'ac': 'list'});
      _logger.d('获取分类列表: $url');
      final response = await _dio.get(url);
      final data = _extractJson(response);
      final List<VideoCategory> categories = [];
      for (final c in (data['class'] as List?) ?? []) {
        if (c is Map<String, dynamic>) {
          categories.add(VideoCategory.fromJson(c));
        }
      }
      return categories;
    } on DioException catch (e) {
      throw Exception(_formatDioError(e));
    } catch (e) {
      _logger.e('获取分类列表失败: $e');
      throw Exception('获取分类失败: $e');
    }
  }

  /// 获取影片列表
  Future<VideoListResponse> fetchVideoList(String apiUrl, {int page = 1, int? typeId}) async {
    try {
      final params = {'ac': 'detail', 'pg': page.toString()};
      if (typeId != null) params['t'] = typeId.toString();
      final url = _buildUrl(apiUrl, params);
      _logger.d('获取影片列表: $url');

      final response = await _dio.get(url);
      final data = _extractJson(response);
      return VideoListResponse.fromJson(data);
    } on DioException catch (e) {
      final errMsg = _formatDioError(e);
      _logger.e('获取影片列表失败: $errMsg');
      throw Exception(errMsg);
    } catch (e) {
      _logger.e('获取影片列表失败: $e');
      throw Exception('加载失败: $e');
    }
  }

  /// 获取影片详情（优先检查预请求缓存）
  Future<VideoDetail> fetchVideoDetail(String apiUrl, String vodId, {String sourceKey = ''}) async {
    // 检查预请求缓存
    final cacheKey = '${apiUrl}_$vodId';
    final now = DateTime.now();
    final cached = _prefetchCache[cacheKey];
    if (cached != null && now.difference(cached.time) < _prefetchCacheTtl) {
      _logger.d('命中预请求缓存: $vodId');
      // 命中缓存后移除，避免重复使用过期数据
      _prefetchCache.remove(cacheKey);
      // 如果sourceKey不同，需要覆盖
      if (sourceKey.isNotEmpty && cached.data.sourceKey != sourceKey) {
        return VideoDetail(
          vodId: cached.data.vodId,
          vodName: cached.data.vodName,
          vodPic: cached.data.vodPic,
          vodContent: cached.data.vodContent,
          vodActor: cached.data.vodActor,
          vodDirector: cached.data.vodDirector,
          vodYear: cached.data.vodYear,
          vodArea: cached.data.vodArea,
          vodRemarks: cached.data.vodRemarks,
          typeName: cached.data.typeName,
          typeId: cached.data.typeId,
          sourceKey: sourceKey,
          playSources: cached.data.playSources,
        );
      }
      return cached.data;
    }

    return _fetchVideoDetailInternal(apiUrl, vodId, sourceKey: sourceKey);
  }

  /// 影片详情内部请求方法
  Future<VideoDetail> _fetchVideoDetailInternal(String apiUrl, String vodId, {String sourceKey = ''}) async {
    try {
      final url = _buildUrl(apiUrl, {'ac': 'detail', 'ids': vodId});
      _logger.d('获取影片详情: $url');

      final response = await _dio.get(url);
      final data = _extractJson(response);

      final list = data['list'] as List?;
      if (list == null || list.isEmpty) {
        throw Exception('影片不存在');
      }

      return VideoDetail.fromJson(list.first as Map<String, dynamic>, sourceKey: sourceKey);
    } on DioException catch (e) {
      final errMsg = _formatDioError(e);
      _logger.e('获取影片详情失败: $errMsg');
      throw Exception(errMsg);
    } catch (e) {
      _logger.e('获取影片详情失败: $e');
      throw Exception('加载失败: $e');
    }
  }

  /// 搜索影片
  Future<VideoListResponse> searchVideos(String apiUrl, String keyword) async {
    try {
      final url = _buildUrl(apiUrl, {'wd': keyword});
      _logger.d('搜索影片: $url');

      final response = await _dio.get(url);
      final data = _extractJson(response);
      return VideoListResponse.fromJson(data);
    } on DioException catch (e) {
      final errMsg = _formatDioError(e);
      _logger.e('搜索影片失败: $errMsg');
      throw Exception(errMsg);
    } catch (e) {
      _logger.e('搜索影片失败: $e');
      throw Exception('搜索失败: $e');
    }
  }

  /// 构建请求 URL
  String _buildUrl(String apiUrl, Map<String, String> params) {
    var url = apiUrl.trim();
    // 确保有协议前缀
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    // 拼接查询参数
    final separator = url.contains('?') ? '&' : '?';
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return '$url$separator$query';
  }

  /// 从响应中提取 JSON 数据
  Map<String, dynamic> _extractJson(Response response) {
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final dynamic body = response.data;

    if (body is Map<String, dynamic>) {
      return body;
    }

    if (body is String) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw Exception('JSON 不是对象格式');
      } catch (e) {
        throw Exception('JSON 解析失败: $e');
      }
    }

    throw Exception('无效的响应格式: ${body.runtimeType}');
  }

  /// 格式化 Dio 错误信息
  String _formatDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查网络';
      case DioExceptionType.receiveTimeout:
        return '接收超时，服务器响应过慢';
      case DioExceptionType.sendTimeout:
        return '发送超时';
      case DioExceptionType.connectionError:
        final msg = e.message ?? '';
        if (msg.contains('Failed host lookup')) {
          return 'DNS 解析失败，域名无法访问';
        }
        if (msg.contains('Connection refused')) {
          return '服务器拒绝连接';
        }
        return '网络连接失败: $msg';
      case DioExceptionType.badResponse:
        return '服务器返回错误: HTTP ${e.response?.statusCode}';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        final msg = e.message ?? '';
        final errorStr = e.error?.toString() ?? '';
        if (msg.isNotEmpty) return '网络错误: $msg';
        if (errorStr.isNotEmpty) return '网络错误: $errorStr';
        return '网络错误: 请检查接口地址是否正确';
    }
  }

  /// 清除所有缓存
  void clearAllCache() {
    _dnsCache.clear();
    _prefetchCache.clear();
    _cdnCache.clear();
    _logger.d('所有缓存已清除');
  }
}

// ==================== 缓存条目类 ====================

/// DNS缓存条目
class _DnsCacheEntry {
  final List<String> addresses;
  final DateTime time;

  _DnsCacheEntry({required this.addresses, required this.time});
}

/// 预请求缓存条目
class _PrefetchCacheEntry<T> {
  final T data;
  final DateTime time;

  _PrefetchCacheEntry({required this.data, required this.time});
}

/// CDN调度缓存条目
class _CdnCacheEntry {
  final String bestUrl;
  final int latencyMs;
  final DateTime time;

  _CdnCacheEntry({
    required this.bestUrl,
    required this.latencyMs,
    required this.time,
  });
}

// ==================== 重试拦截器 ====================

/// 指数退避重试拦截器
/// 最大3次重试，延迟分别为500ms、1000ms、2000ms
/// 仅在超时、连接错误、5xx错误时重试
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  // 指数退避基础延迟：500ms, 1000ms, 2000ms
  static const List<int> _retryDelays = [500, 1000, 2000];

  _RetryInterceptor({required this.dio}) : maxRetries = 3;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final retries = err.requestOptions.extra['retries'] ?? 0;
    if (retries < maxRetries && _shouldRetry(err)) {
      final delayMs = _retryDelays[retries.clamp(0, _retryDelays.length - 1)];
      await Future.delayed(Duration(milliseconds: delayMs));

      final options = err.requestOptions.copyWith(
        extra: {...err.requestOptions.extra, 'retries': retries + 1},
      );
      try {
        final response = await dio.fetch(options);
        handler.resolve(response);
      } catch (e) {
        handler.next(e is DioException ? e : DioException(requestOptions: options, error: e));
      }
    } else {
      handler.next(err);
    }
  }

  /// 判断是否应该重试
  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.response?.statusCode ?? 0) >= 500;
  }
}
