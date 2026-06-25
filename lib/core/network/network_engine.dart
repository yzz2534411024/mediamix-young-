import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'proxy_config_service.dart';
import 'package:logger/logger.dart';

// ==================== 带宽估算器 ====================

/// 带宽估算器 - 使用 EWMA 算法平滑带宽估算
class BandwidthEstimator {
  // EWMA 平滑因子，越大越偏向新样本
  static const double _alpha = 0.7;

  // 当前估算带宽（Kbps）
  double _estimatedBandwidthKbps = 0;

  // 是否已有初始估算
  bool _initialized = false;

  // 峰值带宽（Kbps）
  double _peak = 0.0;

  // 滑动窗口采样历史
  final List<double> _samples = [];
  static const int _windowSize = 20;

  // 每个连接的慢启动样本计数（前3个样本过滤）
  final Map<String, int> _slowStartCount = {};
  static const int _maxSlowStartEntries = 200;

  // 用于 LRU 淘汰的键插入顺序列表
  final List<String> _slowStartOrder = [];

  // 带宽变化通知流控制器
  final _bandwidthController = StreamController<double>.broadcast();

  /// 当前估算带宽（Kbps）
  double get currentBandwidthKbps => _estimatedBandwidthKbps;

  /// 峰值带宽（Kbps）
  double get peak => _peak;

  /// 带宽变化通知流
  Stream<double> get onBandwidthChanged => _bandwidthController.stream;

  /// 记录一次下载并更新带宽估算（带连接键，用于多 CDN 场景）
  void recordSample({
    required String connectionKey,
    required int bytes,
    required Duration duration,
  }) {
    if (duration.inMilliseconds <= 0 || bytes <= 0) return;

    // 过滤慢启动样本（每个连接前3个样本）
    if (!_slowStartCount.containsKey(connectionKey)) {
      _slowStartOrder.add(connectionKey);
      if (_slowStartOrder.length > _maxSlowStartEntries) {
        final oldest = _slowStartOrder.removeAt(0);
        _slowStartCount.remove(oldest);
      }
    }
    _slowStartCount[connectionKey] = (_slowStartCount[connectionKey] ?? 0) + 1;
    if (_slowStartCount[connectionKey]! <= 3) return;

    final kbps = (bytes * 8) / (duration.inMilliseconds / 1000) / 1000;
    _applySample(kbps);
  }

  /// 记录一次下载（简化版，无需连接键）
  void addSample(int bytesDownloaded, int durationMs) {
    if (durationMs <= 0 || bytesDownloaded <= 0) return;
    final kbps = (bytesDownloaded * 8.0) / (durationMs / 1000.0) / 1000.0;
    _applySample(kbps);
  }

  void _applySample(double kbps) {
    // 维护滑动窗口
    _samples.add(kbps);
    if (_samples.length > _windowSize) {
      _samples.removeAt(0);
    }

    if (!_initialized) {
      _estimatedBandwidthKbps = kbps;
      _initialized = true;
    } else {
      _estimatedBandwidthKbps =
          _alpha * kbps + (1 - _alpha) * _estimatedBandwidthKbps;
    }

    // 更新峰值
    if (_estimatedBandwidthKbps > _peak) {
      _peak = _estimatedBandwidthKbps;
    }

    _bandwidthController.add(_estimatedBandwidthKbps);
  }

  /// 返回当前带宽估算值（Kbps）
  double estimateBandwidth() => _estimatedBandwidthKbps;

  /// 获取滑动窗口内采样数
  int sampleCount() => _samples.length;

  /// 获取滑动窗口内的平均带宽（Kbps）
  double windowAverage() {
    if (_samples.isEmpty) return 0.0;
    return _samples.reduce((a, b) => a + b) / _samples.length;
  }

  /// 重置估算器状态
  void reset() {
    _estimatedBandwidthKbps = 0;
    _peak = 0.0;
    _initialized = false;
    _samples.clear();
    _slowStartCount.clear();
    _slowStartOrder.clear();
  }

  /// 释放资源
  void dispose() {
    _bandwidthController.close();
  }
}

// ==================== 网络状态感知 ====================

