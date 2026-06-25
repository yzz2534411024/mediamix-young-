import 'dart:convert';

import 'cms_spider.dart';
import 'java_bridge_client.dart';
import 'java_bridge_spider.dart';
import 'json_spider.dart';
import 'spider_adapter.dart';
import 'tvbox_config_parser.dart';
import 'xpath_spider.dart';

/// 蜘蛛工厂函数签名
typedef SpiderFactory = SpiderAdapter Function(TvBoxSite site);

/// 蜘蛛注册表
///
/// 负责根据 [TvBoxSite] 创建、缓存和管理 [SpiderAdapter] 实例。
/// 使用单例模式，支持内置类型自动映射和自定义工厂注册。
class SpiderRegistry {
  static final SpiderRegistry _instance = SpiderRegistry._internal();

  /// 全局单例
  static SpiderRegistry get instance => _instance;

  final Map<String, SpiderFactory> _factories = {};
  final Map<String, SpiderAdapter> _instances = {};

  SpiderRegistry._internal();

  /// 注册自定义蜘蛛工厂
  ///
  /// [key] 为站点 key，当 [createFromSite] 遇到该 key 的站点时会优先使用此工厂。
  void register(String key, SpiderFactory factory) {
    _factories[key] = factory;
  }

  /// 全局共享的 Java Bridge 客户端（由 SpiderService 初始化时注入）
  JavaBridgeClient? javaBridgeClient;

  /// 根据站点配置创建或返回缓存的蜘蛛实例
  ///
  /// 查找顺序：缓存 -> 已注册工厂 -> 内置类型映射。
  /// 创建成功后会调用 [SpiderAdapter.init] 并传入 [_parseExt] 解析后的配置。
  Future<SpiderAdapter?> createFromSite(TvBoxSite site) async {
    if (_instances.containsKey(site.key)) {
      return _instances[site.key];
    }

    final spider = _buildSpider(site);
    if (spider == null) return null;

    await spider.init(_parseExt(site.ext));
    _instances[site.key] = spider;
    return spider;
  }

  /// 批量根据站点配置创建蜘蛛实例
  Future<List<SpiderAdapter>> createFromSites(List<TvBoxSite> sites) async {
    final result = <SpiderAdapter>[];
    for (final site in sites) {
      final spider = await createFromSite(site);
      if (spider != null) {
        result.add(spider);
      }
    }
    return result;
  }

  /// 获取指定 key 的蜘蛛实例
  SpiderAdapter? get(String key) => _instances[key];

  /// 获取所有已缓存的蜘蛛实例
  List<SpiderAdapter> get all => List.unmodifiable(_instances.values);

  /// 移除并释放指定 key 的蜘蛛实例
  void remove(String key) {
    final spider = _instances.remove(key);
    spider?.dispose();
  }

  /// 释放所有蜘蛛实例并清空缓存
  void disposeAll() {
    for (final spider in _instances.values) {
      spider.dispose();
    }
    _instances.clear();
  }

  SpiderAdapter? _buildSpider(TvBoxSite site) {
    final factory = _factories[site.key];
    if (factory != null) {
      return factory(site);
    }

    // Java 蜘蛛桥接：csp_* 格式的 API 名称
    if (site.isJavaSpider && javaBridgeClient != null) {
      return JavaBridgeSpider(site: site, client: javaBridgeClient!);
    }

    switch (site.type) {
      case 0:
        return CmsSpider(site: site);
      case 1:
        return JsonSpider(site: site);
      case 3:
        // type=3 且非 csp_* 格式，使用 XPath 蜘蛛
        if (!site.isJavaSpider) {
          return XpathSpider(site: site);
        }
        // csp_* 格式但 Bridge 不可用，返回 null
        return null;
      default:
        return null;
    }
  }

  /// 解析站点的 ext 字段为初始化配置映射
  ///
  /// - 以 `http://` 或 `https://` 开头的值返回 `{'extUrl': ext}`
  /// - 可解析为 JSON 对象的字符串返回该对象
  /// - 其他值返回 `{'ext': ext}`
  /// - [ext] 为 null 时返回空映射
  Map<String, dynamic> _parseExt(String? ext) {
    if (ext == null) return {};

    if (ext.startsWith('http://') || ext.startsWith('https://')) {
      return {'extUrl': ext};
    }

    try {
      final decoded = jsonDecode(ext);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // 不是 JSON 字符串，按普通字符串处理
    }

    return {'ext': ext};
  }
}
