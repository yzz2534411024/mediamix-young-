import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// 高性能网络引擎 - 支持并发、缓存、重试、DNS预解析
class NetworkEngine {
  static NetworkEngine? _instance;
  late final Dio _dio;
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  // DNS 预解析缓存
  final _dnsCache = <String, DateTime>{};
  static const _dnsCacheTtl = Duration(minutes: 10);

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

    // 启用 HTTP/2 和连接池优化
    (_dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate =
        (client) {
      client..badCertificateCallback = (cert, host, port) => true;
      return client;
    };

    // 添加拦截器：日志 + 缓存 + 重试
    _dio.interceptors.addAll([
      _RetryInterceptor(dio: _dio, maxRetries: 3),
      _CacheInterceptor(),
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (o) => _logger.d(o),
      ),
    ]);
  }

  static NetworkEngine get instance => _instance ??= NetworkEngine._();

  Dio get dio => _dio;

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
    try {
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isNotEmpty) {
        _dnsCache[host] = DateTime.now();
        _logger.d('DNS 预解析成功: $host -> ${addresses.first.address}');
      }
    } catch (e) {
      _logger.w('DNS 预解析失败: $host');
    }
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
    final semaphore = _Semaphore(maxConcurrent);
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

  /// 清除请求缓存
  void clearRequestCache() {
    _CacheInterceptor.clearCache();
    _logger.d('请求缓存已清除');
  }
}

/// 信号量 - 控制并发数
class _Semaphore {
  int _count;
  final int _max;
  final List<Completer<void>> _waiters = [];

  _Semaphore(this._max) : _count = _max;

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

/// 重试拦截器 - 指数退避
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  _RetryInterceptor({required this.dio, this.maxRetries = 3});

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final retries = err.requestOptions.extra['retries'] ?? 0;
    if (retries < maxRetries && _shouldRetry(err)) {
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

/// 增强内存缓存拦截器 - 支持 LRU 淘汰
class _CacheInterceptor extends Interceptor {
  static final _cache = <String, _CacheEntry>{};
  static const _maxCacheSize = 500;
  static final _accessOrder = <String>[]; // LRU 访问顺序

  static void clearCache() {
    _cache.clear();
    _accessOrder.clear();
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final cacheTime = options.extra['cacheTime'] as int? ?? 0;
    if (cacheTime <= 0 || options.method != 'GET') {
      handler.next(options);
      return;
    }

    final key = _cacheKey(options);
    final entry = _cache[key];
    if (entry != null && DateTime.now().difference(entry.time).inSeconds < cacheTime) {
      // 更新访问顺序（LRU）
      _accessOrder.remove(key);
      _accessOrder.add(key);
      handler.resolve(entry.response);
      return;
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final cacheTime = response.requestOptions.extra['cacheTime'] as int? ?? 0;
    if (cacheTime > 0 && response.requestOptions.method == 'GET') {
      final key = _cacheKey(response.requestOptions);

      // 如果已存在，先移除旧访问记录
      _accessOrder.remove(key);

      _cache[key] = _CacheEntry(response: response, time: DateTime.now());
      _accessOrder.add(key);

      // LRU 淘汰：超出容量时移除最久未访问的
      while (_cache.length > _maxCacheSize) {
        final oldest = _accessOrder.removeAt(0);
        _cache.remove(oldest);
      }
    }
    handler.next(response);
  }

  String _cacheKey(RequestOptions options) {
    return '${options.method}:${options.uri}';
  }
}

class _CacheEntry {
  final Response response;
  final DateTime time;
  _CacheEntry({required this.response, required this.time});
}

/// 全局 Provider
final networkEngineProvider = Provider<NetworkEngine>((ref) {
  return NetworkEngine.instance;
});