/// 网络条件枚举
enum NetworkCondition {
  wifi,   // WiFi: > 5Mbps
  lte,    // 4G: 1-5Mbps
  threeG, // 3G: 0.3-1Mbps
  weak,   // 弱网: < 0.3Mbps
  offline // 离线: 0
}

/// 网络状态感知 - 根据带宽判断网络条件
class NetworkConditionDetector {
  final BandwidthEstimator _estimator;

  // 网络条件变化流控制器
  final _conditionController = StreamController<NetworkCondition>.broadcast();

  // 上次网络条件（用于检测变化）
  NetworkCondition _lastCondition = NetworkCondition.offline;

  NetworkConditionDetector(this._estimator) {
    // 监听带宽变化，更新网络条件
    _estimator.onBandwidthChanged.listen(_onBandwidthChanged);
  }

  /// 当前网络条件
  NetworkCondition get currentCondition {
    return _conditionFromBandwidth(_estimator.currentBandwidthKbps);
  }

  /// 网络条件变化流
  Stream<NetworkCondition> get onConditionChanged => _conditionController.stream;

  /// 根据带宽映射网络条件
  NetworkCondition _conditionFromBandwidth(double kbps) {
    if (kbps <= 0) return NetworkCondition.offline;
    if (kbps < 300) return NetworkCondition.weak;      // < 0.3Mbps
    if (kbps < 1000) return NetworkCondition.threeG;   // 0.3-1Mbps
    if (kbps < 5000) return NetworkCondition.lte;      // 1-5Mbps
    return NetworkCondition.wifi;                       // > 5Mbps
  }

  /// 带宽变化回调
  void _onBandwidthChanged(double kbps) {
    final newCondition = _conditionFromBandwidth(kbps);
    if (newCondition != _lastCondition) {
      _lastCondition = newCondition;
      _conditionController.add(newCondition);
    }
  }

  /// 释放资源
  void dispose() {
    _conditionController.close();
  }
}

// ==================== 缓存统计 ====================

/// 缓存统计数据
class CacheStats {
  final int hitCount;
  final int missCount;

  const CacheStats({this.hitCount = 0, this.missCount = 0});

  /// 缓存命中率（0.0 - 1.0）
  double get hitRate {
    final total = hitCount + missCount;
    return total == 0 ? 0.0 : hitCount / total;
  }

  @override
  String toString() =>
      'CacheStats(hit: $hitCount, miss: $missCount, rate: ${(hitRate * 100).toStringAsFixed(1)}%)';
}

// ==================== 请求优先级 ====================

/// 请求优先级常量
class RequestPriority {
  static const int low = 0;
  static const int normal = 1;
  static const int high = 2;
  static const int critical = 3;
}

// ==================== 高性能网络引擎 ====================

/// 高性能网络引擎 - 支持并发、缓存、重试、DNS预解析、带宽估算、请求优先级
class NetworkEngine {
  static NetworkEngine? _instance;
  late final Dio _dio;
  final Logger _logger = Logger(printer: SimplePrinter());

  // DNS 预解析缓存
  final _dnsCache = <String, DateTime>{};
  static const _dnsCacheTtl = Duration(minutes: 10);

  // CDN 调度缓存
  final _cdnCache = <String, _CdnCacheEntry>{};

  /// DNS 服务器列表
  static const List<String> _dnsServers = [
    'system',        // 系统 DNS
    '114.114.114.114', // 114 DNS
    '8.8.8.8',       // Google DNS
  ];

  // 带宽估算器
  final BandwidthEstimator _bandwidthEstimator = BandwidthEstimator();

  // 网络条件检测器
  late final NetworkConditionDetector _conditionDetector;

  // 缓存拦截器引用（用于获取缓存统计）
  late final _EnhancedCacheInterceptor _cacheInterceptor;

