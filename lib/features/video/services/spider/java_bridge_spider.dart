import 'dart:convert';

import 'package:logger/logger.dart';

import '../../models/video_models.dart';
import 'java_bridge_client.dart';
import 'spider_adapter.dart';
import 'spider_models.dart';
import 'tvbox_config_parser.dart';

/// Java Bridge 蜘蛛适配器
///
/// 通过本地 HTTP 桥接调用 TVBox Java 蜘蛛（csp_*Guard 等）。
/// Java 端负责加载 JAR 并通过反射调用蜘蛛方法，
/// Dart 端通过 [JavaBridgeClient] 发起 HTTP 请求获取结果。
class JavaBridgeSpider implements SpiderAdapter {
  final Logger _logger = Logger(printer: SimplePrinter());
  final TvBoxSite site;
  final JavaBridgeClient client;

  JavaBridgeSpider({
    required this.site,
    required this.client,
  });

  @override
  String get key => site.key;

  @override
  String get name => site.name;

  @override
  SpiderType get type => SpiderType.javaBridge;

  @override
  bool get isSearchSupported {
    // TVBox 站点的 searchable 字段：0=不支持搜索，1=支持
    // 默认支持（除非明确设为 0）
    return true;
  }

  @override
  Future<void> init(Map<String, dynamic> config) async {
    final result = await client.initSpider(site.key, config: config);
    if (result['code'] != 0) {
      _logger.w('Java蜘蛛初始化失败 [${site.key}]: ${result['msg']}');
    } else {
      _logger.d('Java蜘蛛初始化成功: ${site.key} (${site.api})');
    }
  }

  @override
  Future<SpiderHomeResult> homeContent({int page = 1}) async {
    final result = await client.homeContent(site.key, page: page);
    if (result['code'] != 0) {
      _logger.w('Java蜘蛛首页获取失败 [${site.key}]: ${result['msg']}');
      return const SpiderHomeResult();
    }

    final data = _extractData(result);
    if (data == null) return const SpiderHomeResult();

    return _parseHomeResult(data);
  }

  @override
  Future<SpiderListResult> categoryContent({
    required String tid,
    int page = 1,
    Map<String, String>? filter,
  }) async {
    final result = await client.categoryContent(
      site.key,
      tid: tid,
      page: page,
      filter: filter,
    );
    if (result['code'] != 0) {
      _logger.w('Java蜘蛛分类获取失败 [${site.key}]: ${result['msg']}');
      return const SpiderListResult();
    }

    final data = _extractData(result);
    if (data == null) return const SpiderListResult();

    return _parseListResult(data);
  }

  @override
  Future<SpiderDetailResult> detailContent({required String id}) async {
    final result = await client.detailContent(site.key, id);
    if (result['code'] != 0) {
      _logger.w('Java蜘蛛详情获取失败 [${site.key}]: ${result['msg']}');
      return SpiderDetailResult(
        detail: VideoDetail(vodId: id, vodName: '未知', sourceKey: key),
      );
    }

    final data = _extractData(result);
    if (data == null) {
      return SpiderDetailResult(
        detail: VideoDetail(vodId: id, vodName: '未知', sourceKey: key),
      );
    }

    return _parseDetailResult(data, id);
  }

  @override
  Future<SpiderListResult> searchContent({
    required String keyword,
    int page = 1,
  }) async {
    final result = await client.searchContent(
      site.key,
      keyword: keyword,
      page: page,
    );
    if (result['code'] != 0) {
      _logger.w('Java蜘蛛搜索失败 [${site.key}]: ${result['msg']}');
      return const SpiderListResult();
    }

    final data = _extractData(result);
    if (data == null) return const SpiderListResult();

    return _parseListResult(data);
  }

  @override
  Future<SpiderPlayResult> playerContent({
    required String flag,
    required String id,
  }) async {
    final result = await client.playerContent(
      site.key,
      flag: flag,
      id: id,
    );
    if (result['code'] != 0) {
      _logger.w('Java蜘蛛播放解析失败 [${site.key}]: ${result['msg']}');
      return SpiderPlayResult(url: id);
    }

    final data = _extractData(result);
    if (data == null) return SpiderPlayResult(url: id);

    return _parsePlayResult(data, id);
  }

