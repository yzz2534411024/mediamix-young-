# Dart 原生蜘蛛引擎框架 + 视频解析增强 设计文档

> 日期: 2026-06-18
> 状态: 已批准

## 1. 背景与目标

### 1.1 当前问题

- 饭太硬接口 (`http://www.xn--sss604efuw.net/tv`) 返回 TVBox 配置格式 JSON，包含 `spider`、`sites`、`lives`、`flags` 等字段
- 当前 APP 仅解析了 `sites` 数组中的 CMS 站点，**无法加载和执行 `spider` 蜘蛛源**
- TVBox 蜘蛛是 JAR 插件，通过 DexClassLoader 动态加载，Flutter/Dart 环境无法直接执行
- 视频解析接口数量有限，缺少 jlk、exo 等常用解析

### 1.2 目标

1. **通用蜘蛛框架**: 在 Dart 层实现 TVBox 蜘蛛的接口协议，支持任意 TVBox 配置中的 spider 字段
2. **饭太硬接口可用**: 让 APP 能完整解析饭太硬返回的 TVBox 配置，提取并使用蜘蛛源数据
3. **视频解析增强**: 增加 jlk、exo 等视频解析接口

## 2. 架构设计

### 2.1 整体架构

```
TVBox配置URL → TvBoxConfigParser → TvBoxConfig
                                        ↓
                              SpiderRegistry.createFromSite()
                                        ↓
                              SpiderAdapter 实例
                                        ↓
              homeContent / categoryContent / detailContent / searchContent / playerContent
                                        ↓
                    统一转为 VideoItem / VideoDetail / PlaySource
                                        ↓
                              现有 Provider 层（最小改动）
```

### 2.2 核心组件

#### 2.2.1 SpiderAdapter 接口

```dart
/// 蜘蛛类型
enum SpiderType {
  cms,    // 标准CMS采集站（已有实现）
  xpath,  // XPath爬虫
  json,   // JSON API爬虫
  site,   // 自定义站点爬虫
}

/// 蜘蛛适配器接口 — 所有蜘蛛实现此接口
abstract class SpiderAdapter {
  String get key;
  String get name;
  SpiderType get type;

  /// 初始化（加载站点配置）
  Future<void> init(Map<String, dynamic> config);

  /// 首页推荐内容
  Future<SpiderHomeResult> homeContent({int page = 1});

  /// 分类内容
  Future<SpiderListResult> categoryContent({
    required String tid,
    int page = 1,
    Map<String, String>? filter,
  });

  /// 影片详情
  Future<SpiderDetailResult> detailContent({required String id});

  /// 搜索
  Future<SpiderListResult> searchContent({
    required String keyword,
    int page = 1,
  });

  /// 播放地址解析（蜘蛛源关键方法：获取真实播放URL）
  Future<SpiderPlayResult> playerContent({
    required String flag,
    required String id,
  });

  /// 是否支持手动搜索（某些蜘蛛不支持）
  bool get isSearchSupported => true;

  /// 释放资源
  void dispose() {}
}
```

#### 2.2.2 蜘蛛结果模型

```dart
/// 首页推荐结果
class SpiderHomeResult {
  final List<SpiderCategory> categories;  // 分类列表
  final List<VideoItem> recommend;        // 推荐影片
  final Map<String, List<VideoItem>>? classList; // 按分类推荐
}

/// 列表结果
class SpiderListResult {
  final List<VideoItem> list;
  final int page;
  final int pageCount;
  final int total;
}

/// 详情结果
class SpiderDetailResult {
  final VideoDetail detail;
}

/// 播放结果
class SpiderPlayResult {
  final String url;            // 播放URL
  final Map<String, String>? headers;  // 请求头（如Referer）
  final String? parse;         // 是否需要二次解析 (0/1)
  final String? playUrl;       // 解析URL（如需二次解析）
}

/// 蜘蛛分类
class SpiderCategory {
  final String typeId;
  final String typeName;
  final List<SpiderFilter>? filters; // 筛选条件
}

/// 筛选条件
class SpiderFilter {
  final String key;
  final String name;
  final List<SpiderFilterValue> values;
}

class SpiderFilterValue {
  final String value;
  final String name;
}
```