  NetworkEngine._() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 10),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
      },
    ));

    // 启用 HTTP/2、连接池优化 和 代理支持
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.maxConnectionsPerHost = 8;
      client.idleTimeout = const Duration(seconds: 30);

      // 代理配置
      try {
        ProxyConfigService.instance.configureHttpClient(client);
      } catch (_) {}

      return client;
    };

    // 创建缓存拦截器实例
    _cacheInterceptor = _EnhancedCacheInterceptor();

    // 添加拦截器：优先级 + 重试 + 缓存 + 带宽估算 + 日志
    _dio.interceptors.addAll([
      _PriorityInterceptor(),
      _RetryInterceptor(dio: _dio, maxRetries: 3),
      _cacheInterceptor,
      _BandwidthInterceptor(_bandwidthEstimator),
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (o) => _logger.d(o),
      ),
    ]);

    // 初始化网络条件检测器
    _conditionDetector = NetworkConditionDetector(_bandwidthEstimator);
  }

  static NetworkEngine get instance => _instance ??= NetworkEngine._();

  Dio get dio => _dio;

  // ---- 带宽估算相关 ----

  /// 当前估算带宽（Kbps）
  double get currentBandwidthKbps => _bandwidthEstimator.currentBandwidthKbps;

  /// 峰值带宽（Kbps）
  double get peakBandwidthKbps => _bandwidthEstimator.peak;

  /// 供外部组件（如本地代理）上报带宽样本
  void reportBandwidthSample(int bytesDownloaded, int durationMs) {
    _bandwidthEstimator.addSample(bytesDownloaded, durationMs);
  }

  /// 获取带宽估算值
  double estimateBandwidth() => _bandwidthEstimator.estimateBandwidth();

  /// 带宽变化通知流
  Stream<double> get onBandwidthChanged =>
      _bandwidthEstimator.onBandwidthChanged;

  // ---- 网络条件感知 ----

  /// 当前网络条件
  NetworkCondition get currentCondition => _conditionDetector.currentCondition;

  /// 网络条件变化流
  Stream<NetworkCondition> get onConditionChanged =>
      _conditionDetector.onConditionChanged;

  // ---- 缓存统计 ----

  /// 缓存统计数据
  CacheStats get cacheStats => _cacheInterceptor.stats;

  /// DNS 预解析 - 提前解析域名，减少连接延迟
  Future<void> preResolveDns(List<String> urls) async {
    final now = DateTime.now();
    final hosts = <String>{};

    for (final url in urls) {
      try {
        final uri = Uri.parse(url);
        final host = uri.host;
        if (host.isEmpty) continue;

        final cached = _dnsCache[host];
        if (cached != null && now.difference(cached) < _dnsCacheTtl) {
          continue; // DNS 缓存未过期，跳过
        }
        hosts.add(host);
      } catch (_) {
        // 忽略无效 URL
      }
    }

    // 并发解析所有域名
    await Future.wait(
      hosts.map((host) => _resolveHost(host)),
      eagerError: false,
    );
  }

  Future<void> _resolveHost(String host) async {
    // 跳过 localhost / IP 地址
    if (host == 'localhost' || host == '127.0.0.1' ||
        RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) {
      return;
    }

    try {
      final addresses = await _resolveWithFallback(host);
      if (addresses.isNotEmpty) {
        _dnsCache[host] = DateTime.now();
        _logger.d('DNS 预解析成功: $host -> ${addresses.first.address}');
      }
    } catch (e) {
      _logger.w('DNS 预解析失败: $host');
    }
  }

  /// 使用指定 DNS 服务器解析域名
  /// 对于系统 DNS，使用 Dart 的 InternetAddress.lookup
  /// 对于第三方 DNS，使用 HTTP DNS-over-HTTPS (DoH) 查询
  Future<List<InternetAddress>> _resolveWithDns(String host, String dnsServer) async {
    if (dnsServer == 'system') {
      return await InternetAddress.lookup(host);
    }
    // DoH 查询
    final dohUrl = dnsServer == '114.114.114.114'
        ? 'https://dns.114dns.com/resolve?name=$host&type=A'
        : 'https://dns.google/resolve?name=$host&type=A';

    final response = await _dio.get(dohUrl, options: Options(connectTimeout: const Duration(seconds: 2)));
    final data = response.data as Map<String, dynamic>;
    final answers = data['Answer'] as List<dynamic>?;
    if (answers == null || answers.isEmpty) {
      throw Exception('DNS 查询无结果');
    }

    return answers
        .where((a) => a['type'] == 1) // A record
        .map((a) => InternetAddress(a['data'] as String))
        .toList();
  }

  /// DNS 预解析带多服务器轮询
  Future<List<InternetAddress>> _resolveWithFallback(String host) async {
    for (final dns in _dnsServers) {
      try {
        final result = await _resolveWithDns(host, dns);
        if (result.isNotEmpty) return result;
      } catch (e) {
        _logger.d('DNS $dns 解析 $host 失败: $e，尝试下一个');
        continue;
      }
    }
    // 所有 DNS 都失败，回退到系统 DNS
    return await InternetAddress.lookup(host);
  }

  /// 并发请求 - 核心优化：多源同时加载
  /// [maxConcurrent] 默认 32，适合直播源并发加载
  Future<List<Response>> concurrentGet(
    List<String> urls, {
    int maxConcurrent = 32,
    Map<String, String>? headers,
    Duration? timeout,
    void Function(int completed, int total)? onProgress,
  }) async {
    // 先进行 DNS 预解析
    await preResolveDns(urls);

    final results = <Response>[];
    final semaphore = Semaphore(maxConcurrent);
    var completed = 0;

    final futures = urls.map((url) async {
      await semaphore.acquire();
      try {
        final response = await _dio.get(
          url,
          options: Options(
            headers: headers,
            receiveTimeout: timeout,
          ),
        );
        results.add(response);
        completed++;
        onProgress?.call(completed, urls.length);
        return response;
      } catch (e) {
        _logger.w('请求失败: $url, 错误: $e');
        completed++;
        onProgress?.call(completed, urls.length);
        return null;
      } finally {
        semaphore.release();
      }
    }).toList();

    await Future.wait(futures, eagerError: false);
    return results.whereType<Response>().toList();
  }

  /// 带缓存的 GET 请求
  /// [cacheTime] 默认 30 分钟（直播源缓存）
  Future<Response> cachedGet(
    String url, {
    Map<String, String>? headers,
    Duration? cacheTime,
    String? charset,
    Duration? timeout,
  }) async {
    return _dio.get(
      url,
      options: Options(
        headers: headers,
        receiveTimeout: timeout,
        extra: {
          'cacheTime': cacheTime?.inSeconds ?? 1800, // 默认缓存30分钟
          'charset': charset,
        },
      ),
    );
  }

  /// 快速 GET 请求 - 用于需要快速响应的场景（如 EPG）
  Future<Response> quickGet(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return _dio.get(
      url,
      options: Options(
        headers: headers,
        receiveTimeout: timeout,
        extra: {'cacheTime': 300}, // 快速缓存5分钟
      ),
    );
  }

  /// POST 请求
  Future<Response> post(
    String url, {
    dynamic data,
    Map<String, String>? headers,
  }) async {
    return _dio.post(
      url,
      data: data,
      options: Options(headers: headers),
    );
  }

  /// 清除 DNS 缓存
  void clearDnsCache() {
    _dnsCache.clear();
    _logger.d('DNS 缓存已清除');
  }

  /// 并行 TCP 测速选择最优 CDN 节点
  ///
  /// 同时向所有 CDN 节点发起 HEAD 请求，选择延迟最低的节点
  /// [cdnUrls] CDN 节点 URL 列表
  /// [timeout] 单个节点测速超时时间，默认 3 秒
  /// [cacheTtl] 测速结果缓存时间，默认 5 分钟
  Future<String> selectBestCdn(
    List<String> cdnUrls, {
    Duration timeout = const Duration(seconds: 3),
    Duration cacheTtl = const Duration(minutes: 5),
  }) async {
    if (cdnUrls.length <= 1) return cdnUrls.first;

    // 检查 CDN 调度缓存
    final cacheKey = cdnUrls.join('|');
    final cached = _cdnCache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.time) < cacheTtl) {
      _logger.d('CDN调度缓存命中: ${cached.bestUrl}');
      return cached.bestUrl;
    }

    // 并行测速所有 CDN 节点
    final latencies = <String, int>{};
    await Future.wait(
      cdnUrls.map((url) async {
        final stopwatch = Stopwatch()..start();
        try {
          await _dio.head(
            url,
            options: Options(
              sendTimeout: timeout,
              receiveTimeout: timeout,
              connectTimeout: timeout,
            ),
          );
          stopwatch.stop();
          latencies[url] = stopwatch.elapsedMilliseconds;
        } catch (e) {
          stopwatch.stop();
          // HEAD 失败尝试 GET（部分服务器不支持 HEAD）
          stopwatch.reset();
          stopwatch.start();
          try {
            await _dio.get(
              url,
              options: Options(
                sendTimeout: timeout,
                receiveTimeout: timeout,
                connectTimeout: timeout,
              ),
            );
            stopwatch.stop();
            latencies[url] = stopwatch.elapsedMilliseconds;
          } catch (_) {
            stopwatch.stop();
            _logger.w('CDN测速失败: $url - $e');
            latencies[url] = 99999; // 不可达标记
          }
        }
      }),
      eagerError: false,
    );

    // 选择延迟最低的节点
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

  /// 清除 CDN 调度缓存
  void clearCdnCache() {
    _cdnCache.clear();
    _logger.d('CDN 调度缓存已清除');
  }

  /// 清除请求缓存
  void clearRequestCache() {
    _cacheInterceptor.clearCache();
    _logger.d('请求缓存已清除');
  }
}

