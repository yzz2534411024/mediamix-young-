# Dart 原生蜘蛛引擎框架 + 视频解析增强 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Flutter APP 中实现通用蜘蛛引擎框架，支持解析 TVBox 配置中的蜘蛛源，让饭太硬等接口完整可用，同时增强视频解析接口。

**Architecture:** 纯 Dart 实现蜘蛛引擎，通过 SpiderAdapter 抽象接口统一 CMS/XPath/JSON 三种蜘蛛类型，SpiderRegistry 管理蜘蛛实例生命周期，TvBoxConfigParser 解析 TVBox 配置 JSON，Provider 层根据源类型路由到 CMS API 或蜘蛛方法。

**Tech Stack:** Flutter/Dart, Dio (HTTP), html (DOM解析), Riverpod (状态管理)

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `lib/features/video/services/spider/spider_adapter.dart` | 蜘蛛适配器抽象接口 + 蜘蛛类型枚举 |
| Create | `lib/features/video/services/spider/spider_models.dart` | 蜘蛛结果模型（SpiderHomeResult/SpiderListResult/SpiderDetailResult/SpiderPlayResult/SpiderCategory/SpiderFilter） |
| Create | `lib/features/video/services/spider/tvbox_config_parser.dart` | TVBox 配置解析器 + TvBoxConfig/TvBoxSite/TvBoxLive 模型 |
| Create | `lib/features/video/services/spider/spider_registry.dart` | 蜘蛛注册表（工厂注册、实例缓存、自动创建） |
| Create | `lib/features/video/services/spider/cms_spider.dart` | CMS 蜘蛛实现（复用 VideoApiService） |
| Create | `lib/features/video/services/spider/xpath_spider.dart` | XPath 蜘蛛实现（HTML DOM 解析） |
| Create | `lib/features/video/services/spider/json_spider.dart` | JSON 蜘蛛实现（JSONPath + 字段映射） |
| Create | `lib/features/video/services/spider/spider_service.dart` | 蜘蛛服务门面（统一入口，封装 Registry + 代理方法） |
| Modify | `lib/features/video/models/video_models.dart` | 扩展 VideoSource 模型 + VideoParser 新增解析接口 |
| Modify | `lib/features/video/services/tbox_api_service.dart` | 新增 fetchTvBoxConfig 方法 |
| Modify | `lib/features/video/providers/video_providers.dart` | 适配蜘蛛源 Provider |
| Create | `test/features/video/services/spider/spider_models_test.dart` | 蜘蛛模型单元测试 |
| Create | `test/features/video/services/spider/tvbox_config_parser_test.dart` | TVBox 配置解析测试 |
| Create | `test/features/video/services/spider/cms_spider_test.dart` | CMS 蜘蛛测试 |
| Create | `test/features/video/services/spider/json_spider_test.dart` | JSON 蜘蛛测试 |
| Create | `test/features/video/services/spider/spider_registry_test.dart` | 蜘蛛注册表测试 |

---

### Task 1: 蜘蛛模型定义

**Files:**
- Create: `lib/features/video/services/spider/spider_models.dart`
- Create: `test/features/video/services/spider/spider_models_test.dart`

- [ ] **Step 1: 创建蜘蛛模型文件**

```dart
// lib/features/video/services/spider/spider_models.dart
import '../../models/video_models.dart';

/// 蜘蛛类型
enum SpiderType {
  cms,    // 标准CMS采集站
  xpath,  // XPath爬虫
  json,   // JSON API爬虫
  site,   // 自定义站点爬虫
}

/// 首页推荐结果
class SpiderHomeResult {
  final List<SpiderCategory> categories;
  final List<VideoItem> recommend;
  final Map<String, List<VideoItem>>? classList;

  const SpiderHomeResult({
    this.categories = const [],
    this.recommend = const [],
    this.classList,
  });
}

/// 列表结果
class SpiderListResult {
  final List<VideoItem> list;
  final int page;
  final int pageCount;
  final int total;

  const SpiderListResult({
    this.list = const [],
    this.page = 1,
    this.pageCount = 1,
    this.total = 0,
  });
}

/// 详情结果
class SpiderDetailResult {
  final VideoDetail? detail;

  const SpiderDetailResult({this.detail});
}

/// 播放结果
class SpiderPlayResult {
  final String url;
  final Map<String, String>? headers;
  final String? parse;       // "0"=直连, "1"=需二次解析
  final String? playUrl;     // 二次解析URL

  const SpiderPlayResult({
    this.url = '',
    this.headers,
    this.parse,
    this.playUrl,
  });

  bool get needsParse => parse == '1';
}

/// 蜘蛛分类
class SpiderCategory {
  final String typeId;
  final String typeName;
  final List<SpiderFilter>? filters;

  const SpiderCategory({
    required this.typeId,
    required this.typeName,
    this.filters,
  });
}

/// 筛选条件
class SpiderFilter {
  final String key;
  final String name;
  final List<SpiderFilterValue> values;

  const SpiderFilter({required this.key, required this.name, required this.values});
}

/// 筛选值
class SpiderFilterValue {
  final String value;
  final String name;

  const SpiderFilterValue({required this.value, required this.name});
}
```

- [ ] **Step 2: 创建蜘蛛模型测试**

```dart
// test/features/video/services/spider/spider_models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/spider_models.dart';

void main() {
  group('SpiderPlayResult', () {
    test('needsParse returns true when parse is "1"', () {
      const result = SpiderPlayResult(url: 'https://example.com', parse: '1');
      expect(result.needsParse, true);
    });

    test('needsParse returns false when parse is "0"', () {
      const result = SpiderPlayResult(url: 'https://example.com', parse: '0');
      expect(result.needsParse, false);
    });

    test('needsParse returns false when parse is null', () {
      const result = SpiderPlayResult(url: 'https://example.com');
      expect(result.needsParse, false);
    });
  });

  group('SpiderHomeResult', () {
    test('defaults are empty', () {
      const result = SpiderHomeResult();
      expect(result.categories, isEmpty);
      expect(result.recommend, isEmpty);
      expect(result.classList, isNull);
    });
  });

  group('SpiderListResult', () {
    test('defaults are correct', () {
      const result = SpiderListResult();
      expect(result.list, isEmpty);
      expect(result.page, 1);
      expect(result.pageCount, 1);
      expect(result.total, 0);
    });
  });
}
```

