import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

import '../../models/video_models.dart';
import 'spider_adapter.dart';
import 'spider_models.dart';
import 'tvbox_config_parser.dart';

/// XPath / CSS 选择器蜘蛛适配器
///
/// 基于 TVBox 站点配置，通过 Dio 拉取 HTML 并使用 [html] 包解析。
/// 选择器语法：
/// - `"selector"` 提取元素文本
/// - `"selector@attr"` 提取元素属性
class XpathSpider implements SpiderAdapter {
  final TvBoxSite _site;
  final Dio _dio;
  Map<String, dynamic> _config = {};

  XpathSpider({required TvBoxSite site, Dio? dio})
      : _site = site,
        _dio = dio ?? Dio();

  @override
  String get key => _site.key;

  @override
  String get name => _site.name;

  @override
  SpiderType get type => SpiderType.xpath;

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
    final url = _buildUrl(_config['homeUrl']?.toString() ?? _site.api);
    final doc = await _fetchHtml(url);
    final categories = _parseCategories();
    final items = _extractList(doc, _config['list'] as Map<String, dynamic>?);
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

    final doc = await _fetchHtml(_buildUrl(url));
    final items = _extractList(doc, _config['list'] as Map<String, dynamic>?);
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

    final doc = await _fetchHtml(_buildUrl(url));
    final detail = _extractDetail(doc, id);
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

    final doc = await _fetchHtml(_buildUrl(url));
    final items = _extractList(doc, _config['list'] as Map<String, dynamic>?);
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
    final selector = playConfig['selector']?.toString() ??
        playConfig['url']?.toString() ??
        '';

    if (selector.isEmpty) {
      return SpiderPlayResult(url: id, parse: parseFlag);
    }

    final requestUrl = _buildUrl(id);
    final doc = await _fetchHtml(requestUrl);
    final playUrl = _extractFirstValue(
      doc.documentElement,
      selector,
      baseUrl: requestUrl,
    );