#### 2.2.3 TVBox 配置解析器

```dart
/// TVBox 配置模型
class TvBoxConfig {
  final String? spiderUrl;                    // spider JAR URL
  final List<TvBoxSite> sites;                // 站点列表
  final List<TvBoxLive> lives;                // 直播源
  final List<String> flags;                   // 播放标识白名单

  const TvBoxConfig({
    this.spiderUrl,
    this.sites = const [],
    this.lives = const [],
    this.flags = const [],
  });
}

/// TVBox 站点配置
class TvBoxSite {
  final String key;           // 站点唯一标识
  final String name;          // 站点名称
  final int type;             // 站点类型: 0=CMS, 1=JSON, 3=XPath
  final String api;           // API地址
  final String? ext;          // 扩展配置（JSON字符串或URL）
  final String? jar;          // JAR包URL（蜘蛛源标识）
  final String? playerType;   // 播放器类型: 0=系统, 1=IJK, 2=EXO
  final Map<String, dynamic>? extData; // 解析后的ext数据
}

/// TVBox 直播源
class TvBoxLive {
  final String name;
  final String type;  // 0=文本, 1=网页
  final String url;
  final String? playerType;
}

class TvBoxConfigParser {
  /// 解析 TVBox 配置 JSON
  TvBoxConfig parse(Map<String, dynamic> json) {
    // 解析 spider 字段（格式: "jar_url;md5" 或 "jar_url"）
    String? spiderUrl;
    if (json['spider'] is String) {
      spiderUrl = (json['spider'] as String).split(';').first;
    }

    // 解析 sites
    final sites = <TvBoxSite>[];
    for (final s in (json['sites'] as List?) ?? []) {
      if (s is Map<String, dynamic>) {
        sites.add(TvBoxSite(
          key: s['key'] ?? '',
          name: s['name'] ?? '',
          type: s['type'] ?? 0,
          api: s['api'] ?? '',
          ext: s['ext']?.toString(),
          jar: s['jar']?.toString(),
          playerType: s['playerType']?.toString(),
        ));
      }
    }

    // 解析 lives
    final lives = <TvBoxLive>[];
    for (final l in (json['lives'] as List?) ?? []) {
      if (l is Map<String, dynamic>) {
        lives.add(TvBoxLive(
          name: l['name'] ?? '',
          type: l['type']?.toString() ?? '0',
          url: l['url'] ?? '',
          playerType: l['playerType']?.toString(),
        ));
      }
    }

    // 解析 flags
    final flags = <String>[];
    if (json['flags'] is List) {
      flags.addAll((json['flags'] as List).map((e) => e.toString()));
    }

    return TvBoxConfig(
      spiderUrl: spiderUrl,
      sites: sites,
      lives: lives,
      flags: flags,
    );
  }
}
```

#### 2.2.4 蜘蛛注册表