- [ ] **Step 3: 运行测试验证通过**

Run: `flutter test test/features/video/services/spider/spider_models_test.dart`
Expected: All tests PASS

- [ ] **Step 4: 提交**

```bash
git add lib/features/video/services/spider/spider_models.dart test/features/video/services/spider/spider_models_test.dart
git commit -m "feat: add spider models (SpiderHomeResult/SpiderListResult/SpiderPlayResult)"
```

---

### Task 2: SpiderAdapter 抽象接口

**Files:**
- Create: `lib/features/video/services/spider/spider_adapter.dart`

- [ ] **Step 1: 创建蜘蛛适配器接口**

```dart
// lib/features/video/services/spider/spider_adapter.dart
import 'spider_models.dart';

/// 蜘蛛适配器接口 — 所有蜘蛛实现此接口
abstract class SpiderAdapter {
  /// 蜘蛛唯一标识
  String get key;

  /// 蜘蛛名称
  String get name;

  /// 蜘蛛类型
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

  /// 是否支持手动搜索
  bool get isSearchSupported => true;

  /// 释放资源
  void dispose() {}
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/features/video/services/spider/spider_adapter.dart
git commit -m "feat: add SpiderAdapter abstract interface"
```

---

### Task 3: TVBox 配置解析器

**Files:**
- Create: `lib/features/video/services/spider/tvbox_config_parser.dart`
- Create: `test/features/video/services/spider/tvbox_config_parser_test.dart`

- [ ] **Step 1: 创建 TVBox 配置解析器**

```dart
// lib/features/video/services/spider/tvbox_config_parser.dart

/// TVBox 配置模型
class TvBoxConfig {
  final String? spiderUrl;
  final List<TvBoxSite> sites;
  final List<TvBoxLive> lives;
  final List<String> flags;

  const TvBoxConfig({
    this.spiderUrl,
    this.sites = const [],
    this.lives = const [],
    this.flags = const [],
  });
}

/// TVBox 站点配置
class TvBoxSite {
  final String key;
  final String name;
  final int type;           // 0=CMS, 1=JSON, 3=XPath
  final String api;
  final String? ext;
  final String? jar;
  final String? playerType; // "0"=系统, "1"=IJK, "2"=EXO

  const TvBoxSite({
    required this.key,
    required this.name,
    required this.type,
    required this.api,
    this.ext,
    this.jar,
    this.playerType,
  });
}

/// TVBox 直播源
class TvBoxLive {
  final String name;
  final String type;
  final String url;
  final String? playerType;

  const TvBoxLive({
    required this.name,
    required this.type,
    required this.url,
    this.playerType,
  });
}

/// TVBox 配置解析器
class TvBoxConfigParser {
  /// 解析 TVBox 配置 JSON
  TvBoxConfig parse(Map<String, dynamic> json) {
    // 解析 spider 字段（格式: "jar_url;md5" 或 "jar_url"）
    String? spiderUrl;
    if (json['spider'] is String) {
      spiderUrl = (json['spider'] as String).split(';').first.trim();
    }

    // 解析 sites
    final sites = <TvBoxSite>[];
    for (final s in (json['sites'] as List?) ?? []) {
      if (s is Map<String, dynamic>) {
        sites.add(TvBoxSite(
          key: s['key']?.toString() ?? '',
          name: s['name']?.toString() ?? '',
          type: s['type'] is int ? s['type'] as int : int.tryParse(s['type']?.toString() ?? '0') ?? 0,
          api: s['api']?.toString() ?? '',
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
          name: l['name']?.toString() ?? '',
          type: l['type']?.toString() ?? '0',
          url: l['url']?.toString() ?? '',
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

- [ ] **Step 2: 创建 TVBox 配置解析器测试**

```dart
// test/features/video/services/spider/tvbox_config_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/tvbox_config_parser.dart';