// ==================== 信号量 ====================

/// 信号量 - 控制并发数
class Semaphore {
  int _count;
  final List<Completer<void>> _waiters = [];

  Semaphore(int max) : _count = max;

  Future<void> acquire() async {
    if (_count > 0) {
      _count--;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final waiter = _waiters.removeAt(0);
      waiter.complete();
    } else {
      _count++;
    }
  }
}

// ==================== 优先级拦截器 ====================

/// 请求优先级拦截器 - 根据优先级调整超时和重试策略
class _PriorityInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final priority = options.extra['priority'] as int? ?? RequestPriority.normal;

    switch (priority) {
      case RequestPriority.high:
        // 高优先级：更短超时，更快失败
        options.connectTimeout = const Duration(seconds: 5);
        options.receiveTimeout = const Duration(seconds: 15);
        options.sendTimeout = const Duration(seconds: 5);
        // 高优先级允许更多重试
        options.extra = {...options.extra, 'maxRetries': 5};
        break;
      case RequestPriority.critical:
        // 关键请求：绕过缓存，直接走网络
        options.extra = {...options.extra, 'cacheTime': 0, 'maxRetries': 5};
        options.connectTimeout = const Duration(seconds: 5);
        options.receiveTimeout = const Duration(seconds: 10);
        options.sendTimeout = const Duration(seconds: 5);
        break;
      case RequestPriority.low:
        // 低优先级：更长超时容忍
        options.connectTimeout = const Duration(seconds: 15);
        options.receiveTimeout = const Duration(seconds: 60);
        options.extra = {...options.extra, 'maxRetries': 1};
        break;
      default:
        // 普通优先级：使用默认配置
        break;
    }

    handler.next(options);
  }
}

