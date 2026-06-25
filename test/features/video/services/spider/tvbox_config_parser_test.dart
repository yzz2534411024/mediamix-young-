import 'dart:convert';

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

    test('searchable/quickSearch/changeable 为字符串 "true"/"false" 时正确解析', () {
      final config = parser.parse(<String, dynamic>{
        'sites': [
          {
            'key': 'boolStr',
            'name': '布尔字符串站',
            'type': 3,
            'api': 'csp_BoolStr',
            'searchable': 'true',
            'quickSearch': 'false',
            'changeable': 'true',
          },
        ],
      });
      expect(config.sites.length, 1);
      expect(config.sites.first.searchable, isTrue);
      expect(config.sites.first.quickSearch, isFalse);
      expect(config.sites.first.changeable, isTrue);
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

    group('ext 字段类型处理', () {
      test('ext 为 JSON 对象时序列化为 JSON 字符串', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'cloud',
              'name': '云盘站',
              'type': 3,
              'api': 'csp_CloudDrive',
              'ext': {'Cloud-drive': 'tvfan/Cloud-drive.txt'},
            },
          ],
        });
        expect(config.sites.length, 1);
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['Cloud-drive'], 'tvfan/Cloud-drive.txt');
      });

      test('ext 为 JSON 数组时序列化为 JSON 字符串', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'arr',
              'name': '数组站',
              'type': 3,
              'api': 'csp_ArraySite',
              'ext': ['item1', 'item2'],
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as List;
        expect(decoded, ['item1', 'item2']);
      });

      test('ext 为普通字符串时行为不变', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'str',
              'name': '字符串站',
              'type': 0,
              'api': 'https://example.com/api',
              'ext': '{"token":"abc123"}',
            },
          ],
        });
        expect(config.sites.first.ext, '{"token":"abc123"}');
      });

      test('ext 为 null 时返回 null', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'noext',
              'name': '无ext站',
              'type': 0,
              'api': 'https://example.com/api',
            },
          ],
        });
        expect(config.sites.first.ext, isNull);
      });

      test('ext 为嵌套 JSON 对象时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'nested',
              'name': '嵌套站',
              'type': 3,
              'api': 'csp_Nested',
              'ext': {
                'site': {'url': 'https://example.com', 'token': 'xyz'},
                'categories': ['电影', '电视剧'],
              },
            },
          ],
        });
        final ext = config.sites.first.ext;
        expect(ext, isNotNull);
        final decoded = jsonDecode(ext!) as Map;
        expect((decoded['site'] as Map)['url'], 'https://example.com');
        expect(decoded['categories'], ['电影', '电视剧']);
      });

      test('ext 为 int 类型时转为字符串', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'intExt',
              'name': 'IntExt站',
              'type': 0,
              'api': 'https://example.com/api',
              'ext': 12345,
            },
          ],
        });
        expect(config.sites.first.ext, '12345');
      });

      test('ext 为 bool 类型时转为字符串', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'boolExt',
              'name': 'BoolExt站',
              'type': 0,
              'api': 'https://example.com/api',
              'ext': true,
            },
          ],
        });
        expect(config.sites.first.ext, 'true');
      });

      test('ext 为 double 类型时转为字符串', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'doubleExt',
              'name': 'DoubleExt站',
              'type': 0,
              'api': 'https://example.com/api',
              'ext': 3.14,
            },
          ],
        });
        expect(config.sites.first.ext, '3.14');
      });

      test('ext 为空字符串时返回 null', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'emptyExt',
              'name': '空Ext站',
              'type': 0,
              'api': 'https://example.com/api',
              'ext': '',
            },
          ],
        });
        expect(config.sites.first.ext, isNull);
      });

      test('ext 为纯空白字符串时返回 null', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'whitespaceExt',
              'name': '空白Ext站',
              'type': 0,
              'api': 'https://example.com/api',
              'ext': '   ',
            },
          ],
        });
        expect(config.sites.first.ext, isNull);
      });

      test('ext 为空数组时序列化为 "[]"', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'emptyArr',
              'name': '空数组站',
              'type': 3,
              'api': 'csp_EmptyArr',
              'ext': <dynamic>[],
            },
          ],
        });
        expect(config.sites.first.ext, '[]');
      });

      test('ext 为空对象时序列化为 "{}"', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'emptyMap',
              'name': '空对象站',
              'type': 3,
              'api': 'csp_EmptyMap',
              'ext': <String, dynamic>{},
            },
          ],
        });
        expect(config.sites.first.ext, '{}');
      });

      test('ext 为混合类型数组时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'mixedArr',
              'name': '混合数组站',
              'type': 3,
              'api': 'csp_MixedArr',
              'ext': [
                'string',
                123,
                {'key': 'value'},
                true,
              ],
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as List;
        expect(decoded[0], 'string');
        expect(decoded[1], 123);
        expect((decoded[2] as Map)['key'], 'value');
        expect(decoded[3], true);
      });

      test('ext 为深层嵌套结构时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'deepNested',
              'name': '深层嵌套站',
              'type': 3,
              'api': 'csp_DeepNested',
              'ext': {
                'level1': {
                  'level2': {
                    'level3': {
                      'data': ['a', 'b', 'c'],
                      'count': 3,
                    },
                  },
                },
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        final level1 = decoded['level1'] as Map;
        final level2 = level1['level2'] as Map;
        final level3 = level2['level3'] as Map;
        expect(level3['data'], ['a', 'b', 'c']);
        expect(level3['count'], 3);
      });

      test('ext 包含特殊字符和 Unicode 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'unicode',
              'name': '特殊字符站',
              'type': 3,
              'api': 'csp_Unicode',
              'ext': {
                'chinese': '中文测试',
                'emoji': '🎬📺',
                'special': '"quotes" & <brackets>',
                'newline': 'line1\nline2',
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['chinese'], '中文测试');
        expect(decoded['emoji'], '🎬📺');
        expect(decoded['special'], '"quotes" & <brackets>');
        expect(decoded['newline'], 'line1\nline2');
      });

      test('ext 为 JSON 格式字符串时保持原样', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'jsonStr',
              'name': 'JSON字符串站',
              'type': 0,
              'api': 'https://example.com/api',
              'ext': '{"token":"abc123","count":5}',
            },
          ],
        });
        // 字符串类型的 ext 应保持原样，不进行二次序列化
        expect(config.sites.first.ext, '{"token":"abc123","count":5}');
      });

      test('ext 为 URL 字符串时保持原样', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'urlExt',
              'name': 'URL Ext站',
              'type': 0,
              'api': 'https://example.com/api',
              'ext': 'https://example.com/config.json?token=abc&lang=zh',
            },
          ],
        });
        expect(config.sites.first.ext, 'https://example.com/config.json?token=abc&lang=zh');
      });

      test('ext 为本地文件路径时保持原样', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'pathExt',
              'name': '路径Ext站',
              'type': 0,
              'api': 'https://example.com/api',
              'ext': './config/site.json',
            },
          ],
        });
        expect(config.sites.first.ext, './config/site.json');
      });

      test('ext 为含中文键名的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'cnKey',
              'name': '中文键名站',
              'type': 3,
              'api': 'csp_CnKey',
              'ext': {
                '云盘': 'tvfan/cloud.txt',
                '接口地址': 'https://example.com/api',
                '分类': ['电影', '电视剧', '综艺'],
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['云盘'], 'tvfan/cloud.txt');
        expect(decoded['接口地址'], 'https://example.com/api');
        expect(decoded['分类'], ['电影', '电视剧', '综艺']);
      });

      test('ext 为含数字字符串键的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'numKey',
              'name': '数字键站',
              'type': 3,
              'api': 'csp_NumKey',
              'ext': {
                '0': 'zero',
                '1': 'one',
                '99': 'ninety-nine',
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['0'], 'zero');
        expect(decoded['1'], 'one');
        expect(decoded['99'], 'ninety-nine');
      });

      test('ext 为含特殊字符键的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'specialKey',
              'name': '特殊键站',
              'type': 3,
              'api': 'csp_SpecialKey',
              'ext': {
                'Cloud-drive': 'tvfan/cloud.txt',
                'api_key': 'abc123',
                'user.name': 'test',
                'path/to': 'value',
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['Cloud-drive'], 'tvfan/cloud.txt');
        expect(decoded['api_key'], 'abc123');
        expect(decoded['user.name'], 'test');
        expect(decoded['path/to'], 'value');
      });

      test('ext 为大型 JSON 对象时正确序列化', () {
        // 生成含 50 个键值对的大型 Map
        final largeMap = <String, dynamic>{};
        for (var i = 0; i < 50; i++) {
          largeMap['key_$i'] = 'value_$i';
        }
        largeMap['nested'] = {'a': 1, 'b': 2};
        largeMap['array'] = [1, 2, 3, 4, 5];

        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'large',
              'name': '大型Ext站',
              'type': 3,
              'api': 'csp_Large',
              'ext': largeMap,
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded.length, 52); // 50 + nested + array
        expect(decoded['key_0'], 'value_0');
        expect(decoded['key_49'], 'value_49');
        expect((decoded['nested'] as Map)['a'], 1);
        expect(decoded['array'], [1, 2, 3, 4, 5]);
      });

      test('ext 为 Map 数组时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'mapArr',
              'name': 'Map数组站',
              'type': 3,
              'api': 'csp_MapArr',
              'ext': [
                {'name': '源1', 'url': 'https://example1.com'},
                {'name': '源2', 'url': 'https://example2.com'},
                {'name': '源3', 'url': 'https://example3.com'},
              ],
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as List;
        expect(decoded.length, 3);
        expect((decoded[0] as Map)['name'], '源1');
        expect((decoded[1] as Map)['url'], 'https://example2.com');
        expect((decoded[2] as Map)['name'], '源3');
      });

      test('ext 为含 null 值的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'nullVal',
              'name': 'Null值站',
              'type': 3,
              'api': 'csp_NullVal',
              'ext': {
                'valid': 'value',
                'empty': null,
                'another': 'data',
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['valid'], 'value');
        expect(decoded['empty'], isNull);
        expect(decoded['another'], 'data');
      });

      test('ext 为含 null 元素的 List 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'nullList',
              'name': 'Null列表站',
              'type': 3,
              'api': 'csp_NullList',
              'ext': ['first', null, 'third', null, 42],
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as List;
        expect(decoded.length, 5);
        expect(decoded[0], 'first');
        expect(decoded[1], isNull);
        expect(decoded[2], 'third');
        expect(decoded[3], isNull);
        expect(decoded[4], 42);
      });

      test('ext 为含布尔值的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'boolMap',
              'name': '布尔Map站',
              'type': 3,
              'api': 'csp_BoolMap',
              'ext': {
                'enabled': true,
                'disabled': false,
                'name': 'test',
                'count': 10,
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['enabled'], isTrue);
        expect(decoded['disabled'], isFalse);
        expect(decoded['name'], 'test');
        expect(decoded['count'], 10);
      });

      test('ext 为含各种数值类型的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'numMap',
              'name': '数值Map站',
              'type': 3,
              'api': 'csp_NumMap',
              'ext': {
                'intVal': 42,
                'doubleVal': 3.14159,
                'negativeVal': -100,
                'zeroVal': 0,
                'largeVal': 999999999,
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['intVal'], 42);
        expect(decoded['doubleVal'], 3.14159);
        expect(decoded['negativeVal'], -100);
        expect(decoded['zeroVal'], 0);
        expect(decoded['largeVal'], 999999999);
      });

      test('ext 为含数组值的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'arrValMap',
              'name': '数组值Map站',
              'type': 3,
              'api': 'csp_ArrValMap',
              'ext': {
                'categories': ['电影', '电视剧', '综艺', '动漫'],
                'years': [2020, 2021, 2022, 2023, 2024],
                'flags': ['youku', 'iqiyi', 'tencent'],
                'empty': [],
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['categories'], ['电影', '电视剧', '综艺', '动漫']);
        expect(decoded['years'], [2020, 2021, 2022, 2023, 2024]);
        expect(decoded['flags'], ['youku', 'iqiyi', 'tencent']);
        expect(decoded['empty'], []);
      });

      test('ext 为含嵌套数组和对象的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'complexMap',
              'name': '复杂Map站',
              'type': 3,
              'api': 'csp_ComplexMap',
              'ext': {
                'sites': [
                  {'name': '源1', 'enabled': true, 'tags': ['高清', 'VIP']},
                  {'name': '源2', 'enabled': false, 'tags': ['标清']},
                ],
                'config': {
                  'timeout': 30,
                  'retry': 3,
                  'headers': {'User-Agent': 'test', 'Accept': '*/*'},
                },
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        final sites = decoded['sites'] as List;
        expect(sites.length, 2);
        expect((sites[0] as Map)['name'], '源1');
        expect((sites[0] as Map)['enabled'], isTrue);
        expect((sites[0] as Map)['tags'], ['高清', 'VIP']);
        final config2 = decoded['config'] as Map;
        expect(config2['timeout'], 30);
        expect((config2['headers'] as Map)['User-Agent'], 'test');
      });

      test('ext 为含空字符串值的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'emptyStrVal',
              'name': '空字符串值站',
              'type': 3,
              'api': 'csp_EmptyStrVal',
              'ext': {
                'valid': 'data',
                'empty1': '',
                'empty2': '',
                'another': 'value',
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['valid'], 'data');
        expect(decoded['empty1'], '');
        expect(decoded['empty2'], '');
        expect(decoded['another'], 'value');
      });

      test('ext 为单键值对 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'singleKV',
              'name': '单键值站',
              'type': 3,
              'api': 'csp_SingleKV',
              'ext': {'token': 'abc123xyz'},
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded.length, 1);
        expect(decoded['token'], 'abc123xyz');
      });

      test('ext 为中等大小 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'mediumMap',
              'name': '中等Map站',
              'type': 3,
              'api': 'csp_MediumMap',
              'ext': {
                'site1': 'https://site1.com',
                'site2': 'https://site2.com',
                'site3': 'https://site3.com',
                'token': 'abc123',
                'timeout': 30,
                'retry': 3,
                'enabled': true,
                'categories': ['电影', '电视剧'],
                'quality': '1080p',
                'language': 'zh-CN',
                'region': 'CN',
                'version': '1.0.0',
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded.length, 12);
        expect(decoded['site1'], 'https://site1.com');
        expect(decoded['token'], 'abc123');
        expect(decoded['timeout'], 30);
        expect(decoded['enabled'], isTrue);
        expect(decoded['categories'], ['电影', '电视剧']);
        expect(decoded['version'], '1.0.0');
      });

      test('ext 为含所有类型值的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'allTypes',
              'name': '全类型站',
              'type': 3,
              'api': 'csp_AllTypes',
              'ext': {
                'stringVal': 'hello',
                'intVal': 42,
                'doubleVal': 3.14,
                'boolTrueVal': true,
                'boolFalseVal': false,
                'nullVal': null,
                'arrayVal': [1, 'two', true],
                'objectVal': {'nested': 'value'},
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['stringVal'], 'hello');
        expect(decoded['intVal'], 42);
        expect(decoded['doubleVal'], 3.14);
        expect(decoded['boolTrueVal'], isTrue);
        expect(decoded['boolFalseVal'], isFalse);
        expect(decoded['nullVal'], isNull);
        expect(decoded['arrayVal'], [1, 'two', true]);
        expect((decoded['objectVal'] as Map)['nested'], 'value');
      });

      test('ext 为含空数组值的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'emptyArrVal',
              'name': '空数组值站',
              'type': 3,
              'api': 'csp_EmptyArrVal',
              'ext': {
                'valid': 'data',
                'emptyArr1': [],
                'emptyArr2': <dynamic>[],
                'another': 'value',
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['valid'], 'data');
        expect(decoded['emptyArr1'], []);
        expect(decoded['emptyArr2'], []);
        expect(decoded['another'], 'value');
      });

      test('ext 为含空对象值的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'emptyObjVal',
              'name': '空对象值站',
              'type': 3,
              'api': 'csp_EmptyObjVal',
              'ext': {
                'valid': 'data',
                'emptyObj1': {},
                'emptyObj2': <String, dynamic>{},
                'another': 'value',
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['valid'], 'data');
        expect(decoded['emptyObj1'], {});
        expect(decoded['emptyObj2'], {});
        expect(decoded['another'], 'value');
      });

      test('ext 为含嵌套空容器值的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'nestedEmpty',
              'name': '嵌套空容器站',
              'type': 3,
              'api': 'csp_NestedEmpty',
              'ext': {
                'emptyArrInMap': {'items': []},
                'emptyObjInMap': {'config': {}},
                'emptyArrInArr': [[]],
                'emptyObjInArr': [{}],
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect((decoded['emptyArrInMap'] as Map)['items'], []);
        expect((decoded['emptyObjInMap'] as Map)['config'], {});
        expect(decoded['emptyArrInArr'], [[]]);
        expect(decoded['emptyObjInArr'], [{}]);
      });

      test('ext 为含超长字符串值的 Map 时正确序列化', () {
        // 生成 1000 字符的长字符串
        final longString = 'a' * 1000;
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'longStr',
              'name': '长字符串站',
              'type': 3,
              'api': 'csp_LongStr',
              'ext': {
                'short': 'value',
                'long': longString,
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['short'], 'value');
        expect(decoded['long'], longString);
        expect((decoded['long'] as String).length, 1000);
      });

      test('ext 为含 JSON 特殊字符的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'jsonChars',
              'name': 'JSON特殊字符站',
              'type': 3,
              'api': 'csp_JsonChars',
              'ext': {
                'quotes': 'He said "hello"',
                'backslash': 'path\\to\\file',
                'newline': 'line1\nline2',
                'tab': 'col1\tcol2',
                'unicode': '\u0041\u0042\u0043', // ABC
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['quotes'], 'He said "hello"');
        expect(decoded['backslash'], 'path\\to\\file');
        expect(decoded['newline'], 'line1\nline2');
        expect(decoded['tab'], 'col1\tcol2');
        expect(decoded['unicode'], 'ABC');
      });

      test('ext 为含日期时间字符串的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'dateTime',
              'name': '日期时间站',
              'type': 3,
              'api': 'csp_DateTime',
              'ext': {
                'isoDate': '2024-01-15T10:30:00Z',
                'simpleDate': '2024-01-15',
                'timeOnly': '10:30:00',
                'timestamp': '1705312200000',
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['isoDate'], '2024-01-15T10:30:00Z');
        expect(decoded['simpleDate'], '2024-01-15');
        expect(decoded['timeOnly'], '10:30:00');
        expect(decoded['timestamp'], '1705312200000');
      });

      test('ext 为含特殊格式字符串的 Map 时正确序列化', () {
        final config = parser.parse(<String, dynamic>{
          'sites': [
            {
              'key': 'formatStr',
              'name': '格式字符串站',
              'type': 3,
              'api': 'csp_FormatStr',
              'ext': {
                'email': 'user@example.com',
                'phone': '+86-138-0000-0000',
                'ipv4': '192.168.1.1',
                'ipv6': '2001:0db8:85a3:0000:0000:8a2e:0370:7334',
                'uuid': '550e8400-e29b-41d4-a716-446655440000',
              },
            },
          ],
        });
        expect(config.sites.first.ext, isNotNull);
        final decoded = jsonDecode(config.sites.first.ext!) as Map;
        expect(decoded['email'], 'user@example.com');
        expect(decoded['phone'], '+86-138-0000-0000');
        expect(decoded['ipv4'], '192.168.1.1');
        expect(decoded['ipv6'], '2001:0db8:85a3:0000:0000:8a2e:0370:7334');
        expect(decoded['uuid'], '550e8400-e29b-41d4-a716-446655440000');
      });
    });

    test('饭太硬真实配置片段集成测试', () {
      final fanTaiYeConfig = <String, dynamic>{
        'spider': 'https://example.com/fanTaiYe.jar;md5abc',
        'sites': [
          {
            'key': 'CloudDrive',
            'name': '云盘',
            'type': 3,
            'api': 'csp_CloudDrive',
            'ext': {'Cloud-drive': 'tvfan/Cloud-drive.txt'},
            'searchable': 1,
            'quickSearch': 0,
            'changeable': 0,
          },
          {
            'key': 'Wogg',
            'name': '玩偶哥哥',
            'type': 3,
            'api': 'csp_Wogg',
            'ext': {'site': 'https://wogg.example.com'},
          },
          {
            'key': 'Czsapp',
            'name': '厂长资源',
            'type': 3,
            'api': 'csp_Czsapp',
            'ext': 'https://example.com/ext.json',
          },
          {
            'key': 'SimpleStr',
            'name': '简单字符串',
            'type': 0,
            'api': 'https://simple.example.com/api',
          },
        ],
        'flags': ['youku', 'qq', 'iqiyi'],
      };

      final config = parser.parse(fanTaiYeConfig);

      // spider 正确解析（去掉 md5）
      expect(config.spiderUrl, 'https://example.com/fanTaiYe.jar');

      // 4 个站点全部解析
      expect(config.sites.length, 4);

      // ext 为 JSON 对象的站点 — CloudDrive
      final cloudDrive = config.sites[0];
      expect(cloudDrive.key, 'CloudDrive');
      expect(cloudDrive.ext, isNotNull);
      final cloudExt = jsonDecode(cloudDrive.ext!) as Map<String, dynamic>;
      expect(cloudExt['Cloud-drive'], 'tvfan/Cloud-drive.txt');

      // ext 为 JSON 对象的站点 — Wogg
      final wogg = config.sites[1];
      expect(wogg.ext, isNotNull);
      final woggExt = jsonDecode(wogg.ext!) as Map<String, dynamic>;
      expect(woggExt['site'], 'https://wogg.example.com');

      // ext 为普通字符串的站点 — Czsapp
      final czsapp = config.sites[2];
      expect(czsapp.ext, 'https://example.com/ext.json');

      // ext 为 null 的站点 — SimpleStr
      final simple = config.sites[3];
      expect(simple.ext, isNull);

      // flags
      expect(config.flags, ['youku', 'qq', 'iqiyi']);
    });
  });
}