void main() {
  group('TvBoxConfigParser', () {
    late TvBoxConfigParser parser;

    setUp(() {
      parser = TvBoxConfigParser();
    });

    test('parses minimal config with empty fields', () {
      final config = parser.parse({});
      expect(config.spiderUrl, isNull);
      expect(config.sites, isEmpty);
      expect(config.lives, isEmpty);
      expect(config.flags, isEmpty);
    });

    test('parses spider URL without md5', () {
      final config = parser.parse({
        'spider': 'https://example.com/spider.jar',
      });
      expect(config.spiderUrl, 'https://example.com/spider.jar');
    });

    test('parses spider URL with md5', () {
      final config = parser.parse({
        'spider': 'https://example.com/spider.jar;abc123',
      });
      expect(config.spiderUrl, 'https://example.com/spider.jar');
    });

    test('parses sites array', () {
      final config = parser.parse({
        'sites': [
          {'key': 'bfzy', 'name': '暴风资源', 'type': 0, 'api': 'https://bfzyapi.com/api.php/provide/vod/'},
          {'key': 'csp_xb', 'name': '蜘蛛测试', 'type': 3, 'api': 'csp_xb', 'ext': '{"key":"value"}'},
        ],
      });
      expect(config.sites.length, 2);
      expect(config.sites[0].key, 'bfzy');
      expect(config.sites[0].type, 0);
      expect(config.sites[1].type, 3);
      expect(config.sites[1].ext, '{"key":"value"}');
    });

    test('parses lives array', () {
      final config = parser.parse({
        'lives': [
          {'name': '直播源', 'type': 0, 'url': 'https://example.com/live.txt'},
        ],
      });
      expect(config.lives.length, 1);
      expect(config.lives[0].name, '直播源');
    });

    test('parses flags array', () {
      final config = parser.parse({
        'flags': ['优酷', '爱奇艺', '腾讯'],
      });
      expect(config.flags, ['优酷', '爱奇艺', '腾讯']);
    });

    test('handles type as string', () {
      final config = parser.parse({
        'sites': [
          {'key': 'test', 'name': '测试', 'type': '3', 'api': 'test'},
        ],
      });
      expect(config.sites[0].type, 3);
    });

    test('handles missing fields gracefully', () {
      final config = parser.parse({
        'sites': [
          {}, // 完全空的站点
        ],
      });
      expect(config.sites[0].key, '');
      expect(config.sites[0].name, '');
      expect(config.sites[0].type, 0);
      expect(config.sites[0].api, '');
    });
  });
}
```

- [ ] **Step 3: 运行测试验证通过**

Run: `flutter test test/features/video/services/spider/tvbox_config_parser_test.dart`
Expected: All tests PASS

- [ ] **Step 4: 提交**

```bash
git add lib/features/video/services/spider/tvbox_config_parser.dart test/features/video/services/spider/tvbox_config_parser_test.dart
git commit -m "feat: add TvBoxConfigParser with TvBoxConfig/TvBoxSite/TvBoxLive models"
```

---

### Task 4: CMS 蜘蛛实现

**Files:**
- Create: `lib/features/video/services/spider/cms_spider.dart`
- Create: `test/features/video/services/spider/cms_spider_test.dart`

- [ ] **Step 1: 创建 CMS 蜘蛛**

```dart
// lib/features/video/services/spider/cms_spider.dart
import '../../models/video_models.dart';
import '../tbox_api_service.dart';
import 'spider_adapter.dart';
import 'spider_models.dart';
import 'tvbox_config_parser.dart';

/// CMS 采集站蜘蛛 — 复用 VideoApiService 逻辑
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
  Future<void> init(Map<String, dynamic> config) async {
    // CMS 蜘蛛不需要额外配置
  }

  @override
  Future<SpiderHomeResult> homeContent({int page = 1}) async {
    final categories = await _api.fetchCategories(_site.api);
    final list = await _api.fetchVideoList(_site.api, page: page);
    return SpiderHomeResult(
      categories: categories
          .map((c) => SpiderCategory(typeId: c.typeId.toString(), typeName: c.typeName))
          .toList(),
      recommend: list.list,
    );
  }

  @override
  Future<SpiderListResult> categoryContent({
    required String tid,
    int page = 1,
    Map<String, String>? filter,
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
    required String keyword,
    int page = 1,
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
    required String flag,
    required String id,
  }) async {
    // CMS 源播放 URL 直接可用，无需解析
    return SpiderPlayResult(url: id, parse: '0');
  }

  @override
  void dispose() {
    _api.clearAllCache();
  }
}
```

- [ ] **Step 2: 创建 CMS 蜘蛛测试**

```dart
// test/features/video/services/spider/cms_spider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/cms_spider.dart';
import 'package:mediamix/features/video/services/spider/spider_models.dart';
import 'package:mediamix/features/video/services/spider/tvbox_config_parser.dart';

void main() {
  group('CmsSpider', () {
    late CmsSpider spider;

    setUp(() {
      spider = CmsSpider(const TvBoxSite(
        key: 'bfzy',
        name: '暴风资源',
        type: 0,
        api: 'https://bfzyapi.com/api.php/provide/vod/',
      ));
    });

    test('key and name match site config', () {
      expect(spider.key, 'bfzy');
      expect(spider.name, '暴风资源');
    });

    test('type is cms', () {
      expect(spider.type, SpiderType.cms);
    });

    test('isSearchSupported defaults to true', () {
      expect(spider.isSearchSupported, true);
    });

    test('playerContent returns direct URL', () async {
      final result = await spider.playerContent(flag: 'default', id: 'https://example.com/video.m3u8');
      expect(result.url, 'https://example.com/video.m3u8');
      expect(result.needsParse, false);
    });
  });
}
```

- [ ] **Step 3: 运行测试验证通过**

Run: `flutter test test/features/video/services/spider/cms_spider_test.dart`
Expected: All tests PASS

- [ ] **Step 4: 提交**

```bash
git add lib/features/video/services/spider/cms_spider.dart test/features/video/services/spider/cms_spider_test.dart
git commit -m "feat: add CmsSpider implementation reusing VideoApiService"
```

---

### Task 5: JSON 蜘蛛实现

**Files:**
- Create: `lib/features/video/services/spider/json_spider.dart`
- Create: `test/features/video/services/spider/json_spider_test.dart`

- [ ] **Step 1: 创建 JSON 蜘蛛**

```dart
// lib/features/video/services/spider/json_spider.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../models/video_models.dart';
import 'spider_adapter.dart';
import 'spider_models.dart';
import 'tvbox_config_parser.dart';

/// JSON API 蜘蛛 — 通过 JSONPath + 字段映射解析 API 响应
class JsonSpider extends SpiderAdapter {
  final TvBoxSite _site;
  final Dio _dio;
  Map<String, dynamic> _config = {};