```dart
class SpiderRegistry {
  static final SpiderRegistry _instance = SpiderRegistry._();
  factory SpiderRegistry() => _instance;
  SpiderRegistry._();

  /// 内置蜘蛛工厂映射（key → SpiderAdapter 创建函数）
  final Map<String, SpiderAdapter Function(Map<String, dynamic>)> _factories = {};

  /// 已初始化的蜘蛛实例缓存
  final Map<String, SpiderAdapter> _instances = {};

  /// 注册内置蜘蛛工厂
  void register(String key, SpiderAdapter Function(Map<String, dynamic>) factory) {
    _factories[key] = factory;
  }

  /// 根据 TVBox site 配置创建蜘蛛
  Future<SpiderAdapter?> createFromSite(TvBoxSite site) async {
    // 1. 检查是否有内置实现
    if (_factories.containsKey(site.key)) {
      final spider = _factories[site.key]!({});
      await spider.init(_parseExt(site.ext));
      _instances[site.key] = spider;
      return spider;
    }

    // 2. 根据 type 自动创建
    SpiderAdapter? spider;
    switch (site.type) {
      case 0:
        spider = CmsSpider(site);
        break;
      case 1:
        spider = JsonSpider(site);
        break;
      case 3:
        spider = XpathSpider(site);
        break;
      default:
        // 未知类型，尝试CMS兼容
        spider = CmsSpider(site);
    }

    if (spider != null) {
      await spider.init(_parseExt(site.ext));
      _instances[site.key] = spider;
    }
    return spider;
  }

  /// 获取已创建的蜘蛛实例
  SpiderAdapter? get(String key) => _instances[key];

  /// 解析 ext 字段
  Map<String, dynamic> _parseExt(String? ext) {
    if (ext == null || ext.isEmpty) return {};
    if (ext.startsWith('http')) return {'extUrl': ext};
    try {
      return jsonDecode(ext) as Map<String, dynamic>;
    } catch (_) {
      return {'ext': ext};
    }
  }

  /// 释放所有蜘蛛
  void disposeAll() {
    for (final spider in _instances.values) {
      spider.dispose();
    }
    _instances.clear();
  }
}
```

#### 2.2.5 内置蜘蛛实现

**CmsSpider** — 标准CMS采集站（复用现有 VideoApiService 逻辑）

```dart
class CmsSpider extends SpiderAdapter {
  final TvBoxSite _site;
  final VideoApiService _api;

  CmsSpider(this._site) : _api = VideoApiService();

  @override
  String get key => _site.key;
  @override
  String get name => _site.name;
  @override
  SpiderType get type => SpiderType.cms;

  @override
  Future<void> init(Map<String, dynamic> config) async {}

  @override
  Future<SpiderHomeResult> homeContent({int page = 1}) async {
    final categories = await _api.fetchCategories(_site.api);
    final list = await _api.fetchVideoList(_site.api, page: page);
    return SpiderHomeResult(
      categories: categories.map((c) => SpiderCategory(
        typeId: c.typeId.toString(),
        typeName: c.typeName,
      )).toList(),
      recommend: list.list,
    );
  }

  @override
  Future<SpiderListResult> categoryContent({
    required String tid, int page = 1, Map<String, String>? filter,
  }) async {
    final response = await _api.fetchVideoList(
      _site.api,
      page: page,
      typeId: int.tryParse(tid),
    );
    return SpiderListResult(
      list: response.list,
      page: response.page,
      pageCount: response.pageCount,
      total: response.total,
    );
  }

  @override
  Future<SpiderDetailResult> detailContent({required String id}) async {
    final detail = await _api.fetchVideoDetail(_site.api, id, sourceKey: key);
    return SpiderDetailResult(detail: detail);
  }

  @override
  Future<SpiderListResult> searchContent({
    required String keyword, int page = 1,
  }) async {
    final response = await _api.searchVideos(_site.api, keyword);
    return SpiderListResult(
      list: response.list,
      page: response.page,
      pageCount: response.pageCount,
      total: response.total,
    );
  }

  @override
  Future<SpiderPlayResult> playerContent({
    required String flag, required String id,
  }) async {
    // CMS源播放URL直接可用
    return SpiderPlayResult(url: id);
  }
}
```

**XpathSpider** — XPath 爬虫（需 html 解析库）

