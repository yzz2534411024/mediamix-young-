import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/models/video_models.dart';
import 'package:mediamix/features/video/services/spider/json_spider.dart';
import 'package:mediamix/features/video/services/spider/spider_adapter.dart';
import 'package:mediamix/features/video/services/spider/spider_models.dart';
import 'package:mediamix/features/video/services/spider/tvbox_config_parser.dart';

class _FakeAdapter implements HttpClientAdapter {
  final Map<String, Object> responses;

  _FakeAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final value = responses[path];
    if (value is Exception) {
      throw DioException(
        requestOptions: options,
        error: value,
        type: DioExceptionType.connectionError,
      );
    }
    final body = value is String ? value : jsonEncode(value);
    return ResponseBody.fromString(body, 200);
  }

  @override
  void close({bool force = false}) {}
}

Dio _createFakeDio(Map<String, Object> responses) {
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter(responses);
  return dio;
}

void main() {
  const site = TvBoxSite(
    key: 'test-json',
    name: '测试JSON站',
    type: 1,
    api: 'https://json.example.com/api',
  );

  group('JsonSpider', () {
    test('key/name 与配置一致', () {
      final spider = JsonSpider(site: site);
      expect(spider.key, 'test-json');
      expect(spider.name, '测试JSON站');
    });

    test('type 为 json', () {
      final spider = JsonSpider(site: site);
      expect(spider.type, SpiderType.json);
    });

    test('实现 SpiderAdapter 接口', () {
      final spider = JsonSpider(site: site);
      expect(spider, isA<SpiderAdapter>());
    });

    test('init 空配置不抛异常', () async {
      final spider = JsonSpider(site: site);
      await expectLater(spider.init({}), completes);
    });

    test('init extUrl 失败时优雅处理', () async {
      final dio = _createFakeDio({
        'https://ext.example.com/config.json': Exception('network error'),
      });
      final spider = JsonSpider(site: site, dio: dio);
      await expectLater(
        spider.init({'extUrl': 'https://ext.example.com/config.json'}),
        completes,
      );
    });

    test('homeContent 使用 homeUrl 并解析列表', () async {
      final dio = _createFakeDio({
        'https://json.example.com/home': {
          'data': {
            'list': [
              {'title': '影片1', 'id': '1', 'cover': 'https://a.com/1.jpg'},
            ],
          },
        },
      });
      final spider = JsonSpider(site: site, dio: dio);
      await spider.init({
        'homeUrl': 'https://json.example.com/home',
        'listPath': r'$.data.list',
        'fieldMap': {
          'vod_name': 'title',
          'vod_id': 'id',
          'vod_pic': 'cover',
        },
      });

      final result = await spider.homeContent();
      expect(result.recommend.length, 1);
      expect(result.recommend.first.vodName, '影片1');
      expect(result.recommend.first.vodId, '1');
      expect(result.recommend.first.vodPic, 'https://a.com/1.jpg');
      expect(result.recommend.first.sourceKey, 'test-json');
    });

    test('homeContent 使用 site.api 作为 fallback', () async {
      final dio = _createFakeDio({
        'https://json.example.com/api': {
          'list': [
            {'vod_id': '2', 'vod_name': '影片2'},
          ],
        },
      });
      final spider = JsonSpider(site: site, dio: dio);
      await spider.init({'listPath': r'$.list'});

      final result = await spider.homeContent();
      expect(result.recommend.length, 1);
      expect(result.recommend.first.vodId, '2');
    });

    test('categoryContent 替换 {tid} 和 {pg}', () async {
      final dio = _createFakeDio({
        'https://json.example.com/list?type=10&page=3': {
          'data': {
            'list': [
              {'vod_id': 'c1', 'vod_name': '分类影片'},
            ],
          },
        },
      });
      final spider = JsonSpider(site: site, dio: dio);
      await spider.init({
        'cateUrl': 'https://json.example.com/list?type={tid}&page={pg}',
        'listPath': r'$.data.list',
      });

      final result = await spider.categoryContent(tid: '10', page: 3);
      expect(result.list.length, 1);
      expect(result.list.first.vodId, 'c1');
      expect(result.page, 3);
    });

    test('detailContent 替换 {id} 并解析详情', () async {
      final dio = _createFakeDio({
        'https://json.example.com/detail/123': {
          'data': {
            'item': {
              'title': '详情影片',
              'id': '123',
              'desc': '简介',
              'source': '源A\$\$\$源B',
              'urls': '第1集\$url1#第2集\$url2\$\$\$第1集\$url3',
            },
          },
        },
      });
      final spider = JsonSpider(site: site, dio: dio);
      await spider.init({
        'detailUrl': 'https://json.example.com/detail/{id}',
        'detailPath': r'$.data.item',
        'fieldMap': {
          'vod_name': 'title',
          'vod_id': 'id',
          'vod_content': 'desc',
          'vod_play_from': 'source',
          'vod_play_url': 'urls',
        },
      });

      final result = await spider.detailContent(id: '123');
      expect(result.detail, isNotNull);
      expect(result.detail!.vodName, '详情影片');
      expect(result.detail!.vodContent, '简介');
      expect(result.detail!.playSources.length, 2);
      expect(result.detail!.playSources.first.name, '源A');
      expect(result.detail!.playSources.first.episodes.length, 2);
      expect(result.detail!.playSources.first.episodes.first.name, '第1集');
      expect(result.detail!.playSources.first.episodes.first.url, 'url1');
      expect(result.detail!.playSources.last.name, '源B');
      expect(result.detail!.playSources.last.episodes.first.url, 'url3');
    });

    test('searchContent 替换 {wd} 和 {pg}', () async {
      final dio = _createFakeDio({
        'https://json.example.com/search?q=hello&page=2': {
          'data': {
            'list': [
              {'vod_id': 's1', 'vod_name': '搜索影片'},
            ],
          },
        },
      });
      final spider = JsonSpider(site: site, dio: dio);
      await spider.init({
        'searchUrl': 'https://json.example.com/search?q={wd}&page={pg}',
        'listPath': r'$.data.list',
      });

      final result = await spider.searchContent(keyword: 'hello', page: 2);
      expect(result.list.length, 1);
      expect(result.list.first.vodName, '搜索影片');
    });

    test('playerContent 根据 urlPath 提取播放地址', () async {
      final dio = _createFakeDio({
        'https://json.example.com/play/1': {
          'data': {'url': 'https://play.example.com/video.m3u8'},
        },
      });
      final spider = JsonSpider(site: site, dio: dio);
      await spider.init({
        'playUrl': {
          'urlPath': r'$.data.url',
          'parse': '0',
        },
      });

      final result = await spider.playerContent(
        flag: '测试线路',
        id: 'https://json.example.com/play/1',
      );
      expect(result.url, 'https://play.example.com/video.m3u8');
      expect(result.parse, '0');
      expect(result.needsParse, isFalse);
    });

    test('playerContent 无 urlPath 时直接返回 id', () async {
      final spider = JsonSpider(site: site);
      await spider.init({});

      final result = await spider.playerContent(
        flag: '测试线路',
        id: 'https://play.example.com/direct.m3u8',
      );
      expect(result.url, 'https://play.example.com/direct.m3u8');
      expect(result.parse, '0');
    });

    test('init 加载 extUrl 远程配置', () async {
      final dio = _createFakeDio({
        'https://ext.example.com/config.json': {
          'homeUrl': 'https://json.example.com/home2',
          'listPath': r'$.data.list',
        },
        'https://json.example.com/home2': {
          'data': {'list': <dynamic>[]},
        },
      });
      final spider = JsonSpider(site: site, dio: dio);
      await spider.init({'extUrl': 'https://ext.example.com/config.json'});

      final result = await spider.homeContent();
      // homeUrl should be overwritten to home2
      expect(result.recommend, isEmpty);
    });

    test('字符串 JSON 响应也能解析', () async {
      final dio = _createFakeDio({
        'https://json.example.com/api': jsonEncode({
          'list': [
            {'vod_id': 'str1', 'vod_name': '字符串响应'},
          ],
        }),
      });
      final spider = JsonSpider(site: site, dio: dio);
      await spider.init({'listPath': r'$.list'});

      final result = await spider.homeContent();
      expect(result.recommend.length, 1);
      expect(result.recommend.first.vodName, '字符串响应');
    });
  });
}