  JsonSpider(this._site) : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'User-Agent': 'okhttp/3.12.11'},
  ));

  @override
  String get key => _site.key;

  @override
  String get name => _site.name;

  @override
  SpiderType get type => SpiderType.json;

  @override
  Future<void> init(Map<String, dynamic> config) async {
    _config = Map<String, dynamic>.from(config);
    if (config.containsKey('extUrl')) {
      try {
        final resp = await _dio.get(config['extUrl']);
        final data = resp.data;
        _config = data is Map<String, dynamic> ? data : jsonDecode(data.toString());
      } catch (_) {
        // 远程配置获取失败，使用本地配置
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
    return SpiderListResult(list: items, page: page, pageCount: 1, total: items.length);
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
    if (url.isEmpty) return const SpiderListResult();

    final data = await _fetchJson(url);
    final items = _extractList(data, _config['listPath']?.toString() ?? '');
    return SpiderListResult(list: items, page: page, pageCount: 1, total: items.length);
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

  // --- 辅助方法 ---

  Future<Map<String, dynamic>> _fetchJson(String url) async {
    final resp = await _dio.get(url);
    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    return jsonDecode(data.toString()) as Map<String, dynamic>;
  }

  List<SpiderCategory> _parseCategories() {
    final cats = _config['categories'] as List? ?? [];
    return cats.map((c) {
      final m = c as Map<String, dynamic>;
      return SpiderCategory(
        typeId: m['id']?.toString() ?? '',
        typeName: m['name']?.toString() ?? '',
      );
    }).toList();
  }

  List<VideoItem> _extractList(Map<String, dynamic> data, String jsonPath) {
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
        vodId: _mapField(m, 'vod_id', fieldMap) ?? '',
        vodName: _mapField(m, 'vod_name', fieldMap) ?? '未知',
        vodPic: _mapField(m, 'vod_pic', fieldMap),
        vodRemarks: _mapField(m, 'vod_remarks', fieldMap),
        vodYear: _mapField(m, 'vod_year', fieldMap),
        vodArea: _mapField(m, 'vod_area', fieldMap),
        typeName: _mapField(m, 'type_name', fieldMap),
        sourceKey: key,
      );
    }).toList();
  }

  String? _mapField(Map<String, dynamic> m, String vodField, Map<String, dynamic> fieldMap) {
    final apiKey = fieldMap[vodField]?.toString() ?? vodField;
    return m[apiKey]?.toString();
  }

  VideoDetail _extractDetail(Map<String, dynamic> data, String id) {
    final detailPath = _config['detailPath']?.toString() ?? '';
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
      vodYear: _mapField(detail, 'vod_year', fieldMap),
      vodArea: _mapField(detail, 'vod_area', fieldMap),
      vodRemarks: _mapField(detail, 'vod_remarks', fieldMap),
      typeName: _mapField(detail, 'type_name', fieldMap),
      sourceKey: key,
      playSources: _extractPlaySources(detail),
    );
  }

  List<PlaySource> _extractPlaySources(Map<String, dynamic> detail) {
    final fieldMap = _config['fieldMap'] as Map<String, dynamic>? ?? {};
    final playFromKey = fieldMap['vod_play_from']?.toString() ?? 'vod_play_from';
    final playUrlKey = fieldMap['vod_play_url']?.toString() ?? 'vod_play_url';

    final vodPlayFrom = detail[playFromKey]?.toString() ?? '';
    final vodPlayUrl = detail[playUrlKey]?.toString() ?? '';

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

- [ ] **Step 2: 创建 JSON 蜘蛛测试**

```dart
// test/features/video/services/spider/json_spider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/json_spider.dart';
import 'package:mediamix/features/video/services/spider/spider_models.dart';
import 'package:mediamix/features/video/services/spider/tvbox_config_parser.dart';

void main() {
  group('JsonSpider', () {
    late JsonSpider spider;

    setUp(() {
      spider = JsonSpider(const TvBoxSite(
        key: 'json_test',
        name: 'JSON测试源',
        type: 1,
        api: 'https://api.example.com',
      ));
    });

    test('key and name match site config', () {
      expect(spider.key, 'json_test');
      expect(spider.name, 'JSON测试源');
    });

    test('type is json', () {
      expect(spider.type, SpiderType.json);
    });

    test('init with empty config does not throw', () async {
      await spider.init({});
      // 无异常即通过
    });

    test('init with extUrl that fails gracefully', () async {
      // 远程配置获取失败时使用本地配置
      await spider.init({'extUrl': 'https://nonexistent.invalid/config.json'});
      // 无异常即通过
    });
  });
}
```

- [ ] **Step 3: 运行测试验证通过**

Run: `flutter test test/features/video/services/spider/json_spider_test.dart`
Expected: All tests PASS

- [ ] **Step 4: 提交**

```bash
git add lib/features/video/services/spider/json_spider.dart test/features/video/services/spider/json_spider_test.dart
git commit -m "feat: add JsonSpider with JSONPath and field mapping support"
```

---

### Task 6: XPath 蜘蛛实现

**Files:**
- Create: `lib/features/video/services/spider/xpath_spider.dart`

- [ ] **Step 1: 添加 html 依赖**

在 `pubspec.yaml` 的 dependencies 中添加：
```yaml
  html: ^0.15.4
```

Run: `flutter pub get`

- [ ] **Step 2: 创建 XPath 蜘蛛**

```dart
// lib/features/video/services/spider/xpath_spider.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import '../../models/video_models.dart';
import 'spider_adapter.dart';
import 'spider_models.dart';
import 'tvbox_config_parser.dart';

/// XPath 蜘蛛 — 通过 CSS 选择器 + XPath 规则解析 HTML 页面
class XpathSpider extends SpiderAdapter {
  final TvBoxSite _site;
  final Dio _dio;
  Map<String, dynamic> _config = {};

  XpathSpider(this._site) : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'User-Agent': 'Mozilla/5.0'},
  ));

  @override
  String get key => _site.key;

  @override
  String get name => _site.name;

  @override
  SpiderType get type => SpiderType.xpath;

  @override
  Future<void> init(Map<String, dynamic> config) async {
    _config = Map<String, dynamic>.from(config);
    if (config.containsKey('extUrl')) {
      try {
        final resp = await _dio.get(config['extUrl']);
        final data = resp.data;
        _config = data is Map<String, dynamic> ? data : jsonDecode(data.toString());
      } catch (_) {}
    }
  }

  @override
  Future<SpiderHomeResult> homeContent({int page = 1}) async {
    final url = _config['homeUrl']?.toString() ?? _site.api;
    final doc = await _fetchHtml(url);
    final categories = _parseCategories();
    final items = _parseList(doc);
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

    final doc = await _fetchHtml(url);
    final items = _parseList(doc);
    return SpiderListResult(list: items, page: page, pageCount: 1, total: items.length);
  }

  @override
  Future<SpiderDetailResult> detailContent({required String id}) async {
    var url = (_config['detailUrl']?.toString() ?? '').replaceAll('{id}', id);
    if (url.isEmpty) url = id;

    final doc = await _fetchHtml(url);
    final detail = _parseDetail(doc, id);
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
    if (url.isEmpty) return const SpiderListResult();

    final doc = await _fetchHtml(url);
    final items = _parseList(doc);
    return SpiderListResult(list: items, page: page, pageCount: 1, total: items.length);
  }

  @override
  Future<SpiderPlayResult> playerContent({
    required String flag,
    required String id,
  }) async {
    final playConfig = _config['playUrl'] as Map<String, dynamic>? ?? {};
    final parseFlag = playConfig['parse']?.toString() ?? '0';

    if (playConfig.containsKey('selector')) {
      final doc = await _fetchHtml(id);
      final element = doc.querySelector(playConfig['selector'].toString());
      final playUrl = element?.attributes['src'] ?? element?.attributes['href'] ?? element?.text ?? '';
      return SpiderPlayResult(
        url: playUrl,
        parse: parseFlag,
        playUrl: parseFlag == '1' ? playUrl : null,
      );
    }

    return SpiderPlayResult(url: id, parse: parseFlag);
  }

  // --- 辅助方法 ---

  Future<dom.Document> _fetchHtml(String url) async {
    final resp = await _dio.get(url, options: Options(responseType: ResponseType.plain));
    return html_parser.parse(resp.data.toString());
  }

  List<SpiderCategory> _parseCategories() {
    final cats = _config['categories'] as List? ?? [];
    return cats.map((c) {
      final m = c as Map<String, dynamic>;
      return SpiderCategory(
        typeId: m['id']?.toString() ?? '',
        typeName: m['name']?.toString() ?? '',
      );
    }).toList();
  }

  List<VideoItem> _parseList(dom.Document doc) {
    final listConfig = _config['list'] as Map<String, dynamic>? ?? {};
    final containerSelector = listConfig['container']?.toString() ?? '';
    final fieldSelectors = listConfig['fields'] as Map<String, dynamic>? ?? {};

    if (containerSelector.isEmpty) return [];

    final elements = doc.querySelectorAll(containerSelector);
    return elements.map((el) {
      return VideoItem(
        vodId: _selectField(el, fieldSelectors['vod_id']),
        vodName: _selectField(el, fieldSelectors['vod_name']) ?? '未知',
        vodPic: _selectField(el, fieldSelectors['vod_pic']),
        vodRemarks: _selectField(el, fieldSelectors['vod_remarks']),
        sourceKey: key,
      );
    }).toList();
  }

  String? _selectField(dom.Element parent, dynamic selector) {
    if (selector == null) return null;
    final sel = selector.toString();
    if (sel.isEmpty) return null;

    // 格式: "selector@attr" 或 "selector" (取文本)
    final parts = sel.split('@');
    final cssSelector = parts[0];
    final attr = parts.length > 1 ? parts[1] : null;

    final element = parent.querySelector(cssSelector);
    if (element == null) return null;

    if (attr == 'href' || attr == 'src') return element.attributes[attr];
    if (attr == 'text') return element.text.trim();
    return element.text.trim();
  }

  VideoDetail _parseDetail(dom.Document doc, String id) {
    final detailConfig = _config['detail'] as Map<String, dynamic>? ?? {};
    final fieldSelectors = detailConfig['fields'] as Map<String, dynamic>? ?? {};

    return VideoDetail(
      vodId: id,
      vodName: _selectDocField(doc, fieldSelectors['vod_name']) ?? '未知',
      vodPic: _selectDocField(doc, fieldSelectors['vod_pic']),
      vodContent: _selectDocField(doc, fieldSelectors['vod_content']),
      vodActor: _selectDocField(doc, fieldSelectors['vod_actor']),
      vodDirector: _selectDocField(doc, fieldSelectors['vod_director']),
      sourceKey: key,
      playSources: _parsePlaySources(doc),
    );
  }

  String? _selectDocField(dom.Document doc, dynamic selector) {
    if (selector == null) return null;
    final sel = selector.toString();
    if (sel.isEmpty) return null;

    final parts = sel.split('@');
    final cssSelector = parts[0];
    final attr = parts.length > 1 ? parts[1] : null;

    final element = doc.querySelector(cssSelector);
    if (element == null) return null;

    if (attr == 'href' || attr == 'src') return element.attributes[attr];
    return element.text.trim();
  }

  List<PlaySource> _parsePlaySources(dom.Document doc) {
    final playConfig = _config['playUrl'] as Map<String, dynamic>? ?? {};
    final tabSelector = playConfig['tab']?.toString() ?? '';
    final listSelector = playConfig['list']?.toString() ?? '';
    final nameSelector = playConfig['name']?.toString() ?? '';
    final urlSelector = playConfig['url']?.toString() ?? '';

    if (tabSelector.isEmpty || listSelector.isEmpty) return [];

    final tabs = doc.querySelectorAll(tabSelector);
    final lists = doc.querySelectorAll(listSelector);

    final sources = <PlaySource>[];
    for (int i = 0; i < tabs.length && i < lists.length; i++) {
      final episodes = <VideoEpisode>[];
      for (final item in lists[i].querySelectorAll('li, a')) {
        final name = nameSelector.isNotEmpty
            ? item.querySelector(nameSelector)?.text.trim() ?? ''
            : item.text.trim();
        final url = urlSelector.isNotEmpty
            ? (item.querySelector(urlSelector)?.attributes['href'] ?? item.attributes['href'] ?? '')
            : item.attributes['href'] ?? '';
        if (name.isNotEmpty && url.isNotEmpty) {
          episodes.add(VideoEpisode(name: name, url: url));
        }
      }
      if (episodes.isNotEmpty) {
        sources.add(PlaySource(name: tabs[i].text.trim(), episodes: episodes));
      }
    }
    return sources;
  }
}
```

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml pubspec.lock lib/features/video/services/spider/xpath_spider.dart
git commit -m "feat: add XpathSpider with CSS selector + HTML parsing support"
```

---

### Task 7: 蜘蛛注册表

**Files:**
- Create: `lib/features/video/services/spider/spider_registry.dart`
- Create: `test/features/video/services/spider/spider_registry_test.dart`

- [ ] **Step 1: 创建蜘蛛注册表**

```dart
// lib/features/video/services/spider/spider_registry.dart
import 'dart:convert';
import 'package:logger/logger.dart';
import 'spider_adapter.dart';
import 'spider_models.dart';
import 'tvbox_config_parser.dart';
import 'cms_spider.dart';
import 'xpath_spider.dart';
import 'json_spider.dart';

/// 蜘蛛注册表 — 管理蜘蛛实例的创建、缓存和生命周期
class SpiderRegistry {
  static final SpiderRegistry _instance = SpiderRegistry._internal();
  factory SpiderRegistry() => _instance;
  SpiderRegistry._internal();

  final Logger _logger = Logger(printer: SimplePrinter());

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
    // 1. 检查是否已有缓存实例
    if (_instances.containsKey(site.key)) {
      return _instances[site.key]!;
    }

    // 2. 检查是否有内置工厂
    if (_factories.containsKey(site.key)) {
      try {
        final spider = _factories[site.key]!(_parseExt(site.ext));
        await spider.init(_parseExt(site.ext));
        _instances[site.key] = spider;
        _logger.d('内置蜘蛛创建成功: ${site.key}');
        return spider;
      } catch (e) {
        _logger.e('内置蜘蛛创建失败: ${site.key} - $e');
        return null;
      }
    }

    // 3. 根据 type 自动创建
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
        _logger.w('未知蜘蛛类型: ${site.type}，尝试CMS兼容: ${site.key}');
        spider = CmsSpider(site);
    }

    if (spider != null) {
      try {
        await spider.init(_parseExt(site.ext));
        _instances[site.key] = spider;
        _logger.d('蜘蛛创建成功: ${site.key} (${spider.type})');
      } catch (e) {
        _logger.e('蜘蛛初始化失败: ${site.key} - $e');
        return null;
      }
    }

    return spider;
  }

  /// 批量创建蜘蛛
  Future<List<SpiderAdapter>> createFromSites(List<TvBoxSite> sites) async {
    final results = <SpiderAdapter>[];
    for (final site in sites) {
      final spider = await createFromSite(site);
      if (spider != null) results.add(spider);
    }
    return results;
  }

  /// 获取已创建的蜘蛛实例
  SpiderAdapter? get(String key) => _instances[key];

  /// 获取所有已创建的蜘蛛实例
  List<SpiderAdapter> get all => _instances.values.toList();

  /// 移除指定蜘蛛
  void remove(String key) {
    _instances[key]?.dispose();
    _instances.remove(key);
  }

  /// 释放所有蜘蛛
  void disposeAll() {
    for (final spider in _instances.values) {
      spider.dispose();
    }
    _instances.clear();
  }

  /// 解析 ext 字段为 Map
  Map<String, dynamic> _parseExt(String? ext) {
    if (ext == null || ext.isEmpty) return {};
    if (ext.startsWith('http://') || ext.startsWith('https://')) {
      return {'extUrl': ext};
    }
    try {
      return jsonDecode(ext) as Map<String, dynamic>;
    } catch (_) {
      return {'ext': ext};
    }
  }
}
```

- [ ] **Step 2: 创建蜘蛛注册表测试**

```dart
// test/features/video/services/spider/spider_registry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/spider_registry.dart';
import 'package:mediamix/features/video/services/spider/spider_models.dart';
import 'package:mediamix/features/video/services/spider/tvbox_config_parser.dart';

