import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/tvbox_config_parser.dart';

void main() {
  const parser = TvBoxConfigParser();

  group('TvBoxConfigParser', () {
    test('解析最小空配置', () {
      final config = parser.parse(<String, dynamic>{});
      expect(config.spiderUrl, isNull);
      expect(config.sites, isEmpty);
      expect(config.lives, isEmpty);
      expect(config.flags, isEmpty);
    });

    test('解析无 md5 的 spider URL', () {
      final config = parser.parse(<String, dynamic>{
        'spider': 'https://example.com/spider.jar',
      });
      expect(config.spiderUrl, 'https://example.com/spider.jar');
    });

    test('解析带 md5 的 spider URL', () {
      final config = parser.parse(<String, dynamic>{
        'spider': 'https://example.com/spider.jar;abc123',
      });
      expect(config.spiderUrl, 'https://example.com/spider.jar');
    });

    test('解析 sites 数组（含 type 0 和 type 3）', () {
      final config = parser.parse(<String, dynamic>{
        'sites': [
          {
            'key': 'cms',
            'name': 'CMS站点',
            'type': 0,
            'api': 'https://cms.example.com/api',
            'ext': '{"categories": "电影"}',
            'jar': 'https://example.com/cms.jar',
            'playerType': 1,
          },
          {
            'key': 'xpath',
            'name': 'XPath站点',
            'type': 3,
            'api': 'csp_XPath',
          },
        ],
      });
      expect(config.sites.length, 2);

      final cms = config.sites[0];
      expect(cms.key, 'cms');
      expect(cms.name, 'CMS站点');
      expect(cms.type, 0);
      expect(cms.api, 'https://cms.example.com/api');
      expect(cms.ext, '{"categories": "电影"}');
      expect(cms.jar, 'https://example.com/cms.jar');
      expect(cms.playerType, 1);

      final xpath = config.sites[1];
      expect(xpath.key, 'xpath');
      expect(xpath.type, 3);
      expect(xpath.api, 'csp_XPath');
      expect(xpath.ext, isNull);
      expect(xpath.jar, isNull);
      expect(xpath.playerType, isNull);
    });

    test('解析 lives 数组', () {
      final config = parser.parse(<String, dynamic>{
        'lives': [
          {
            'name': '央视直播',
            'type': '0',
            'url': 'https://example.com/cctv.m3u',
            'playerType': 1,
          },
          {
            'name': '卫视直播',
            'type': '1',
            'url': 'https://example.com/tv.m3u',
          },
        ],
      });
      expect(config.lives.length, 2);

      final cctv = config.lives[0];
      expect(cctv.name, '央视直播');
      expect(cctv.type, '0');
      expect(cctv.url, 'https://example.com/cctv.m3u');
      expect(cctv.playerType, 1);

      final satellite = config.lives[1];
      expect(satellite.name, '卫视直播');
      expect(satellite.type, '1');
      expect(satellite.url, 'https://example.com/tv.m3u');
      expect(satellite.playerType, isNull);
    });

    test('解析 flags 数组', () {
      final config = parser.parse(<String, dynamic>{
        'flags': ['youku', 'qq', 'iqiyi'],
      });
      expect(config.flags, ['youku', 'qq', 'iqiyi']);
    });

    test('type 为字符串 "3" 时正确解析为 int', () {
      final config = parser.parse(<String, dynamic>{
        'sites': [
          {
            'key': 'stringType',
            'name': '字符串类型',
            'type': '3',
            'api': 'csp_StringType',
          },
        ],
      });
      expect(config.sites.length, 1);
      expect(config.sites.first.type, 3);
    });

    test('缺失字段时优雅处理不抛异常', () {
      expect(
        () => parser.parse(<String, dynamic>{
          'spider': null,
          'sites': null,
          'lives': null,
          'flags': null,
        }),
        returnsNormally,
      );

      expect(
        () => parser.parse(<String, dynamic>{
          'sites': [
            {'key': 'incomplete'},
          ],
        }),
        returnsNormally,
      );

      final config = parser.parse(<String, dynamic>{
        'sites': [
          {'key': 'incomplete'},
        ],
      });
      expect(config.sites, isEmpty);
    });
  });
}