// ==================== 重试拦截器 ====================

/// 重试拦截器 - 指数退避，支持优先级感知
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  _RetryInterceptor({required this.dio, this.maxRetries = 3});

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // 优先级感知：高优先级请求允许更多重试
    final priorityMaxRetries =
        err.requestOptions.extra['maxRetries'] as int? ?? maxRetries;
    final retries = err.requestOptions.extra['retries'] ?? 0;
    if (retries < priorityMaxRetries && _shouldRetry(err)) {
      final delay = Duration(milliseconds: 500 * (1 << retries)); // 指数退避
      await Future.delayed(delay);

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

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.response?.statusCode ?? 0) >= 500;
  }
}

// ==================== 增强缓存拦截器 ====================

/// 增强内存缓存拦截器 - 支持 LRU 淘汰、容量限制、内容类型过滤、HTTP 缓存头
class _EnhancedCacheInterceptor extends Interceptor {
  static final _cache = <String, _CacheEntry>{};
  static const _maxCacheSize = 500;
  static final _accessOrder = <String>[]; // LRU 访问顺序

  // 缓存容量限制：50MB
  static const int _maxCacheBytes = 50 * 1024 * 1024;
  int _currentCacheBytes = 0;

  // 缓存统计
  int _hitCount = 0;
  int _missCount = 0;