void main() {
  group('SpiderRegistry', () {
    late SpiderRegistry registry;

    setUp(() {
      registry = SpiderRegistry();
      registry.disposeAll();
    });

    tearDown(() {
      registry.disposeAll();
    });

    test('createFromSite with type 0 creates CmsSpider', () async {
      final spider = await registry.createFromSite(const TvBoxSite(
        key: 'test_cms',
        name: 'CMS测试',
        type: 0,
        api: 'https://example.com/api',
      ));
      expect(spider, isNotNull);
      expect(spider!.key, 'test_cms');
      expect(spider.type, SpiderType.cms);
    });

    test('createFromSite with type 1 creates JsonSpider', () async {
      final spider = await registry.createFromSite(const TvBoxSite(
        key: 'test_json',
        name: 'JSON测试',
        type: 1,
        api: 'https://example.com/api',
      ));
      expect(spider, isNotNull);
      expect(spider!.type, SpiderType.json);
    });

    test('createFromSite with type 3 creates XpathSpider', () async {
      final spider = await registry.createFromSite(const TvBoxSite(
        key: 'test_xpath',
        name: 'XPath测试',
        type: 3,
        api: 'https://example.com',
      ));
      expect(spider, isNotNull);
      expect(spider!.type, SpiderType.xpath);
    });

    test('createFromSite caches instances', () async {
      final spider1 = await registry.createFromSite(const TvBoxSite(
        key: 'cached_test',
        name: '缓存测试',
        type: 0,
        api: 'https://example.com/api',
      ));
      final spider2 = registry.get('cached_test');
      expect(identical(spider1, spider2), true);
    });

    test('get returns null for non-existent key', () {
      expect(registry.get('nonexistent'), isNull);
    });

    test('remove disposes and removes spider', () async {
      await registry.createFromSite(const TvBoxSite(
        key: 'removable',
        name: '可移除',
        type: 0,
        api: 'https://example.com/api',
      ));
      expect(registry.get('removable'), isNotNull);
      registry.remove('removable');
      expect(registry.get('removable'), isNull);
    });

    test('disposeAll clears all instances', () async {
      await registry.createFromSite(const TvBoxSite(key: 'a', name: 'A', type: 0, api: ''));
      await registry.createFromSite(const TvBoxSite(key: 'b', name: 'B', type: 0, api: ''));
      expect(registry.all.length, 2);
      registry.disposeAll();
      expect(registry.all.length, 0);
    });

    test('register custom factory', () async {
      registry.register('custom', (config) => _TestSpider(config));
      final spider = await registry.createFromSite(const TvBoxSite(
        key: 'custom',
        name: '自定义',
        type: 99,
        api: '',
      ));
      expect(spider, isNotNull);
      expect(spider!.runtimeType, _TestSpider);
    });
  });
}

