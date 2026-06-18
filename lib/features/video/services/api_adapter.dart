import 'dart:convert';
import 'package:logger/logger.dart';
import '../models/video_models.dart';

/// API 源类型
enum ApiSourceType {
  /// CMS 采集站标准格式 (api.php/provide/vod/)
  cmsCollection,

  /// 标准 JSON REST API
  jsonRest,

  /// 直接 HLS/M3U8 播放列表源
  m3u8Direct,

  /// Mao 格式 API（兼容老版本接口）
  maoApi,
}

/// API 源描述
class ApiSourceDescriptor {
  final String key;
  final String name;
  final ApiSourceType type;
  final String apiUrl;
  final Map<String, String> paramMapping;

  const ApiSourceDescriptor({
    required this.key,
    required this.name,
    required this.type,
    required this.apiUrl,
    this.paramMapping = const {},
  });
}

/// API 响应适配器
///
/// 负责将不同格式的 API 响应转换为统一的内部模型。
/// 支持 CMS 采集站、JSON REST、M3U8 直接源等多种格式。
class ApiAdapter {
  final Logger _logger = Logger(printer: SimplePrinter());

  // ============================================================
  // 分类列表解析
  // ============================================================

  /// 解析分类列表 — 支持多种响应格式
  List<VideoCategory> parseCategories(
    dynamic data, {
    ApiSourceType sourceType = ApiSourceType.cmsCollection,
  }) {
    switch (sourceType) {
      case ApiSourceType.cmsCollection:
        return _parseCmsCategories(data);
      case ApiSourceType.jsonRest:
        return _parseJsonRestCategories(data);
      case ApiSourceType.maoApi:
        return _parseMaoCategories(data);
      default:
        _logger.w('不支持的分类解析类型: $sourceType');
        return [];
    }
  }

  List<VideoCategory> _parseCmsCategories(dynamic data) {
    final json = _ensureMap(data);
    if (json == null) return [];
    final list = json['class'];
    if (list is! List) return [];
    return list
        .map((e) => VideoCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<VideoCategory> _parseJsonRestCategories(dynamic data) {
    final json = _ensureMap(data);
    if (json == null) return [];
    // JSON REST 常见格式: { "data": [{ "id": 1, "name": "电影" }] }
    final list = json['data'] ?? json['categories'] ?? json['items'] ?? [];
    if (list is! List) return [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return VideoCategory(
        typeId: int.tryParse('${m['id'] ?? m['type_id'] ?? 0}') ?? 0,
        typePid: int.tryParse('${m['pid'] ?? m['parent_id'] ?? 0}') ?? 0,
        typeName: '${m['name'] ?? m['type_name'] ?? m['title'] ?? ''}',
      );
    }).toList();
  }

  List<VideoCategory> _parseMaoCategories(dynamic data) {
    final json = _ensureMap(data);
    if (json == null) return [];
    // 猫格式: { "types": [{ "id": "1", "name": "电影" }] }
    final list = json['types'] ?? json['class'] ?? [];
    if (list is! List) return [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return VideoCategory(
        typeId: int.tryParse('${m['id'] ?? m['type_id'] ?? 0}') ?? 0,
        typePid: 0,
        typeName: '${m['name'] ?? m['type_name'] ?? ''}',
      );
    }).toList();
  }

  // ============================================================
  // 视频列表解析
  // ============================================================

  /// 解析视频列表 — 支持多种响应格式
  VideoListResponse parseVideoList(
    dynamic data, {
    ApiSourceType sourceType = ApiSourceType.cmsCollection,
  }) {
    switch (sourceType) {
      case ApiSourceType.cmsCollection:
        return _parseCmsVideoList(data);
      case ApiSourceType.jsonRest:
        return _parseJsonRestVideoList(data);
      case ApiSourceType.maoApi:
        return _parseMaoVideoList(data);
      default:
        _logger.w('不支持的列表解析类型: $sourceType');
        return const VideoListResponse(list: [], page: 1, pageCount: 1, total: 0);
    }
  }

  VideoListResponse _parseCmsVideoList(dynamic data) {
    final json = _ensureMap(data);
    if (json == null) return const VideoListResponse(list: [], page: 1, pageCount: 1, total: 0);
    return VideoListResponse.fromJson(json);
  }