```dart
class XpathSpider extends SpiderAdapter {
  final TvBoxSite _site;
  Map<String, dynamic> _config = {};

  XpathSpider(this._site);

  @override
  String get key => _site.key;
  @override
  String get name => _site.name;
  @override
  SpiderType get type => SpiderType.xpath;

  @override
  Future<void> init(Map<String, dynamic> config) async {
    _config = config;
    // 如果 ext 是 URL，先获取远程配置
    if (config.containsKey('extUrl')) {
      final dio = Dio();
      final resp = await dio.get(config['extUrl']);
      _config = resp.data is Map<String, dynamic>
          ? resp.data
          : jsonDecode(resp.data);
    }
  }

  /// XPath 配置格式示例:
  /// {
  ///   "homeUrl": "https://example.com",
  ///   "cateUrl": "https://example.com/type/{tid}/{page}.html",
  ///   "detailUrl": "https://example.com/detail/{id}.html",
  ///   "searchUrl": "https://example.com/search?q={wd}&page={pg}",
  ///   "categories": [{"id":"1","name":"电影"}, ...],
  ///   "list": { "vod_name": "//div[@class='name']/text()", ... },
  ///   "detail": { "vod_content": "//div[@class='desc']/text()", ... },
  ///   "playUrl": { "parse": 0, "url": "//iframe/@src" }
  /// }

  @override
  Future<SpiderHomeResult> homeContent({int page = 1}) async {
    final url = _config['homeUrl'] ?? _site.api;
    final html = await _fetchHtml(url);
    final doc = parse(html);

    final categories = _parseCategories();
    final items = _parseList(doc, _config['list'] ?? {});

    return SpiderHomeResult(categories: categories, recommend: items);
  }

  @override
  Future<SpiderListResult> categoryContent({
    required String tid, int page = 1, Map<String, String>? filter,
  }) async {
    var url = (_config['cateUrl'] ?? '').toString()
        .replaceAll('{tid}', tid)
        .replaceAll('{pg}', page.toString());
    if (url.isEmpty) url = _site.api;

    final html = await _fetchHtml(url);
    final doc = parse(html);
    final items = _parseList(doc, _config['list'] ?? {});

    return SpiderListResult(list: items, page: page, pageCount: 1, total: items.length);
  }

  @override
  Future<SpiderDetailResult> detailContent({required String id}) async {
    var url = (_config['detailUrl'] ?? '').toString().replaceAll('{id}', id);
    if (url.isEmpty) url = id;

    final html = await _fetchHtml(url);
    final doc = parse(html);
    final detail = _parseDetail(doc, id);

    return SpiderDetailResult(detail: detail);
  }

  @override
  Future<SpiderListResult> searchContent({
    required String keyword, int page = 1,
  }) async {
    var url = (_config['searchUrl'] ?? '').toString()
        .replaceAll('{wd}', Uri.encodeComponent(keyword))
        .replaceAll('{pg}', page.toString());
    if (url.isEmpty) return const SpiderListResult(list: [], page: 1, pageCount: 1, total: 0);

    final html = await _fetchHtml(url);
    final doc = parse(html);
    final items = _parseList(doc, _config['list'] ?? {});

    return SpiderListResult(list: items, page: page, pageCount: 1, total: items.length);
  }

  @override
  Future<SpiderPlayResult> playerContent({
    required String flag, required String id,
  }) async {
    final playConfig = _config['playUrl'] ?? {};
    final parseFlag = playConfig['parse'] ?? 0;

    // 如果需要从页面提取播放URL
    if (playConfig.containsKey('url')) {
      final html = await _fetchHtml(id);
      final doc = parse(html);
      final playUrl = _evalXPath(doc, playConfig['url']);
      return SpiderPlayResult(
        url: playUrl,
        parse: parseFlag.toString(),
        playUrl: parseFlag == 1 ? playUrl : null,
      );
    }

    // 直接返回URL
    return SpiderPlayResult(url: id, parse: parseFlag.toString());
  }

  // --- 辅助方法 ---

  Future<String> _fetchHtml(String url) async {
    final dio = Dio();
    final resp = await dio.get(url, options: Options(
      responseType: ResponseType.plain,
      headers: {'User-Agent': 'Mozilla/5.0'},
    ));
    return resp.data.toString();
  }

  List<SpiderCategory> _parseCategories() {
    final cats = _config['categories'] as List? ?? [];
    return cats.map((c) {
      final m = c as Map<String, dynamic>;
      return SpiderCategory(typeId: m['id'].toString(), typeName: m['name'].toString());
    }).toList();
  }

  List<VideoItem> _parseList(Document doc, Map<String, dynamic> rules) {
    // 根据XPath规则提取列表数据
    // rules 格式: { "vod_name": "//xpath", "vod_id": "//xpath/@href", ... }
    // 实现根据具体站点配置的XPath规则进行DOM查询
    final items = <VideoItem>[];
    // 查找列表容器，遍历子元素，对每个子元素应用规则
    // 具体实现依赖 html 包的 XPath 查询能力
    return items;
  }

  VideoDetail _parseDetail(Document doc, String id) {
    final rules = _config['detail'] ?? {};
    // 根据XPath规则提取详情数据
    return VideoDetail(
      vodId: id,
      vodName: _evalXPath(doc, rules['vod_name']),
      vodPic: _evalXPath(doc, rules['vod_pic']),
      vodContent: _evalXPath(doc, rules['vod_content']),
      vodActor: _evalXPath(doc, rules['vod_actor']),
      vodDirector: _evalXPath(doc, rules['vod_director']),
      sourceKey: key,
      playSources: _parsePlaySources(doc, rules),
    );
  }

  String _evalXPath(Document doc, dynamic xpath) {
    if (xpath == null) return '';
    // 使用 html 包的 querySelector 或 XPath 求值
    // 返回匹配节点的文本内容或属性值
    return '';
  }

  List<PlaySource> _parsePlaySources(Document doc, Map<String, dynamic> rules) {
    // 解析播放源和剧集列表
    return [];
  }
}
```