  // 可缓存的内容类型（JSON/API/文本类）
  static const _cacheableContentTypes = {
    'application/json',
    'application/xml',
    'text/',
    'application/javascript',
    'application/x-www-form-urlencoded',
  };

  // 不可缓存的扩展名（二进制/视频/音频/图片）
  static const _nonCacheableExtensions = {
    '.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv',
    '.mp3', '.wav', '.flac', '.aac', '.ogg',
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp',
    '.zip', '.rar', '.7z', '.tar', '.gz',
    '.apk', '.exe', '.dmg', '.iso',
  };

  /// 获取缓存统计
  CacheStats get stats => CacheStats(hitCount: _hitCount, missCount: _missCount);

  /// 清除缓存
  void clearCache() {
    _cache.clear();
    _accessOrder.clear();
    _currentCacheBytes = 0;
    _hitCount = 0;
    _missCount = 0;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final cacheTime = options.extra['cacheTime'] as int? ?? 0;
    if (cacheTime <= 0 || options.method != 'GET') {
      handler.next(options);
      return;
    }

    // 关键请求绕过缓存
    final priority = options.extra['priority'] as int? ?? RequestPriority.normal;
    if (priority == RequestPriority.critical) {
      _missCount++;
      handler.next(options);
      return;
    }

    final key = _cacheKey(options);
    final entry = _cache[key];

    // 检查缓存头：如果有 Cache-Control: no-cache 或 max-age=0，不使用缓存
    if (entry != null) {
      final ccHeader = options.headers['cache-control'] as String?;
      if (ccHeader != null) {
        if (ccHeader.contains('no-cache') || ccHeader.contains('no-store')) {
          _missCount++;
          handler.next(options);
          return;
        }
      }

      // 检查缓存是否过期
      final age = DateTime.now().difference(entry.time).inSeconds;
      final maxAge = _parseMaxAge(entry.response) ?? cacheTime;

      if (age < maxAge) {
        // 缓存命中 - 更新访问顺序（LRU）
        _accessOrder.remove(key);
        _accessOrder.add(key);
        _hitCount++;
        handler.resolve(entry.response);
        return;
      }
    }

    _missCount++;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final cacheTime = response.requestOptions.extra['cacheTime'] as int? ?? 0;
    if (cacheTime > 0 && response.requestOptions.method == 'GET') {
      // 内容类型过滤：只缓存 JSON/API/文本类响应
      if (!_isCacheableResponse(response)) {
        handler.next(response);
        return;
      }

      final key = _cacheKey(response.requestOptions);

      // 计算响应体大小
      final bodyBytes = _estimateResponseSize(response);

      // 如果已存在，先移除旧条目的大小
      if (_cache.containsKey(key)) {
        _currentCacheBytes -= _cache[key]!.bodySize;
        _accessOrder.remove(key);
      }

      // 检查是否超出容量限制
      while (_cache.isNotEmpty &&
          (_currentCacheBytes + bodyBytes > _maxCacheBytes ||
              _cache.length >= _maxCacheSize)) {
        _evictOldest();
      }

      // 存入缓存
      _cache[key] = _CacheEntry(
        response: response,
        time: DateTime.now(),
        bodySize: bodyBytes,
        eTag: response.headers.value('etag'),
        lastModified: response.headers.value('last-modified'),
      );
      _accessOrder.add(key);
      _currentCacheBytes += bodyBytes;
    }
    handler.next(response);
  }

  /// 淘汰最久未访问的缓存条目
  void _evictOldest() {
    if (_accessOrder.isEmpty) return;
    final oldest = _accessOrder.removeAt(0);
    final entry = _cache.remove(oldest);
    if (entry != null) {
      _currentCacheBytes -= entry.bodySize;
    }
  }

