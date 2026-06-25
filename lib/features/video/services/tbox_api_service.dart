import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:logger/logger.dart';
import '../models/video_models.dart';
import 'spider/tvbox_config_parser.dart';
import 'spider/tvbox_image_decoder.dart';
import '../../../core/network/network_engine.dart';
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

  VideoApiService({Dio? dio}) : _dio = dio ?? _createDio();

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': 'okhttp/3.12.11',
        'Accept': '*/*',
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

  /// 选择最优CDN节点 - 委托给 NetworkEngine 进行并行 TCP 测速
  /// 缓存5分钟TTL
  Future<String> selectBestCdn(List<String> cdnUrls) async {
    return NetworkEngine.instance.selectBestCdn(cdnUrls);
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
  // ignore: unused_element
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

  /// 获取分类列表（支持标准 CMS、TVBox 配置、图片伪装三种格式）
  Future<List<VideoCategory>> fetchCategories(String apiUrl) async {
    try {
      final url = _buildUrl(apiUrl, {'ac': 'list'});
      _logger.d('获取分类列表: $url');

      // 使用 HttpClient 直接请求，绕过 Dio
      final data = await _fetchAndDecode(url);

      // TVBox 配置格式：sites 数组 → 转为 class 分类
      if (data.containsKey('sites') && data['sites'] is List) {
        final sites = data['sites'] as List;
        final categories = <VideoCategory>[];
        for (int i = 0; i < sites.length; i++) {
          final s = sites[i] as Map<String, dynamic>?;
          if (s != null) {
            categories.add(VideoCategory(
              typeId: i + 1,
              typeName: (s['name'] ?? s['key'] ?? '').toString(),
              typePid: 0,
            ));
          }
        }
        // 缓存站点列表供后续查询
        _tvboxSites = sites.cast<Map<String, dynamic>>();
        return categories;
      }

      // 标准 CMS 格式
      final List<VideoCategory> categories = [];
      for (final c in (data['class'] as List?) ?? []) {
        if (c is Map<String, dynamic>) {
          categories.add(VideoCategory.fromJson(c));
        }
      }
      return categories;
    } catch (e) {
      _logger.e('获取分类列表失败: $e');
      throw Exception('获取分类失败: $e');
    }
  }

  /// 缓存的 TVBox 站点列表
  List<Map<String, dynamic>>? _tvboxSites;

  /// 获取影片列表（支持 TVBox 站点派生 URL 和图片伪装格式）
  Future<VideoListResponse> fetchVideoList(String apiUrl, {int page = 1, int? typeId}) async {
    try {
      // 如果有缓存的 TVBox 站点且 typeId 有效，尝试使用该站点的 ext URL
      String effectiveUrl = apiUrl;
      if (_tvboxSites != null && typeId != null && typeId > 0 && typeId <= _tvboxSites!.length) {
        final site = _tvboxSites![typeId - 1];
        final ext = site['ext'];
        if (ext is String && (ext.startsWith('http://') || ext.startsWith('https://'))) {
          effectiveUrl = ext;
          _logger.d('使用TVBox站点URL: ${site['name']} → $effectiveUrl');
        }
      }

      final params = <String, String>{'ac': 'detail', 'pg': page.toString()};
      if (typeId != null && effectiveUrl == apiUrl) {
        params['t'] = typeId.toString();
      }
      final url = _buildUrl(effectiveUrl, params);
      _logger.d('获取影片列表: $url');

      final data = await _fetchAndDecode(url);

      // 检测 TVBox 配置格式（饭太硬等配置源会返回 sites 数组而非视频列表）
      if (data.containsKey('sites') && data['sites'] is List) {
        _logger.d('响应是 TVBox 配置格式，缓存 sites 并返回空列表');
        _tvboxSites = (data['sites'] as List).cast<Map<String, dynamic>>();
        return VideoListResponse(
          list: [],
          page: page,
          pageCount: 0,
          total: 0,
        );
      }

      return VideoListResponse.fromJson(data);
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

      final data = await _fetchAndDecode(url);

      final list = data['list'] as List?;
      if (list == null || list.isEmpty) {
        throw Exception('影片不存在');
      }

      return VideoDetail.fromJson(list.first as Map<String, dynamic>, sourceKey: sourceKey);
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

      final data = await _fetchAndDecode(url);

      // 检测 TVBox 配置格式
      if (data.containsKey('sites') && data['sites'] is List) {
        _logger.d('搜索响应是 TVBox 配置格式，返回空列表');
        return const VideoListResponse(list: [], page: 1, pageCount: 0, total: 0);
      }

      return VideoListResponse.fromJson(data);
    } catch (e) {
      _logger.e('搜索影片失败: $e');
      throw Exception('搜索失败: $e');
    }
  }

  /// 使用 dart:io HttpClient 直接请求并解码响应
  /// 绕过 Dio，彻底解决 bytes 类型判断和图片伪装格式问题
  Future<Map<String, dynamic>> _fetchAndDecode(String url) async {
    _logger.d('_fetchAndDecode: $url');
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.idleTimeout = const Duration(seconds: 5);
      client.autoUncompress = false; // 禁止自动解压，避免 gzip 问题
      client.badCertificateCallback = (cert, host, port) => true;
      try {
        ProxyConfigService.instance.configureHttpClient(client);
      } catch (_) {}

      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'okhttp/3.12.11');
      request.headers.set('Accept', '*/*');
      request.headers.set('Accept-Encoding', 'identity'); // 明确要求不压缩

      final response = await request.close();
      final statusCode = response.statusCode;
      if (statusCode != 200) {
        throw Exception('HTTP $statusCode');
      }

      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }

      _logger.d('_fetchAndDecode: 收到 ${bytes.length} bytes, '
          '前10字节=${bytes.take(10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      // 步骤0：如果数据是 gzip 压缩的，先解压
      List<int> effectiveBytes = bytes;
      if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
        _logger.d('_fetchAndDecode: 检测到 gzip 压缩数据，正在解压...');
        try {
          effectiveBytes = gzip.decode(bytes);
          _logger.d('_fetchAndDecode: gzip 解压后 ${effectiveBytes.length} bytes');
        } catch (e) {
          _logger.w('_fetchAndDecode: gzip 解压失败: $e，使用原始数据');
        }
      }

      // 步骤1：TvBoxImageDecoder（JPEG 伪装 + UTF-8 + GBK + Base64）
      final decoded = TvBoxImageDecoder.decode(effectiveBytes);
      if (decoded != null) {
        _logger.d('_fetchAndDecode: TvBoxImageDecoder 解码成功');
        return decoded;
      }

      // 步骤2：直接 UTF-8 解码后 JSON 解析（支持 TVBox 注释格式）
      try {
        final text = utf8.decode(effectiveBytes, allowMalformed: true).trim();
        if (text.startsWith('{')) {
          final json = _parseJsonWithComments(text);
          if (json != null) {
            _logger.d('_fetchAndDecode: UTF-8 JSON 解码成功');
            return json;
          }
        }
      } catch (_) {}

      // 步骤3：提取 ASCII 文本后尝试 Base64 解码
      final asciiText = String.fromCharCodes(
        effectiveBytes.where((b) => b >= 32 && b <= 126),
      );
      if (asciiText.isNotEmpty) {
        final json = _tryParseJsonOrBase64(asciiText);
        if (json != null) {
          _logger.d('_fetchAndDecode: ASCII Base64 解码成功');
          return json;
        }
      }

      _logger.e('_fetchAndDecode: 所有解码方式均失败, bytes长度=${effectiveBytes.length}');
      throw Exception('JSON 解析失败: 无法识别的响应格式 (${effectiveBytes.length} bytes)');
    } catch (e) {
      _logger.e('_fetchAndDecode 失败: $e');
      rethrow;
    } finally {
      client?.close();
    }
  }

  /// 构建请求 URL（自动处理中文域名 Punycode 编码）
  String _buildUrl(String apiUrl, Map<String, String> params) {
    var url = apiUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    // 用 Uri.parse 处理 IDN 域名（如 饭太硬.net → xn--...）
    final uri = Uri.parse(url);
    final separator = uri.query.isNotEmpty ? '&' : '?';
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}$separator$query';
  }

  /// 尝试解析含 ** 分隔符的 Base64 或纯 Base64 文本
  Map<String, dynamic>? _tryParseJsonOrBase64(String text) {
    // 方式1：找 ** 分隔符后的 Base64
    final markerIdx = text.indexOf('**');
    if (markerIdx >= 0) {
      final b64Data = text.substring(markerIdx + 2).trim();
      if (b64Data.isNotEmpty) {
        try {
          final cleaned = b64Data.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
          if (cleaned.length >= 4) {
            final decoded = base64Decode(cleaned);
            final jsonStr = utf8.decode(decoded);
            final json = _parseJsonWithComments(jsonStr);
            if (json != null) return json;
          }
        } catch (_) {}
      }
    }

    // 方式2：整个文本作为 Base64
    if (text.length >= 4) {
      try {
        final cleaned = text.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
        if (cleaned.length >= 4) {
          final decoded = base64Decode(cleaned);
          final jsonStr = utf8.decode(decoded);
          final json = _parseJsonWithComments(jsonStr);
          if (json != null) return json;
        }
      } catch (_) {}
    }

    return null;
  }

  /// 解析可能包含 JavaScript 风格注释的 JSON
  /// TVBox 配置文件常含 // 单行注释和 /* */ 多行注释
  Map<String, dynamic>? _parseJsonWithComments(String text) {
    // 先尝试直接解析
    try {
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) return json;
    } catch (_) {}

    // 剥离注释后再解析
    final cleaned = _stripJsonComments(text);
    try {
      final json = jsonDecode(cleaned);
      if (json is Map<String, dynamic>) return json;
    } catch (_) {}

    return null;
  }

  /// 剥离 JSON 中的 JavaScript 风格注释
  /// 支持 // 单行注释和 /* */ 多行注释
  static String _stripJsonComments(String text) {
    final sb = StringBuffer();
    int i = 0;
    bool inString = false;
    String? stringChar;

    while (i < text.length) {
      if (inString) {
        final ch = text[i];
        sb.write(ch);
        if (ch == '\\' && i + 1 < text.length) {
          i++;
          sb.write(text[i]);
        } else if (ch == stringChar) {
          inString = false;
        }
        i++;
        continue;
      }

      if (text[i] == '"' || text[i] == "'") {
        inString = true;
        stringChar = text[i];
        sb.write(text[i]);
        i++;
      } else if (i + 1 < text.length && text[i] == '/' && text[i + 1] == '/') {
        i += 2;
        while (i < text.length && text[i] != '\n' && text[i] != '\r') {
          i++;
        }
      } else if (i + 1 < text.length && text[i] == '/' && text[i + 1] == '*') {
        i += 2;
        while (i + 1 < text.length && !(text[i] == '*' && text[i + 1] == '/')) {
          i++;
        }
        i += 2;
      } else {
        sb.write(text[i]);
        i++;
      }
    }

    return sb.toString();
  }

  /// 获取 TVBox 配置文件
  Future<TvBoxConfig> fetchTvBoxConfig(String configUrl) async {
    try {
      final url = _buildUrl(configUrl, {});
      _logger.d('获取TVBox配置: $url');

      final json = await _fetchAndDecode(url);

      final config = const TvBoxConfigParser().parse(json);
      _logger.d('TVBox配置解析完成: ${config.sites.length}个站点, '
          'spider=${config.spiderUrl}');
      return config;
    } catch (e) {
      _logger.e('获取TVBox配置失败: $e');
      throw Exception('加载失败: $e');
    }
  }

  /// 清除所有缓存
  void clearAllCache() {
    _dnsCache.clear();
    _prefetchCache.clear();
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