**JsonSpider** — JSON API 爬虫

```dart
class JsonSpider extends SpiderAdapter {
  final TvBoxSite _site;
  Map<String, dynamic> _config = {};

  JsonSpider(this._site);

  @override
  String get key => _site.key;
  @override
  String get name => _site.name;
  @override
  SpiderType get type => SpiderType.json;

  @override
  Future<void> init(Map<String, dynamic> config) async {
    _config = config;
    if (config.containsKey('extUrl')) {
      final dio = Dio();
      final resp = await dio.get(config['extUrl']);
      _config = resp.data is Map<String, dynamic>
          ? resp.data
          : jsonDecode(resp.data);
    }
  }

  /// JSON 配置格式示例:
  /// {
  ///   "homeUrl": "https://api.example.com/home",
  ///   "cateUrl": "https://api.example.com/list?type={tid}&page={pg}",
  ///   "detailUrl": "https://api.example.com/detail/{id}",
  ///   "searchUrl": "https://api.example.com/search?wd={wd}",
  ///   "categories": [{"id":"1","name":"电影"}, ...],
  ///   "listPath": "$.data.list",          // JSONPath 到列表
  ///   "detailPath": "$.data",             // JSONPath 到详情
  ///   "fieldMap": {                       // 字段映射
  ///     "vod_name": "title",
  ///     "vod_id": "id",
  ///     "vod_pic": "cover"
  ///   }
  /// }

  @override
  Future<SpiderHomeResult> homeContent({int page = 1}) async {
    final url = _config['homeUrl'] ?? _site.api;
    final data = await _fetchJson(url);
    final categories = _parseCategories();
    final items = _extractList(data, _config['listPath'] ?? '');
    return SpiderHomeResult(categories: categories, recommend: items);
  }

  @override
  Future<SpiderListResult> categoryContent({
    required String tid, int page = 1, Map<String, String>? filter,
  }) async {
    var url = (_config['cateUrl'] ?? '').toString()
        .replaceAll('{tid}', tid)
        .replaceAll('{pg}', page.toString());
    if (url.isEmpty) url = _site.api;

    final data = await _fetchJson(url);
    final items = _extractList(data, _config['listPath'] ?? '');
    return SpiderListResult(list: items, page: page, pageCount: 1, total: items.length);
  }

  @override
  Future<SpiderDetailResult> detailContent({required String id}) async {
    var url = (_config['detailUrl'] ?? '').toString().replaceAll('{id}', id);
    if (url.isEmpty) url = id;

    final data = await _fetchJson(url);
    final detail = _extractDetail(data, id);
    return SpiderDetailResult(detail: detail);
  }

  @override
  Future<SpiderListResult> searchContent({
    required String keyword, int page = 1,
  }) async {
    var url = (_config['searchUrl'] ?? '').toString()
        .replaceAll('{wd}', Uri.encodeComponent(keyword))
        .replaceAll('{pg}', page.toString());
    if (url.isEmpty) return const SpiderListResult(list: [], page: 1, pageCount: 1, total: 0);

    final data = await _fetchJson(url);
    final items = _extractList(data, _config['listPath'] ?? '');
    return SpiderListResult(list: items, page: page, pageCount: 1, total: items.length);
  }

  @override
  Future<SpiderPlayResult> playerContent({
    required String flag, required String id,
  }) async {
    final playConfig = _config['playUrl'] ?? {};
    final parseFlag = playConfig['parse'] ?? 0;

    if (playConfig.containsKey('urlPath')) {
      final data = await _fetchJson(id);
      final playUrl = _extractField(data, playConfig['urlPath']);
      return SpiderPlayResult(
        url: playUrl,
        parse: parseFlag.toString(),
        playUrl: parseFlag == 1 ? playUrl : null,
      );
    }

    return SpiderPlayResult(url: id, parse: parseFlag.toString());
  }

  // --- 辅助方法 ---

  Future<Map<String, dynamic>> _fetchJson(String url) async {
    final dio = Dio();
    final resp = await dio.get(url);
    if (resp.data is Map<String, dynamic>) return resp.data;
    return jsonDecode(resp.data.toString());
  }

  List<SpiderCategory> _parseCategories() {
    final cats = _config['categories'] as List? ?? [];
    return cats.map((c) {
      final m = c as Map<String, dynamic>;
      return SpiderCategory(typeId: m['id'].toString(), typeName: m['name'].toString());
    }).toList();
  }

  List<VideoItem> _extractList(Map<String, dynamic> data, String jsonPath) {
    // 使用 JSONPath 或手动路径解析提取列表
    // jsonPath 格式: "$.data.list" → data['data']['list']
    final segments = jsonPath.replaceAll('\$', '').split('.')..removeWhere((s) => s.isEmpty);
    dynamic current = data;
    for (final seg in segments) {
      if (current is Map<String, dynamic>) {
        current = current[seg];
      } else {
        return [];
      }
    }
    if (current is! List) return [];

    final fieldMap = _config['fieldMap'] as Map<String, dynamic>? ?? {};
    return current.map((item) {
      final m = item as Map<String, dynamic>;
      return VideoItem(
        vodId: _mapField(m, 'vod_id', fieldMap).toString(),
        vodName: _mapField(m, 'vod_name', fieldMap).toString(),
        vodPic: _mapField(m, 'vod_pic', fieldMap),
        vodRemarks: _mapField(m, 'vod_remarks', fieldMap),
        sourceKey: key,
      );
    }).toList();
  }

  String? _mapField(Map<String, dynamic> m, String vodField, Map<String, dynamic> fieldMap) {
    final apiKey = fieldMap[vodField] ?? vodField;
    return m[apiKey]?.toString();
  }

  VideoDetail _extractDetail(Map<String, dynamic> data, String id) {
    final detailPath = _config['detailPath'] ?? '';
    var detail = data;
    if (detailPath.isNotEmpty) {
      final segments = detailPath.replaceAll('\$', '').split('.')..removeWhere((s) => s.isEmpty);
      for (final seg in segments) {
        if (detail is Map<String, dynamic>) detail = detail[seg];
      }
    }
    if (detail is! Map<String, dynamic>) {
      return VideoDetail(vodId: id, vodName: '未知', sourceKey: key);
    }

    final fieldMap = _config['fieldMap'] as Map<String, dynamic>? ?? {};
    return VideoDetail(
      vodId: _mapField(detail, 'vod_id', fieldMap) ?? id,
      vodName: _mapField(detail, 'vod_name', fieldMap) ?? '未知',
      vodPic: _mapField(detail, 'vod_pic', fieldMap),
      vodContent: _mapField(detail, 'vod_content', fieldMap),
      vodActor: _mapField(detail, 'vod_actor', fieldMap),
      vodDirector: _mapField(detail, 'vod_director', fieldMap),
      sourceKey: key,
      playSources: _extractPlaySources(detail),
    );
  }

  List<PlaySource> _extractPlaySources(Map<String, dynamic> detail) {
    // 从详情数据中提取播放源
    final fieldMap = _config['fieldMap'] as Map<String, dynamic>? ?? {};
    final playFromKey = fieldMap['vod_play_from'] ?? 'vod_play_from';
    final playUrlKey = fieldMap['vod_play_url'] ?? 'vod_play_url';

    final vodPlayFrom = detail[playFromKey]?.toString() ?? '';
    final vodPlayUrl = detail[playUrlKey]?.toString() ?? '';

    // 复用 VideoDetail.fromJson 中的播放源解析逻辑
    if (vodPlayFrom.isEmpty || vodPlayUrl.isEmpty) return [];

    final sources = <PlaySource>[];
    final fromNames = vodPlayFrom.split('\$\$\$');
    final fromUrls = vodPlayUrl.split('\$\$\$');

    for (int i = 0; i < fromNames.length && i < fromUrls.length; i++) {
      final episodes = <VideoEpisode>[];
      final lines = fromUrls[i].trim().split('#');
      for (final line in lines) {
        final parts = line.split('\$');
        if (parts.length >= 2) {
          episodes.add(VideoEpisode(name: parts[0].trim(), url: parts[1].trim()));
        }
      }
      if (episodes.isNotEmpty) {
        sources.add(PlaySource(name: fromNames[i].trim(), episodes: episodes));
      }
    }
    return sources;
  }

  String _extractField(Map<String, dynamic> data, String jsonPath) {
    final segments = jsonPath.replaceAll('\$', '').split('.')..removeWhere((s) => s.isEmpty);
    dynamic current = data;
    for (final seg in segments) {
      if (current is Map<String, dynamic>) {
        current = current[seg];
      } else {
        return '';
      }
    }
    return current?.toString() ?? '';
  }
}
```

