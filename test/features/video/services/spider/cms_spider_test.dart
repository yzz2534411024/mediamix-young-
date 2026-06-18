import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/models/video_models.dart';
import 'package:mediamix/features/video/services/spider/cms_spider.dart';
import 'package:mediamix/features/video/services/spider/spider_adapter.dart';
import 'package:mediamix/features/video/services/spider/spider_models.dart';
import 'package:mediamix/features/video/services/spider/tvbox_config_parser.dart';
import 'package:mediamix/features/video/services/tbox_api_service.dart';

class _FakeVideoApiService extends VideoApiService {
  _FakeVideoApiService() : super(dio: Dio());

  var clearAllCacheCalled = false;

  @override
  Future<List<VideoCategory>> fetchCategories(String apiUrl) async {
    return const [
      VideoCategory(typeId: 1, typePid: 0, typeName: '电影'),
      VideoCategory(typeId: 2, typePid: 0, typeName: '电视剧'),
    ];
  }

  @override
  Future<VideoListResponse> fetchVideoList(
    String apiUrl, {
    int page = 1,
    int? typeId,
  }) async {
    return VideoListResponse(
      list: [
        VideoItem(
          vodId: typeId == null ? 'home-1' : 'cat-$typeId',
          vodName: typeId == null ? '首页推荐' : '分类_$typeId',
        ),
      ],
      page: page,
      pageCount: 1,
      total: 1,
    );
  }

  @override
  Future<VideoDetail> fetchVideoDetail(
    String apiUrl,
    String vodId, {
    String sourceKey = '',
  }) async {
    return VideoDetail(
      vodId: vodId,
      vodName: '测试影片',
      sourceKey: sourceKey,
    );
  }

  @override
  Future<VideoListResponse> searchVideos(String apiUrl, String keyword) async {
    return VideoListResponse(
      list: [
        VideoItem(vodId: 'search-1', vodName: '搜索结果: $keyword'),
      ],
      page: 1,
      pageCount: 1,
      total: 1,
    );
  }

  @override
  void clearAllCache() {
    clearAllCacheCalled = true;
  }
}

void main() {
  const site = TvBoxSite(
    key: 'test-cms',
    name: '测试CMS站',
    type: 0,
    api: 'https://cms.example.com/api.php/provide/vod/',
  );

  group('CmsSpider', () {
    test('key/name 与配置一致', () {
      final spider = CmsSpider(site: site);
      expect(spider.key, 'test-cms');
      expect(spider.name, '测试CMS站');
    });

    test('type 为 cms', () {
      final spider = CmsSpider(site: site);
      expect(spider.type, SpiderType.cms);
    });

    test('isSearchSupported 为 true', () {
      final spider = CmsSpider(site: site);
      expect(spider.isSearchSupported, isTrue);
    });

    test('playerContent 返回直接播放 URL', () async {
      final spider = CmsSpider(site: site);
      final result = await spider.playerContent(
        flag: '测试线路',
        id: 'https://example.com/video.m3u8',
      );
      expect(result.url, 'https://example.com/video.m3u8');
      expect(result.parse, '0');
      expect(result.needsParse, isFalse);
    });

    test('init 为空实现且正常返回', () async {
      final spider = CmsSpider(site: site);
      await expectLater(spider.init({}), completes);
    });

    test('homeContent 调用 fetchCategories 和 fetchVideoList', () async {
      final api = _FakeVideoApiService();
      final spider = CmsSpider(site: site, apiService: api);
      final result = await spider.homeContent();

      expect(result.categories.length, 2);
      expect(result.categories.first.typeId, '1');
      expect(result.categories.first.typeName, '电影');
      expect(result.recommend.length, 1);
      expect(result.recommend.first.vodId, 'home-1');
      expect(result.classList, containsPair('1', <VideoItem>[]));
      expect(result.classList, containsPair('2', <VideoItem>[]));
    });

    test('categoryContent 使用 tid 作为 typeId', () async {
      final api = _FakeVideoApiService();
      final spider = CmsSpider(site: site, apiService: api);
      final result = await spider.categoryContent(tid: '2');

      expect(result.list.length, 1);
      expect(result.list.first.vodId, 'cat-2');
    });

    test('detailContent 使用 key 作为 sourceKey', () async {
      final api = _FakeVideoApiService();
      final spider = CmsSpider(site: site, apiService: api);
      final result = await spider.detailContent(id: '123');

      expect(result.detail, isNotNull);
      expect(result.detail!.vodId, '123');
      expect(result.detail!.sourceKey, 'test-cms');
    });

    test('searchContent 返回搜索结果', () async {
      final api = _FakeVideoApiService();
      final spider = CmsSpider(site: site, apiService: api);
      final result = await spider.searchContent(keyword: ' Flutter ');

      expect(result.list.length, 1);
      expect(result.list.first.vodName, '搜索结果:  Flutter ');
    });

    test('dispose 调用 clearAllCache', () {
      final api = _FakeVideoApiService();
      final spider = CmsSpider(site: site, apiService: api);
      spider.dispose();
      expect(api.clearAllCacheCalled, isTrue);
    });

    test('实现 SpiderAdapter 接口', () {
      final spider = CmsSpider(site: site);
      expect(spider, isA<SpiderAdapter>());
    });
  });
}