    return SpiderPlayResult(
      url: playUrl,
      parse: parseFlag,
      playUrl: parseFlag == '1' ? playUrl : null,
    );
  }

  @override
  void dispose() {
    _dio.close(force: true);
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

  /// 拉取并解析 HTML 文档
  Future<Document> _fetchHtml(String url) async {
    final response = await _dio.get(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final data = response.data;

    if (data is String) {
      return parse(data);
    }

    if (data is List<int>) {
      return parse(String.fromCharCodes(data));
    }

    return parse(data.toString());
  }

  /// 从文档中提取视频列表
  List<VideoItem> _extractList(Document doc, Map<String, dynamic>? listConfig) {
    if (listConfig == null) return [];

    final containerSelector = listConfig['container']?.toString() ?? '';
    if (containerSelector.isEmpty) return [];

    final fields = listConfig['fields'] as Map<String, dynamic>? ?? {};
    final nodes = doc.querySelectorAll(containerSelector);

    final result = <VideoItem>[];
    for (final node in nodes) {
      final vodId = _extractField(node, fields['vod_id']?.toString() ?? '');
      final vodName = _extractField(node, fields['vod_name']?.toString() ?? '');
      if (vodName.isEmpty) continue;

      result.add(VideoItem(
        vodId: vodId,
        vodName: vodName,
        vodPic: _extractField(node, fields['vod_pic']?.toString() ?? ''),
        vodRemarks: _extractField(node, fields['vod_remarks']?.toString() ?? ''),
        sourceKey: key,
      ));
    }
    return result;
  }

  /// 从文档中提取详情
  VideoDetail _extractDetail(Document doc, String id) {
    final detailConfig = _config['detail'] as Map<String, dynamic>?;
    final fields = (detailConfig?['fields'] as Map<String, dynamic>?) ?? {};

    final playSources = _extractPlaySources(doc);

    final root = doc.documentElement;
    return VideoDetail(
      vodId: id,
      vodName: _extractFirstValue(root, fields['vod_name']?.toString() ?? '')
          .ifEmpty('未知'),
      vodPic: _extractFirstValue(root, fields['vod_pic']?.toString() ?? '')
          .nullIfEmpty,
      vodContent: _extractFirstValue(
              root, fields['vod_content']?.toString() ?? '')
          .nullIfEmpty,
      vodActor: _extractFirstValue(root, fields['vod_actor']?.toString() ?? '')
          .nullIfEmpty,
      vodDirector:
          _extractFirstValue(root, fields['vod_director']?.toString() ?? '')
              .nullIfEmpty,
      sourceKey: key,
      playSources: playSources,
    );
  }

  /// 从详情页提取播放源与选集
  List<PlaySource> _extractPlaySources(Document doc) {
    final playConfig = _config['playUrl'] as Map<String, dynamic>?;
    if (playConfig == null) return [];

    final tabSelector = playConfig['tab']?.toString() ?? '';
    final listSelector = playConfig['list']?.toString() ?? '';
    final nameSelector = playConfig['name']?.toString() ?? '';
    final urlSelector = playConfig['url']?.toString() ?? '';

    if (tabSelector.isEmpty || listSelector.isEmpty) return [];

    final tabs = doc.querySelectorAll(tabSelector);
    final sources = <PlaySource>[];

    for (final tab in tabs) {
      final sourceName = tab.text.trim();
      final episodes = <VideoEpisode>[];

      // listSelector 优先在 tab 上下文内查找，未命中则在文档范围内查找
      var items = tab.querySelectorAll(listSelector);
      if (items.isEmpty) {
        items = doc.querySelectorAll(listSelector);
      }

      for (final item in items) {
        final name = _extractField(item, nameSelector);
        final url = _extractField(item, urlSelector);
        if (name.isNotEmpty && url.isNotEmpty) {
          episodes.add(VideoEpisode(name: name, url: url));
        }
      }

      if (episodes.isNotEmpty) {
        sources.add(PlaySource(
          name: sourceName.isEmpty ? '默认源' : sourceName,
          episodes: episodes,
        ));
      }
    }

    return sources;
  }

  /// 在节点上按选择器提取字段值
  String _extractField(Element root, String rawSelector) {
    if (rawSelector.isEmpty) return '';
    return _extractFirstValue(root, rawSelector);
  }

  /// 解析选择器并提取首个匹配值
  ///
  /// 选择器支持 `"selector"` 和 `"selector@attr"` 两种形式。
  /// 当选择器未包含 `@` 时，依次尝试 `src`、`href` 属性，最后取文本。
  String _extractFirstValue(Element? root, String rawSelector,
      {String? baseUrl}) {
    if (root == null || rawSelector.isEmpty) return '';

    final (selector, attr) = _parseSelector(rawSelector);
    if (selector.isEmpty) return '';

    final element = root.querySelector(selector);
    if (element == null) return '';

    String value;
    if (attr != null) {
      value = element.attributes[attr] ?? '';
    } else {
      value = element.attributes['src'] ??
          element.attributes['href'] ??
          element.text.trim();
    }

    return baseUrl != null && value.isNotEmpty
        ? _resolveUrl(value, baseUrl)
        : value;
  }

  /// 解析选择器字符串
  (String selector, String? attr) _parseSelector(String raw) {
    final atIndex = raw.lastIndexOf('@');
    if (atIndex == -1) return (raw, null);
    return (raw.substring(0, atIndex), raw.substring(atIndex + 1));
  }

  /// 处理 URL：为空或协议头缺失时补充 site.api 作为 base
  String _buildUrl(String url) {
    if (url.trim().isEmpty) return _site.api;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = _site.api;
    if (base.endsWith('/')) {
      return url.startsWith('/') ? '$base${url.substring(1)}' : '$base$url';
    }
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  /// 将相对 URL 转为绝对 URL
  String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = Uri.tryParse(baseUrl);
    if (base == null) return url;
    final resolved = base.resolve(url);
    return resolved.toString();
  }
}

extension _StringX on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
  String? get nullIfEmpty => isEmpty ? null : this;
}