### 2.3 数据源模型扩展

将 `CmsApiSite` 扩展为统一的 `VideoSource`，兼容 CMS 站点和蜘蛛源：

```dart
/// 视频源（统一 CMS 站点和蜘蛛源）
class VideoSource {
  final String key;
  final String name;
  final String apiUrl;
  final bool enabled;
  final bool isBuiltIn;
  final SourceType sourceType;  // 新增：源类型
  final String? spiderKey;      // 新增：关联的蜘蛛key
  final int? playerType;        // 新增：播放器类型 (0=系统, 1=IJK, 2=EXO)

  enum SourceType {
    cms,      // 标准CMS采集站
    spider,   // 蜘蛛源
  }
}
```

**迁移策略：**

- `CmsApiSite` 保留为兼容层，内部转为 `VideoSource(sourceType: SourceType.cms)`
- 所有 Provider 层逐步从 `CmsApiSite` 迁移到 `VideoSource`
- `defaultSites` 中的 CMS 站点自动转为 `VideoSource(sourceType: SourceType.cms)`
- TVBox 配置中的蜘蛛站点转为 `VideoSource(sourceType: SourceType.spider, spiderKey: site.key)`
- 迁移期间 `CmsApiSite.defaultSites` 仍然可用，通过扩展方法 `toVideoSource()` 转换