  /// 判断响应是否可缓存（基于内容类型）
  bool _isCacheableResponse(Response response) {
    // 检查 URL 扩展名
    final path = response.requestOptions.uri.path.toLowerCase();
    for (final ext in _nonCacheableExtensions) {
      if (path.endsWith(ext)) return false;
    }

    // 检查 Content-Type
    final contentType = response.headers.value('content-type') ?? '';
    final lowerContentType = contentType.toLowerCase();

    // 如果包含不可缓存的类型标记，跳过
    if (lowerContentType.contains('video/') ||
        lowerContentType.contains('audio/') ||
        lowerContentType.contains('image/') ||
        lowerContentType.contains('octet-stream')) {
      return false;
    }

    // 检查是否为可缓存的类型
    for (final cacheable in _cacheableContentTypes) {
      if (lowerContentType.contains(cacheable)) return true;
    }

    // 无 Content-Type 时默认缓存（可能是简单文本响应）
    if (contentType.isEmpty) return true;

    return false;
  }

  /// 估算响应体大小（字节）
  int _estimateResponseSize(Response response) {
    final data = response.data;
    if (data == null) return 0;
    if (data is String) return data.length * 2; // UTF-16 估算
    if (data is List<int>) return data.length;
    if (data is Map || data is List) {
      // JSON 对象估算：转为字符串后计算
      try {
        return data.toString().length * 2;
      } catch (_) {
        return 1024; // 默认 1KB
      }
    }
    return 1024; // 默认 1KB
  }

  /// 解析响应中的 Cache-Control max-age
  int? _parseMaxAge(Response response) {
    final cc = response.headers.value('cache-control');
    if (cc == null) return null;
    final match = RegExp(r'max-age=(\d+)').firstMatch(cc);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }

  String _cacheKey(RequestOptions options) {
    return '${options.method}:${options.uri}';
  }
}

// ==================== 缓存条目 ====================

class _CacheEntry {
  final Response response;
  final DateTime time;
  final int bodySize; // 响应体大小（字节）
  final String? eTag; // ETag 缓存头
  final String? lastModified; // Last-Modified 缓存头

  _CacheEntry({
    required this.response,
    required this.time,
    this.bodySize = 0,
    this.eTag,
    this.lastModified,
  });
}

// ==================== CDN 调度缓存条目 ====================

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

// ==================== 带宽估算拦截器 ====================

/// 带宽估算拦截器 - 记录每次响应的下载速率
class _BandwidthInterceptor extends Interceptor {
  final BandwidthEstimator _estimator;

  _BandwidthInterceptor(this._estimator);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 使用响应头中的耗时信息或估算
    final int responseTime = _extractResponseTime(response);
    if (responseTime > 0) {
      final bytes = _estimateResponseBytes(response);
      if (bytes > 0) {
        _estimator.recordSample(
          connectionKey: response.requestOptions.uri.host,
          bytes: bytes,
          duration: Duration(milliseconds: responseTime),
        );
      }
    }
    handler.next(response);
  }

  /// 从响应中提取耗时（毫秒）
  int _extractResponseTime(Response response) {
    // Dio 不直接提供响应时间，使用 extra 中的时间戳
    final startTime = response.requestOptions.extra['_requestStartTime'];
    if (startTime is int) {
      return DateTime.now().millisecondsSinceEpoch - startTime;
    }
    return 0;
  }

  /// 估算响应字节数
  int _estimateResponseBytes(Response response) {
    // 优先使用 Content-Length 头
    final contentLength = response.headers.value('content-length');
    if (contentLength != null) {
      final length = int.tryParse(contentLength);
      if (length != null && length > 0) return length;
    }

    // 回退：估算响应体大小
    final data = response.data;
    if (data == null) return 0;
    if (data is String) return data.length;
    if (data is List<int>) return data.length;
    if (data is Map || data is List) {
      try {
        return data.toString().length;
      } catch (_) {
        return 0;
      }
    }
    return 0;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 在请求中记录开始时间，用于计算耗时
    options.extra = {
      ...options.extra,
      '_requestStartTime': DateTime.now().millisecondsSinceEpoch,
    };
    handler.next(options);
  }
}

// ==================== 全局 Provider ====================

/// 全局 Provider
final networkEngineProvider = Provider<NetworkEngine>((ref) {
  return NetworkEngine.instance;
});