class _TestSpider extends SpiderAdapter {
  final Map<String, dynamic> _config;
  _TestSpider(this._config);

  @override
  String get key => 'custom';
  @override
  String get name => '自定义蜘蛛';
  @override
  SpiderType get type => SpiderType.site;

  @override
  Future<void> init(Map<String, dynamic> config) async {}

  @override
  Future<SpiderHomeResult> homeContent({int page = 1}) async => const SpiderHomeResult();

  @override
  Future<SpiderListResult> categoryContent({required String tid, int page = 1, Map<String, String>? filter}) async => const SpiderListResult();

  @override
  Future<SpiderDetailResult> detailContent({required String id}) async => const SpiderDetailResult();

  @override
  Future<SpiderListResult> searchContent({required String keyword, int page = 1}) async => const SpiderListResult();

  @override
  Future<SpiderPlayResult> playerContent({required String flag, required String id}) async => const SpiderPlayResult();
}
```

- [ ] **Step 3: 运行测试验证通过**

Run: `flutter test test/features/video/services/spider/spider_registry_test.dart`
Expected: All tests PASS

- [ ] **Step 4: 提交**

```bash
git add lib/features/video/services/spider/spider_registry.dart test/features/video/services/spider/spider_registry_test.dart
git commit -m "feat: add SpiderRegistry with factory registration and instance caching"
```

---

### Task 8: 蜘蛛服务门面

**Files:**
- Create: `lib/features/video/services/spider/spider_service.dart`

- [ ] **Step 1: 创建蜘蛛服务门面**

```dart
// lib/features/video/services/spider/spider_service.dart
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../../models/video_models.dart';
import '../tbox_api_service.dart';
import 'spider_adapter.dart';
import 'spider_models.dart';
import 'spider_registry.dart';
import 'tvbox_config_parser.dart';

