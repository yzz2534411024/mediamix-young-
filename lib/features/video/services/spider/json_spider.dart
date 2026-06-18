import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/video_models.dart';
import 'spider_adapter.dart';
import 'spider_models.dart';
import 'tvbox_config_parser.dart';

/// JSON API 蜘蛛适配器
///
/// 基于 TVBox 站点配置，通过自定义 JSON 路径和字段映射解析视频数据。
class JsonSpider implements SpiderAdapter {
  final TvBoxSite _site;
  final Dio _dio;
  Map<String, dynamic> _config = {};

  JsonSpider({required TvBoxSite site, Dio? dio})
      : _site = site,
        _dio = dio ?? Dio();

  @override
  String get key => _site.key;

  @override
  String get name => _site.name;

  @override
  SpiderType get type => SpiderType.json;

  @override
  bool get isSearchSupported => true;

  @override
  Future<void> init(Map<String, dynamic> config) async {
    _config = Map<String, dynamic>.from(config);

    if (_config.containsKey('extUrl')) {
      try {
        final extUrl = _config['extUrl'].toString();
        final response = await _dio.get(extUrl);
        final data = response.data;

        Map<String, dynamic>? remoteConfig;
        if (data is Map<String, dynamic>) {
          remoteConfig = data;
        } else if (data is String) {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) {
            remoteConfig = decoded;
          }
        }

        if (remoteConfig != null) {
          _config = {..._config, ...remoteConfig};
        }
      } catch (_) {
        // 远程配置加载失败时保持原有配置，避免初始化异常
      }
    }
  }

  @override
  Future<SpiderHomeResult> homeContent({int page = 1}) async {
    final url = _config['homeUrl']?.toString() ?? _site.api;
    final data = await _fetchJson(url);
    final categories = _parseCategories();
    final items = _extractList(data, _config['listPath']?.toString() ?? '');
    return SpiderHomeResult(categories: categories, recommend: items);
  }

  @override
  Future<SpiderListResult> categoryContent({
    required String tid,
    int page = 1,
    Map<String, String>? filter,
  }) async {
    var url = (_config['cateUrl']?.toString() ?? '')
        .replaceAll('{tid}', tid)
        .replaceAll('{pg}', page.toString());
    if (url.isEmpty) url = _site.api;

    final data = await _fetchJson(url);
    final items = _extractList(data, _config['listPath']?.toString() ?? '');
    return SpiderListResult(
      list: items,
      page: page,
      pageCount: 1,
      total: items.length,
    );
  }

  @override
  Future<SpiderDetailResult> detailContent({required String id}) async {
    var url = (_config['detailUrl']?.toString() ?? '').replaceAll('{id}', id);
    if (url.isEmpty) url = id;

    final data = await _fetchJson(url);
    final detail = _extractDetail(data, id);
    return SpiderDetailResult(detail: detail);
  }

  @override
  Future<SpiderListResult> searchContent({
    required String keyword,
    int page = 1,
  }) async {
    var url = (_config['searchUrl']?.toString() ?? '')
        .replaceAll('{wd}', Uri.encodeComponent(keyword))
        .replaceAll('{pg}', page.toString());
    if (url.isEmpty) {
      return const SpiderListResult(
        list: [],
        page: 1,
        pageCount: 1,
        total: 0,
      );
    }

    final data = await _fetchJson(url);
    final items = _extractList(data, _config['listPath']?.toString() ?? '');
    return SpiderListResult(
      list: items,
      page: page,
      pageCount: 1,
      total: items.length,
    );
  }

  @override
  Future<SpiderPlayResult> playerContent({
    required String flag,
    required String id,
  }) async {
    final playConfig = _config['playUrl'] as Map<String, dynamic>? ?? {};
    final parseFlag = playConfig['parse']?.toString() ?? '0';

    if (playConfig.containsKey('urlPath')) {
      final data = await _fetchJson(id);
      final playUrl = _extractField(data, playConfig['urlPath'].toString());
      return SpiderPlayResult(
        url: playUrl,
        parse: parseFlag,
        playUrl: parseFlag == '1' ? playUrl : null,
      );
    }

    return SpiderPlayResult(url: id, parse: parseFlag);
  }

  @override
  void dispose() {
    _dio.close(force: true);
  }

  /// 发起 GET 请求并解析为 JSON 对象
  Future<Map<String, dynamic>> _fetchJson(String url) async {
    final response = await _dio.get(url);
    final data = response.data;

    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }

    throw Exception('无效的 JSON 响应');
  }

  /// 解析配置中的分类列表
  List<SpiderCategory> _parseCategories() {
    final cats = _config['categories'] as List? ?? [];
    return cats.whereType<Map<String, dynamic>>().map((c) {
      return SpiderCategory(
        typeId: c['id']?.toString() ?? '',
        typeName: c['name']?.toString() ?? '',
      );
    }).toList();
  }

  /// 按简单 JSON 路径提取列表并映射为 VideoItem
  List<VideoItem> _extractList(dynamic data, String listPath) {
    final raw = listPath.isEmpty ? data : _extractByPath(data, listPath);
    if (raw is! List) return [];

    final result = <VideoItem>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final normalized = _normalizeMap(item);
      result.add(VideoItem.fromJson(normalized, sourceKey: key));
    }
    return result;
  }

  /// 按简单 JSON 路径提取详情并映射为 VideoDetail
  VideoDetail _extractDetail(Map<String, dynamic> data, String id) {
    final detailPath = _config['detailPath']?.toString() ?? '';
    dynamic detail = data;
    if (detailPath.isNotEmpty) {
      detail = _extractByPath(data, detailPath);
    }

    if (detail is! Map<String, dynamic>) {
      return VideoDetail(vodId: id, vodName: '未知', sourceKey: key);
    }

    final normalized = _normalizeMap(detail);
    return VideoDetail.fromJson(normalized, sourceKey: key);
  }

  /// 应用字段映射，将 API 字段名转为标准 vod 字段名
  Map<String, dynamic> _normalizeMap(Map<String, dynamic> source) {
    final fieldMap = _config['fieldMap'] as Map<String, dynamic>? ?? {};
    final normalized = <String, dynamic>{};

    for (final entry in fieldMap.entries) {
      final apiKey = entry.value?.toString();
      if (apiKey != null && apiKey.isNotEmpty) {
        normalized[entry.key] = source[apiKey];
      }
    }

    for (final entry in source.entries) {
      if (!normalized.containsKey(entry.key)) {
        normalized[entry.key] = entry.value;
      }
    }

    return normalized;
  }

  /// 按简单路径（如 $.data.list）从 JSON 中提取值
  dynamic _extractByPath(dynamic data, String path) {
    final segments = path.replaceAll('\$', '').split('.')
      ..removeWhere((s) => s.isEmpty);

    dynamic current = data;
    for (final seg in segments) {
      if (current is Map<String, dynamic>) {
        current = current[seg];
      } else {
        return null;
      }
    }
    return current;
  }

  /// 按简单路径从 JSON 中提取字符串字段
  String _extractField(Map<String, dynamic> data, String path) {
    final value = _extractByPath(data, path);
    return value?.toString() ?? '';
  }
}