  VideoListResponse _parseJsonRestVideoList(dynamic data) {
    final json = _ensureMap(data);
    if (json == null) return const VideoListResponse(list: [], page: 1, pageCount: 1, total: 0);
    // JSON REST 常见格式: { "data": { "list": [...], "page": 1, "total": 100 } }
    final inner = json['data'] ?? json['result'] ?? json;
    if (inner is! Map<String, dynamic>) return const VideoListResponse(list: [], page: 1, pageCount: 1, total: 0);

    // 尝试多个常见的列表字段名
    final list = inner['list'] ?? inner['items'] ?? inner['records'] ?? inner['data'] ?? [];
    if (list is! List) return const VideoListResponse(list: [], page: 1, pageCount: 1, total: 0);

    final items = list.map((e) {
      final m = e as Map<String, dynamic>;
      return VideoItem(
        vodId: '${m['id'] ?? m['vod_id'] ?? m['video_id'] ?? ''}',
        vodName: '${m['title'] ?? m['name'] ?? m['vod_name'] ?? ''}',
        vodPic: '${m['cover'] ?? m['pic'] ?? m['vod_pic'] ?? m['image'] ?? ''}',
        vodRemarks: '${m['remarks'] ?? m['vod_remarks'] ?? m['description'] ?? ''}',
        vodYear: '${m['year'] ?? m['vod_year'] ?? ''}',
        vodArea: '${m['area'] ?? m['vod_area'] ?? ''}',
        typeName: '${m['type_name'] ?? m['category'] ?? ''}',
      );
    }).toList();

    return VideoListResponse(
      list: items,
      page: int.tryParse('${inner['page'] ?? inner['pageNum'] ?? 1}') ?? 1,
      pageCount: int.tryParse('${inner['pagecount'] ?? inner['pages'] ?? 1}') ?? 1,
      total: int.tryParse('${inner['total'] ?? inner['totalCount'] ?? 0}') ?? 0,
    );
  }

  VideoListResponse _parseMaoVideoList(dynamic data) {
    final json = _ensureMap(data);
    if (json == null) return const VideoListResponse(list: [], page: 1, pageCount: 1, total: 0);
    final list = json['list'] ?? json['videos'] ?? [];
    if (list is! List) return const VideoListResponse(list: [], page: 1, pageCount: 1, total: 0);

    final items = list.map((e) {
      final m = e as Map<String, dynamic>;
      return VideoItem(
        vodId: '${m['id'] ?? m['vod_id'] ?? ''}',
        vodName: '${m['title'] ?? m['vod_name'] ?? m['name'] ?? ''}',
        vodPic: '${m['cover'] ?? m['vod_pic'] ?? m['pic'] ?? ''}',
        vodRemarks: '${m['remarks'] ?? m['note'] ?? ''}',
        vodYear: '${m['year'] ?? ''}',
        vodArea: '${m['area'] ?? ''}',
        typeName: '${m['category'] ?? m['type_name'] ?? ''}',
      );
    }).toList();

    return VideoListResponse(
      list: items,
      page: int.tryParse('${json['page'] ?? 1}') ?? 1,
      pageCount: int.tryParse('${json['pagecount'] ?? 1}') ?? 1,
      total: int.tryParse('${json['total'] ?? 0}') ?? 0,
    );
  }

  // ============================================================
  // 视频详情解析
  // ============================================================

  /// 解析视频详情 — 支持多种响应格式
  VideoDetail? parseVideoDetail(
    dynamic data, {
    ApiSourceType sourceType = ApiSourceType.cmsCollection,
    String? sourceKey,
  }) {
    switch (sourceType) {
      case ApiSourceType.cmsCollection:
        return _parseCmsVideoDetail(data, sourceKey: sourceKey ?? '');
      case ApiSourceType.jsonRest:
        return _parseJsonRestVideoDetail(data, sourceKey: sourceKey ?? '');
      case ApiSourceType.maoApi:
        return _parseMaoVideoDetail(data, sourceKey: sourceKey ?? '');
      default:
        _logger.w('不支持的详情解析类型: $sourceType');
        return null;
    }
  }

  VideoDetail? _parseCmsVideoDetail(dynamic data, {String? sourceKey}) {
    final json = _ensureMap(data);
    if (json == null) return null;
    final list = json['list'];
    if (list is! List || list.isEmpty) return null;
    return VideoDetail.fromJson(
      list.first as Map<String, dynamic>,
      sourceKey: sourceKey ?? '',
    );
  }