/// 蜘蛛服务 — 统一入口，封装 Registry + TVBox 配置获取
class SpiderService {
  final Logger _logger = Logger(printer: SimplePrinter());
  final SpiderRegistry _registry = SpiderRegistry();
  final Dio _dio;

  SpiderService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'User-Agent': 'okhttp/3.12.11'},
  ));

  /// 获取 TVBox 配置
  Future<TvBoxConfig> fetchTvBoxConfig(String configUrl) async {
    try {
      final response = await _dio.get(configUrl);
      final data = response.data;
      final Map<String, dynamic> json;
      if (data is Map<String, dynamic>) {
        json = data;
      } else {
        json = {} as Map<String, dynamic>; // fallback
      }
      final config = TvBoxConfigParser().parse(json);
      _logger.d('TVBox配置解析完成: ${config.sites.length}个站点, spider=${config.spiderUrl}');
      return config;
    } catch (e) {
      _logger.e('获取TVBox配置失败: $e');
      rethrow;
    }
  }

  /// 从 TVBox 配置创建所有蜘蛛
  Future<List<SpiderAdapter>> initFromConfig(TvBoxConfig config) async {
    return _registry.createFromSites(config.sites);
  }

  /// 获取蜘蛛实例
  SpiderAdapter? getSpider(String key) => _registry.get(key);

  /// 获取所有蜘蛛
  List<SpiderAdapter> get allSpiders => _registry.all;

  /// 通过蜘蛛获取首页内容
  Future<SpiderHomeResult> fetchHome(SpiderAdapter spider, {int page = 1}) {
    return spider.homeContent(page: page);
  }

  /// 通过蜘蛛获取分类内容
  Future<SpiderListResult> fetchCategory(
    SpiderAdapter spider, {
    required String tid,
    int page = 1,
  }) {
    return spider.categoryContent(tid: tid, page: page);
  }

  /// 通过蜘蛛获取详情
  Future<SpiderDetailResult> fetchDetail(
    SpiderAdapter spider, {
    required String id,
  }) {
    return spider.detailContent(id: id);
  }

  /// 通过蜘蛛搜索
  Future<SpiderListResult> fetchSearch(
    SpiderAdapter spider, {
    required String keyword,
    int page = 1,
  }) {
    return spider.searchContent(keyword: keyword, page: page);
  }

  /// 通过蜘蛛解析播放地址
  Future<SpiderPlayResult> fetchPlay(
    SpiderAdapter spider, {
    required String flag,
    required String id,
  }) {
    return spider.playerContent(flag: flag, id: id);
  }

  /// 释放所有蜘蛛
  void disposeAll() => _registry.disposeAll();
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/features/video/services/spider/spider_service.dart
git commit -m "feat: add SpiderService facade for unified spider access"
```

---

### Task 9: VideoSource 模型扩展 + 视频解析增强

**Files:**
- Modify: `lib/features/video/models/video_models.dart`

- [ ] **Step 1: 在 video_models.dart 中添加 VideoSource 模型**

在 `CmsApiSite` 类之后添加：

```dart
/// 视频源类型
enum SourceType {
  cms,      // 标准CMS采集站
  spider,   // 蜘蛛源
}