### 2.4 与现有架构的集成

#### 2.4.1 VideoApiService 扩展

```dart
class VideoApiService {
  // 现有方法保持不变...

  // 新增：获取 TVBox 配置
  Future<TvBoxConfig> fetchTvBoxConfig(String configUrl) async {
    final response = await _dio.get(configUrl);
    final data = _extractJson(response);
    return TvBoxConfigParser().parse(data);
  }

  // 新增：通过蜘蛛获取首页内容
  Future<SpiderHomeResult> fetchSpiderHome(SpiderAdapter spider) {
    return spider.homeContent();
  }

  // 新增：通过蜘蛛获取分类内容
  Future<SpiderListResult> fetchSpiderCategory(
    SpiderAdapter spider, {
    required String tid,
    int page = 1,
  }) {
    return spider.categoryContent(tid: tid, page: page);
  }

  // 新增：通过蜘蛛获取详情
  Future<SpiderDetailResult> fetchSpiderDetail(
    SpiderAdapter spider, {
    required String id,
  }) {
    return spider.detailContent(id: id);
  }

  // 新增：通过蜘蛛搜索
  Future<SpiderListResult> fetchSpiderSearch(
    SpiderAdapter spider, {
    required String keyword,
  }) {
    return spider.searchContent(keyword: keyword);
  }

  // 新增：通过蜘蛛解析播放地址
  Future<SpiderPlayResult> fetchSpiderPlay(
    SpiderAdapter spider, {
    required String flag,
    required String id,
  }) {
    return spider.playerContent(flag: flag, id: id);
  }
}
```