  VideoDetail? _parseJsonRestVideoDetail(dynamic data, {String? sourceKey}) {
    final json = _ensureMap(data);
    if (json == null) return null;

    // 多种嵌套格式: data, result, 或顶层
    final inner = json['data'] ?? json['result'] ?? json;
    if (inner is! Map<String, dynamic>) return null;

    final video = inner['video'] ?? inner['detail'] ?? inner;
    if (video is! Map<String, dynamic>) return null;

    // 解析播放源 — JSON REST 可能有不同格式
    final sources = <PlaySource>[];
    final playUrls = video['play_urls'] ?? video['episodes'] ?? video['sources'];
    if (playUrls is List) {
      for (final s in playUrls) {
        if (s is Map<String, dynamic>) {
          final episodes = <VideoEpisode>[];
          final eps = s['episodes'] ?? s['items'] ?? s['urls'] ?? [s];
          if (eps is List) {
            for (final ep in eps) {
              if (ep is Map<String, dynamic>) {
                episodes.add(VideoEpisode(
                  name: '${ep['name'] ?? ep['title'] ?? ep['label'] ?? ''}',
                  url: '${ep['url'] ?? ep['src'] ?? ''}',
                ));
              }
            }
          }
          if (episodes.isNotEmpty) {
            sources.add(PlaySource(
              name: sourceKey ?? '${s['name'] ?? s['label'] ?? '默认'}',
              episodes: episodes,
            ));
          }
        }
      }
    }

    // 兼容旧格式：vod_play_url 字符串解析
    if (sources.isEmpty && video['vod_play_url'] != null) {
      return VideoDetail.fromJson(video, sourceKey: sourceKey ?? '');
    }

    return VideoDetail(
      vodId: '${video['id'] ?? video['vod_id'] ?? video['video_id'] ?? ''}',
      vodName: '${video['title'] ?? video['name'] ?? video['vod_name'] ?? ''}',
      vodPic: '${video['cover'] ?? video['pic'] ?? video['vod_pic'] ?? ''}',
      vodContent: '${video['description'] ?? video['vod_content'] ?? video['summary'] ?? ''}',
      vodActor: '${video['actor'] ?? video['vod_actor'] ?? video['actors'] ?? ''}',
      vodDirector: '${video['director'] ?? video['vod_director'] ?? ''}',
      vodYear: '${video['year'] ?? video['vod_year'] ?? ''}',
      vodArea: '${video['area'] ?? video['vod_area'] ?? ''}',
      vodRemarks: '${video['remarks'] ?? video['vod_remarks'] ?? ''}',
      typeName: '${video['category'] ?? video['type_name'] ?? ''}',
      playSources: sources,
      sourceKey: sourceKey ?? '',
    );
  }

  VideoDetail? _parseMaoVideoDetail(dynamic data, {String? sourceKey}) {
    final json = _ensureMap(data);
    if (json == null) return null;

    final video = json['video'] ?? json['data'] ?? json;
    if (video is! Map<String, dynamic>) return null;

    return VideoDetail.fromJson(video, sourceKey: sourceKey ?? '');
  }

  // ============================================================
  // 搜索结果解析
  // ============================================================

  /// 解析搜索结果
  VideoListResponse parseSearchResults(
    dynamic data, {
    ApiSourceType sourceType = ApiSourceType.cmsCollection,
  }) {
    // 搜索结果格式与视频列表相同
    return parseVideoList(data, sourceType: sourceType);
  }

  // ============================================================
  // 自动检测 API 类型
  // ============================================================

  /// 根据响应数据自动检测 API 类型
  ApiSourceType detectApiType(dynamic data) {
    if (data is String) {
      // 尝试判断是否为 M3U8
      if (data.trim().startsWith('#EXTM3U')) {
        return ApiSourceType.m3u8Direct;
      }
      // 尝试 JSON 解析
      try {
        data = jsonDecode(data);
      } catch (_) {
        return ApiSourceType.cmsCollection;
      }
    }

    final json = _ensureMap(data);
    if (json == null) return ApiSourceType.cmsCollection;

    // JSON REST 特征：有 data/code/message 字段
    if (json.containsKey('code') && json.containsKey('data')) {
      return ApiSourceType.jsonRest;
    }

    // 猫格式特征
    if (json.containsKey('types') || json.containsKey('videos')) {
      return ApiSourceType.maoApi;
    }

    // 默认 CMS 格式
    return ApiSourceType.cmsCollection;
  }

  // ============================================================
  // 辅助方法
  // ============================================================

  Map<String, dynamic>? _ensureMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }
}