/// 视频源（统一 CMS 站点和蜘蛛源）
class VideoSource {
  final String key;
  final String name;
  final String apiUrl;
  final bool enabled;
  final bool isBuiltIn;
  final SourceType sourceType;
  final String? spiderKey;
  final int? playerType;  // 0=系统, 1=IJK, 2=EXO

  const VideoSource({
    required this.key,
    required this.name,
    required this.apiUrl,
    this.enabled = true,
    this.isBuiltIn = false,
    this.sourceType = SourceType.cms,
    this.spiderKey,
    this.playerType,
  });

  VideoSource copyWith({
    String? key,
    String? name,
    String? apiUrl,
    bool? enabled,
    bool? isBuiltIn,
    SourceType? sourceType,
    String? spiderKey,
    int? playerType,
  }) {
    return VideoSource(
      key: key ?? this.key,
      name: name ?? this.name,
      apiUrl: apiUrl ?? this.apiUrl,
      enabled: enabled ?? this.enabled,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      sourceType: sourceType ?? this.sourceType,
      spiderKey: spiderKey ?? this.spiderKey,
      playerType: playerType ?? this.playerType,
    );
  }

  /// 从 CmsApiSite 转换
  factory VideoSource.fromCmsSite(CmsApiSite site) {
    return VideoSource(
      key: site.key,
      name: site.name,
      apiUrl: site.apiUrl,
      enabled: site.enabled,
      isBuiltIn: site.isBuiltIn,
      sourceType: SourceType.cms,
    );
  }
}
```

- [ ] **Step 2: 在 VideoParser.defaultParsers 中新增解析接口**

修改 `VideoParser.defaultParsers` 列表，在现有 4 个解析接口后添加：

```dart
    VideoParser(
      key: 'jlk',
      name: 'JLK解析',
      urlTemplate: 'https://jlk.jianghu.vip/?url={url}',
    ),
```

- [ ] **Step 3: 提交**

```bash
git add lib/features/video/models/video_models.dart
git commit -m "feat: add VideoSource model and JLK video parser"
```

---

### Task 10: VideoApiService 扩展

**Files:**
- Modify: `lib/features/video/services/tbox_api_service.dart`

- [ ] **Step 1: 在 VideoApiService 中添加 fetchTvBoxConfig 方法**

在 `VideoApiService` 类中 `clearAllCache()` 方法之前添加：

```dart
  // ==================== TVBox 配置 ====================

  /// 获取 TVBox 配置
  Future<TvBoxConfig> fetchTvBoxConfig(String configUrl) async {
    try {
      final url = _buildUrl(configUrl, {});
      _logger.d('获取TVBox配置: $url');
      final response = await _dio.get(url);
      final data = _extractJson(response);
      return TvBoxConfigParser().parse(data);
    } on DioException catch (e) {
      throw Exception(_formatDioError(e));
    } catch (e) {
      _logger.e('获取TVBox配置失败: $e');
      throw Exception('获取TVBox配置失败: $e');
    }
  }
```

同时在文件顶部添加 import：

```dart
import 'spider/tvbox_config_parser.dart';
```

- [ ] **Step 2: 提交**

```bash
git add lib/features/video/services/tbox_api_service.dart
git commit -m "feat: add fetchTvBoxConfig method to VideoApiService"
```

---

### Task 11: Provider 层适配

**Files:**
- Modify: `lib/features/video/providers/video_providers.dart`

- [ ] **Step 1: 添加蜘蛛相关 Provider**

在 `video_providers.dart` 文件顶部添加 import：

```dart
import '../services/spider/spider_service.dart';
import '../services/spider/spider_adapter.dart';
import '../services/spider/spider_models.dart';
import '../services/spider/tvbox_config_parser.dart';
```

在文件中（`videoApiServiceProvider` 之后）添加：

```dart
// ===== 蜘蛛服务 Provider =====
final spiderServiceProvider = Provider<SpiderService>((ref) {
  final service = SpiderService();
  ref.onDispose(() => service.disposeAll());
  return service;
});

// ===== TVBox 配置 Provider =====
final tvboxConfigProvider = FutureProvider.family<TvBoxConfig, String>((ref, configUrl) async {
  final service = ref.read(spiderServiceProvider);
  return service.fetchTvBoxConfig(configUrl);
});
```

- [ ] **Step 2: 提交**

```bash
git add lib/features/video/providers/video_providers.dart
git commit -m "feat: add spider service and TVBox config providers"
```

---

### Task 12: 运行全量测试

**Files:**
- 无新增

- [ ] **Step 1: 运行所有蜘蛛相关测试**

Run: `flutter test test/features/video/services/spider/`
Expected: All tests PASS

- [ ] **Step 2: 运行全量测试确保无回归**

Run: `flutter test`
Expected: All tests PASS (或仅有已知失败)

- [ ] **Step 3: 运行静态分析**

Run: `flutter analyze`
Expected: No issues found

---

## Self-Review Checklist

1. **Spec coverage:**
   - SpiderAdapter 接口 → Task 2
   - 蜘蛛结果模型 → Task 1
   - TVBox 配置解析器 → Task 3
   - 蜘蛛注册表 → Task 7
   - CmsSpider → Task 4
   - XpathSpider → Task 6
   - JsonSpider → Task 5
   - VideoSource 模型 → Task 9
   - 视频解析增强 → Task 9
   - VideoApiService 扩展 → Task 10
   - Provider 层适配 → Task 11
   - All covered.

2. **Placeholder scan:** No TBD/TODO/fill-in-later patterns found.

3. **Type consistency:** SpiderType enum used consistently across all files. TvBoxSite model used consistently. SpiderAdapter interface methods match implementations.
