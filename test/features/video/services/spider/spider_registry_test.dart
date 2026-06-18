import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/cms_spider.dart';
import 'package:mediamix/features/video/services/spider/json_spider.dart';
import 'package:mediamix/features/video/services/spider/spider_adapter.dart';
import 'package:mediamix/features/video/services/spider/spider_models.dart';
import 'package:mediamix/features/video/services/spider/spider_registry.dart';
import 'package:mediamix/features/video/services/spider/tvbox_config_parser.dart';
import 'package:mediamix/features/video/services/spider/xpath_spider.dart';

void main() {
  final registry = SpiderRegistry.instance;

  setUp(() {
    registry.disposeAll();
  });

  tearDown(() {
    registry.disposeAll();
  });

  group('SpiderRegistry', () {
    test('type 0 创建 CmsSpider', () async {
      const site = TvBoxSite(
        key: 'cms-site',
        name: 'CMS Site',
        type: 0,
        api: 'https://cms.example.com/api',
      );

      final spider = await registry.createFromSite(site);

      expect(spider, isA<CmsSpider>());
      expect(spider!.key, 'cms-site');
      expect(registry.get('cms-site'), same(spider));
    });

    test('type 1 创建 JsonSpider', () async {
      const site = TvBoxSite(
        key: 'json-site',
        name: 'JSON Site',
        type: 1,
        api: 'https://json.example.com/api',
      );

      final spider = await registry.createFromSite(site);

      expect(spider, isA<JsonSpider>());
      expect(spider!.key, 'json-site');
    });

    test('type 3 创建 XpathSpider', () async {
      const site = TvBoxSite(
        key: 'xpath-site',
        name: 'XPath Site',
        type: 3,
        api: 'https://xpath.example.com',
      );

      final spider = await registry.createFromSite(site);

      expect(spider, isA<XpathSpider>());
      expect(spider!.key, 'xpath-site');
    });

    test('同一站点多次创建返回缓存实例', () async {
      const site = TvBoxSite(
        key: 'cached-site',
        name: 'Cached Site',
        type: 0,
        api: 'https://cms.example.com/api',
      );

      final first = await registry.createFromSite(site);
      final second = await registry.createFromSite(site);

      expect(first, same(second));
      expect(registry.all.length, 1);
    });

    test('get 不存在 key 返回 null', () {
      expect(registry.get('not-exists'), isNull);
    });

    test('remove 释放并移除实例', () async {
      const site = TvBoxSite(
        key: 'removable-site',
        name: 'Removable Site',
        type: 0,
        api: 'https://cms.example.com/api',
      );

      final spider = await registry.createFromSite(site);
      expect(spider, isNotNull);

      registry.remove('removable-site');

      expect(registry.get('removable-site'), isNull);
      expect(registry.all, isEmpty);
    });

    test('disposeAll 清空所有实例', () async {
      const sites = [
        TvBoxSite(
          key: 'site-a',
          name: 'Site A',
          type: 0,
          api: 'https://a.example.com/api',
        ),
        TvBoxSite(
          key: 'site-b',
          name: 'Site B',
          type: 1,
          api: 'https://b.example.com/api',
        ),
      ];

      await registry.createFromSites(sites);
      expect(registry.all.length, 2);

      registry.disposeAll();

      expect(registry.all, isEmpty);
      expect(registry.get('site-a'), isNull);
      expect(registry.get('site-b'), isNull);
    });

    test('createFromSites 批量创建', () async {
      const sites = [
        TvBoxSite(
          key: 'batch-cms',
          name: 'Batch CMS',
          type: 0,
          api: 'https://cms.example.com/api',
        ),
        TvBoxSite(
          key: 'batch-json',
          name: 'Batch JSON',
          type: 1,
          api: 'https://json.example.com/api',
        ),
        TvBoxSite(
          key: 'batch-xpath',
          name: 'Batch XPath',
          type: 3,
          api: 'https://xpath.example.com',
        ),
      ];

      final spiders = await registry.createFromSites(sites);

      expect(spiders.length, 3);
      expect(spiders[0], isA<CmsSpider>());
      expect(spiders[1], isA<JsonSpider>());
      expect(spiders[2], isA<XpathSpider>());
    });

    test('register 自定义工厂', () async {
      const site = TvBoxSite(
        key: 'custom-site',
        name: 'Custom Site',
        type: 99,
        api: 'https://custom.example.com',
      );

      var factoryCalled = false;
      registry.register('custom-site', (s) {
        factoryCalled = true;
        expect(s.key, 'custom-site');
        return _FakeSpider(site: s);
      });

      final spider = await registry.createFromSite(site);

      expect(factoryCalled, isTrue);
      expect(spider, isA<_FakeSpider>());
      expect(spider!.key, 'custom-site');
    });

    test('ext 为 URL 时解析为 extUrl', () async {
      const site = TvBoxSite(
        key: 'ext-url-site',
        name: 'Ext URL Site',
        type: 1,
        api: 'https://json.example.com/api',
        ext: 'https://ext.example.com/config.json',
      );

      final spider = await registry.createFromSite(site);
      expect(spider, isA<JsonSpider>());
    });

    test('ext 为 JSON 字符串时解析为配置映射', () async {
      const site = TvBoxSite(
        key: 'ext-json-site',
        name: 'Ext JSON Site',
        type: 1,
        api: 'https://json.example.com/api',
        ext: '{"homeUrl":"https://example.com/home"}',
      );

      final spider = await registry.createFromSite(site);
      expect(spider, isA<JsonSpider>());
    });

    test('ext 为普通字符串时解析为 ext', () async {
      const site = TvBoxSite(
        key: 'ext-plain-site',
        name: 'Ext Plain Site',
        type: 1,
        api: 'https://json.example.com/api',
        ext: 'plain-ext-value',
      );

      final spider = await registry.createFromSite(site);
      expect(spider, isA<JsonSpider>());
    });
  });
}

class _FakeSpider implements SpiderAdapter {
  @override
  final TvBoxSite site;

  _FakeSpider({required this.site});

  @override
  String get key => site.key;

  @override
  String get name => site.name;

  @override
  SpiderType get type => SpiderType.site;

  @override
  bool get isSearchSupported => false;

  @override
  Future<void> init(Map<String, dynamic> config) async {}

  @override
  Future<SpiderHomeResult> homeContent({int page = 1}) async =>
      const SpiderHomeResult();

  @override
  Future<SpiderListResult> categoryContent({
    required String tid,
    int page = 1,
    Map<String, String>? filter,
  }) async =>
      const SpiderListResult();

  @override
  Future<SpiderDetailResult> detailContent({required String id}) async =>
      const SpiderDetailResult();

  @override
  Future<SpiderListResult> searchContent({
    required String keyword,
    int page = 1,
  }) async =>
      const SpiderListResult();

  @override
  Future<SpiderPlayResult> playerContent({
    required String flag,
    required String id,
  }) async =>
      const SpiderPlayResult();

  @override
  void dispose() {}
}
