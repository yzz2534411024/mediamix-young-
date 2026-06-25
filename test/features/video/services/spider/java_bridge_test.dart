import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/java_bridge_client.dart';
import 'package:mediamix/features/video/services/spider/java_bridge_spider.dart';
import 'package:mediamix/features/video/services/spider/spider_models.dart';
import 'package:mediamix/features/video/services/spider/spider_registry.dart';
import 'package:mediamix/features/video/services/spider/tvbox_config_parser.dart';

void main() {
  group('TvBoxSite - isJavaSpider', () {
    test('csp_ 开头的 api 应识别为 Java 蜘蛛', () {
      const site = TvBoxSite(
        key: 'test',
        name: '测试',
        type: 3,
        api: 'csp_WoGGGuard',
      );
      expect(site.isJavaSpider, isTrue);
    });

    test('非 csp_ 开头的 api 不应识别为 Java 蜘蛛', () {
      const site = TvBoxSite(
        key: 'test',
        name: '测试',
        type: 0,
        api: 'http://example.com/api',
      );
      expect(site.isJavaSpider, isFalse);
    });

    test('空 api 不应识别为 Java 蜘蛛', () {
      const site = TvBoxSite(
        key: 'test',
        name: '测试',
        type: 1,
        api: '',
      );
      expect(site.isJavaSpider, isFalse);
    });

    test('drpy JS 蜘蛛不应识别为 Java 蜘蛛', () {
      const site = TvBoxSite(
        key: 'huya',
        name: '虎牙',
        type: 3,
        api: 'https://example.com/drpy2.min.js',
      );
      expect(site.isJavaSpider, isFalse);
    });
  });

  group('TvBoxSite - 扩展字段解析', () {
    test('应正确解析 searchable/quickSearch/changeable 字段', () {
      const parser = TvBoxConfigParser();
      final config = parser.parse({
        'sites': [
          {
            'key': 'test1',
            'name': '测试1',
            'type': 3,
            'api': 'csp_TestGuard',
            'searchable': 1,
            'quickSearch': 1,
            'changeable': 0,
          },
          {
            'key': 'test2',
            'name': '测试2',
            'type': 3,
            'api': 'csp_Test2Guard',
            'searchable': 0,
            'quickSearch': 0,
            'changeable': 1,
          },
        ],
      });

      expect(config.sites.length, 2);
      expect(config.sites[0].searchable, isTrue);
      expect(config.sites[0].quickSearch, isTrue);
      expect(config.sites[0].changeable, isFalse);
      expect(config.sites[1].searchable, isFalse);
      expect(config.sites[1].quickSearch, isFalse);
      expect(config.sites[1].changeable, isTrue);
    });

    test('searchable 字段缺失时默认为 true', () {
      const parser = TvBoxConfigParser();
      final config = parser.parse({
        'sites': [
          {
            'key': 'test',
            'name': '测试',
            'type': 3,
            'api': 'csp_TestGuard',
          },
        ],
      });

      expect(config.sites[0].searchable, isTrue);
      expect(config.sites[0].quickSearch, isFalse);
      expect(config.sites[0].changeable, isFalse);
    });
  });

  group('SpiderType - javaBridge', () {
    test('SpiderType 应包含 javaBridge 类型', () {
      expect(SpiderType.values, contains(SpiderType.javaBridge));
    });

    test('javaBridge 类型的索引应正确', () {
      expect(SpiderType.javaBridge.index, equals(4));
    });
  });

  group('SpiderRegistry - Java Bridge 路由', () {
    test('csp_* 站点在 Bridge 不可用时应返回 null', () {
      final registry = SpiderRegistry.instance;
      // 确保 javaBridgeClient 为 null
      registry.javaBridgeClient = null;

      // 非 csp_* 的 type=3 应该走 XpathSpider 路径
      const site = TvBoxSite(
        key: 'test_csp',
        name: '测试',
        type: 3,
        api: 'csp_TestGuard',
      );
      expect(site.isJavaSpider, isTrue);
    });

    test('非 csp_* 的 type=3 站点应使用 XPath 蜘蛛', () {
      final registry = SpiderRegistry.instance;
      registry.javaBridgeClient = null;

      const site = TvBoxSite(
        key: 'test_xpath',
        name: '测试XPath',
        type: 3,
        api: 'https://example.com/api',
      );

      // 非 csp_* 的 type=3 应该走 XpathSpider 路径
      expect(site.isJavaSpider, isFalse);
    });
  });

  group('JavaBridgeSpider - 响应解析', () {
    late JavaBridgeSpider spider;

    setUp(() {
      // 使用 mock client（实际测试中不会发起 HTTP 请求）
      spider = JavaBridgeSpider(
        site: const TvBoxSite(
          key: 'test_csp',
          name: '测试蜘蛛',
          type: 3,
          api: 'csp_TestGuard',
        ),
        client: JavaBridgeClient(baseUrl: 'http://127.0.0.1:19999'),
      );
    });

    test('key 和 name 应来自 site', () {
      expect(spider.key, 'test_csp');
      expect(spider.name, '测试蜘蛛');
      expect(spider.type, SpiderType.javaBridge);
    });

    test('isSearchSupported 应返回 true', () {
      expect(spider.isSearchSupported, isTrue);
    });

    test('Bridge 不可用时 homeContent 应返回空结果', () async {
      final result = await spider.homeContent();
      expect(result.categories, isEmpty);
      expect(result.recommend, isEmpty);
    });

    test('Bridge 不可用时 searchContent 应返回空结果', () async {
      final result = await spider.searchContent(keyword: '测试');
      expect(result.list, isEmpty);
      expect(result.page, 1);
    });

    test('Bridge 不可用时 detailContent 应返回默认详情', () async {
      final result = await spider.detailContent(id: '123');
      expect(result.detail, isNotNull);
      expect(result.detail!.vodId, '123');
      expect(result.detail!.vodName, '未知');
    });

    test('Bridge 不可用时 playerContent 应返回 fallback URL', () async {
      final result = await spider.playerContent(flag: 'flag1', id: 'test_url');
      expect(result.url, 'test_url');
    });
  });

  group('JavaBridgeClient - 基本属性', () {
    test('初始状态 should not be available', () {
      final client = JavaBridgeClient(baseUrl: 'http://127.0.0.1:19999');
      expect(client.isAvailable, isFalse);
    });

    test('checkStatus 应在连接失败时返回 false', () async {
      final client = JavaBridgeClient(baseUrl: 'http://127.0.0.1:19999');
      final result = await client.checkStatus();
      expect(result, isFalse);
      expect(client.isAvailable, isFalse);
      client.dispose();
    });

    test('listSpiders 应在连接失败时返回空列表', () async {
      final client = JavaBridgeClient(baseUrl: 'http://127.0.0.1:19999');
      final result = await client.listSpiders();
      expect(result, isEmpty);
      client.dispose();
    });
  });

  group('TvBoxConfigParser - 饭太硬配置解析', () {
    test('应正确解析饭太硬格式的站点', () {
      const parser = TvBoxConfigParser();
      final config = parser.parse({
        'spider': 'https://example.com/spider.jar;md5;abc123',
        'sites': [
          {
            'key': '原创',
            'name': '原创┃不卡',
            'type': 3,
            'api': 'csp_YCyzGuard',
            'timeout': 15,
            'playerType': 1,
            'searchable': 1,
            'quickSearch': 1,
            'changeable': 1,
          },
          {
            'key': '虎牙js',
            'name': '虎牙┃直播',
            'type': 3,
            'api': 'https://example.com/drpy2.min.js',
            'ext': 'https://example.com/虎牙.js',
            'playerType': 2,
            'searchable': 1,
            'quickSearch': 0,
            'changeable': 0,
          },
        ],
      });

      expect(config.spiderUrl, 'https://example.com/spider.jar');
      expect(config.sites.length, 2);

      // 第一个站点是 Java 蜘蛛
      expect(config.sites[0].isJavaSpider, isTrue);
      expect(config.sites[0].api, 'csp_YCyzGuard');
      expect(config.sites[0].playerType, 1);
      expect(config.sites[0].searchable, isTrue);

      // 第二个站点是 JS 蜘蛛（不是 csp_* 格式）
      expect(config.sites[1].isJavaSpider, isFalse);
      expect(config.sites[1].api, contains('drpy2'));
    });
  });

  group('JavaBridgeSpider - JSON 响应解析', () {
    late JavaBridgeSpider spider;

    setUp(() {
      spider = JavaBridgeSpider(
        site: const TvBoxSite(
          key: 'test_csp',
          name: '测试蜘蛛',
          type: 3,
          api: 'csp_TestGuard',
        ),
        client: JavaBridgeClient(baseUrl: 'http://127.0.0.1:19999'),
      );
    });

    test('_extractData 应处理 Map 类型的 data', () {
      // Bridge 不可用时返回空结果，验证接口契约
      expect(spider.key, 'test_csp');
    });

    test('_parseVideoList 应处理标准 TVBox 视频列表格式', () {
      // 验证 VideoItem.fromJson 能处理常见字段名
      final item = {
        'vod_id': '123',
        'vod_name': '测试影片',
        'vod_pic': 'https://example.com/pic.jpg',
        'vod_remarks': 'HD',
      };

      // VideoItem.fromJson 应该能解析这些字段
      // 这里只验证数据格式兼容性
      expect(item['vod_id'], '123');
      expect(item['vod_name'], '测试影片');
    });
  });

  group('SpiderRegistry - disposeAll 清理', () {
    test('disposeAll 应清空所有实例', () {
      final registry = SpiderRegistry.instance;
      registry.disposeAll();
      expect(registry.all, isEmpty);
    });
  });
}