#### 2.4.2 Provider 层适配

- `cmsSiteListProvider` → `videoSourceListProvider`（兼容 CMS + 蜘蛛源）
- `currentSiteProvider` → `currentSourceProvider`
- 搜索/详情 Provider 根据源类型选择 CMS API 或蜘蛛方法
- 新增 `spiderRegistryProvider` 管理蜘蛛实例

#### 2.4.3 播放器适配

蜘蛛源的 `playerContent` 返回的 URL 可能需要特殊处理：
- 带 headers 的播放请求（Referer、User-Agent 等）
- 需要二次解析的 URL（`parse = "1"` 时走 VideoParser）
- 不同 playerType 选择不同播放器引擎

### 2.5 视频解析增强

在 `VideoParser.defaultParsers` 中新增：

```dart
VideoParser(key: 'jlk', name: 'JLK解析', urlTemplate: 'https://jlk.jianghu.vip/?url={url}'),
// exo 等其他解析接口根据实际可用性添加
```

## 3. 文件结构

```
lib/features/video/
├── models/
│   ├── video_models.dart          # 扩展 VideoSource、SpiderPlayResult 等
│   └── spider_models.dart         # 新增：蜘蛛相关模型
├── services/
│   ├── tbox_api_service.dart      # 扩展：TVBox配置获取、蜘蛛方法代理
│   ├── api_adapter.dart           # 保持不变
│   └── spider/                    # 新增：蜘蛛引擎目录
│       ├── spider_adapter.dart    # 蜘蛛接口定义
│       ├── spider_registry.dart   # 蜘蛛注册表
│       ├── tvbox_config_parser.dart # TVBox配置解析
│       ├── cms_spider.dart        # CMS蜘蛛实现
│       ├── xpath_spider.dart      # XPath蜘蛛实现
│       ├── json_spider.dart       # JSON蜘蛛实现
│       └── builtins/              # 内置蜘蛛实现
│           └── ...                 # 特定站点的蜘蛛实现
├── providers/
│   └── video_providers.dart       # 适配蜘蛛源
└── pages/
    └── ...                         # UI 层面小改
```

## 4. 依赖

- `html` 包: HTML DOM 解析（XPath 蜘蛛需要）
- 现有 `dio` 包: HTTP 请求
- 现有 `logger` 包: 日志

## 5. 实施优先级

1. **P0**: SpiderAdapter 接口 + TvBoxConfigParser + CmsSpider（让饭太硬 sites 可用）
2. **P1**: SpiderRegistry + Provider 层适配 + 播放器适配
3. **P2**: XpathSpider + JsonSpider 实现
4. **P3**: 视频解析增强（jlk/exo 等）
5. **P4**: 内置特定站点蜘蛛实现

## 6. 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 饭太硬接口变更或不可用 | 保留 Vercel 代理方案作为备用 |
| XPath 蜘蛛配置复杂 | 先支持 CMS 和 JSON 类型，XPath 后续迭代 |
| 蜘蛛源播放需要特殊 headers | playerContent 返回 headers，播放器层适配 |
| 新蜘蛛需要手动实现 | 设计可扩展的 SpiderAdapter 接口，降低实现成本 |