  @override
  void dispose() {
    // JavaBridgeSpider 不直接 dispose client，由 JavaBridgeManager 统一管理
  }

  // ==================== 响应解析 ====================

  /// 从 Bridge 响应中提取 data 字段
  dynamic _extractData(Map<String, dynamic> result) {
    final data = result['data'];
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is List) return {'list': decoded};
      } catch (_) {}
    }
    return null;
  }

  /// 解析首页结果
  SpiderHomeResult _parseHomeResult(Map<String, dynamic> data) {
    final categories = <SpiderCategory>[];
    final classList = data['class'];
    if (classList is List) {
      for (final c in classList) {
        if (c is Map<String, dynamic>) {
          categories.add(SpiderCategory(
            typeId: c['type_id']?.toString() ?? c['typeId']?.toString() ?? '',
            typeName: c['type_name']?.toString() ?? c['typeName']?.toString() ?? '',
          ));
        }
      }
    }

    final recommend = _parseVideoList(data['list'] ?? data['recommend']);

    final classMap = <String, List<VideoItem>>{};
    if (data['videoList'] is Map<String, dynamic>) {
      final videoMap = data['videoList'] as Map<String, dynamic>;
      for (final entry in videoMap.entries) {
        classMap[entry.key] = _parseVideoList(entry.value);
      }
    }

    return SpiderHomeResult(
      categories: categories,
      recommend: recommend,
      classList: classMap.isNotEmpty ? classMap : null,
    );
  }

  /// 解析列表结果
  SpiderListResult _parseListResult(Map<String, dynamic> data) {
    final list = _parseVideoList(data['list'] ?? data['data']);
    final page = _intValue(data['page'] ?? data['pageCount'] ?? 1);
    final pageCount = _intValue(data['pagecount'] ?? data['pageCount'] ?? 1);
    final total = _intValue(data['total'] ?? data['recordcount'] ?? list.length);

    return SpiderListResult(
      list: list,
      page: page,
      pageCount: pageCount,
      total: total,
    );
  }

  /// 解析详情结果
  SpiderDetailResult _parseDetailResult(Map<String, dynamic> data, String id) {
    // TVBox 详情格式：{ "list": [{ "vod_id": ..., "vod_name": ..., ... }] }
    final list = data['list'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map<String, dynamic>) {
        final detail = VideoDetail.fromJson(first, sourceKey: key);
        return SpiderDetailResult(detail: detail);
      }
    }

    // 尝试直接解析 data 为详情
    if (data.containsKey('vod_id') || data.containsKey('vodId')) {
      final detail = VideoDetail.fromJson(data, sourceKey: key);
      return SpiderDetailResult(detail: detail);
    }

    return SpiderDetailResult(
      detail: VideoDetail(vodId: id, vodName: '未知', sourceKey: key),
    );
  }

  /// 解析播放结果
  SpiderPlayResult _parsePlayResult(Map<String, dynamic> data, String fallbackId) {
    // TVBox 播放结果格式：
    // { "url": "xxx", "parse": 0/1, "flag": "xxx", "header": {...} }
    // 或 { "playUrl": "xxx" }
    String url = data['url']?.toString() ?? '';
    String? parse;
    Map<String, String>? headers;

    if (url.isEmpty) {
      // 尝试从 playUrl 字段获取
      url = data['playUrl']?.toString() ?? fallbackId;
    }

    final parseValue = data['parse'];
    if (parseValue is int) {
      parse = parseValue.toString();
    } else if (parseValue is String) {
      parse = parseValue;
    }

    final headerData = data['header'];
    if (headerData is Map<String, dynamic>) {
      headers = headerData.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    }

    return SpiderPlayResult(
      url: url,
      parse: parse,
      headers: headers,
      playUrl: parse == '1' ? url : null,
    );
  }

  /// 解析视频列表
  List<VideoItem> _parseVideoList(dynamic raw) {
    if (raw is! List) return [];

    final result = <VideoItem>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        result.add(VideoItem.fromJson(item, sourceKey: key));
      } catch (e) {
        _logger.d('解析视频项失败: $e');
      }
    }
    return result;
  }

  int _intValue(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is double) return v.toInt();
    return 0;
  }
}
