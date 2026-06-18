import '../../models/video_models.dart';
import 'spider_adapter.dart';
import 'spider_models.dart';
import 'tvbox_config_parser.dart';
import '../tbox_api_service.dart';

/// CMS 采集站蜘蛛适配器
///
/// 基于 TVBox 站点配置，通过 [VideoApiService] 调用标准 CMS API。
class CmsSpider implements SpiderAdapter {
  final TvBoxSite site;
  final VideoApiService _apiService;

  CmsSpider({
    required this.site,
    VideoApiService? apiService,
  }) : _apiService = apiService ?? VideoApiService();

  @override
  String get key => site.key;

  @override
  String get name => site.name;

  @override
  SpiderType get type => SpiderType.cms;

  @override
  bool get isSearchSupported => true;

  @override
  Future<void> init(Map<String, dynamic> config) async {
    // CMS 蜘蛛无需额外初始化
  }

  @override
  Future<SpiderHomeResult> homeContent({int page = 1}) async {
    final categories = await _apiService.fetchCategories(site.api);
    final videoList = await _apiService.fetchVideoList(site.api, page: page);

    final spiderCategories = categories.map((c) {
      return SpiderCategory(
        typeId: c.typeId.toString(),
        typeName: c.typeName,
      );
    }).toList();

    final classList = <String, List<VideoItem>>{};
    for (final category in categories) {
      classList[category.typeId.toString()] = [];
    }

    return SpiderHomeResult(
      categories: spiderCategories,
      recommend: videoList.list,
      classList: classList,
    );
  }

  @override
  Future<SpiderListResult> categoryContent({
    required String tid,
    int page = 1,
    Map<String, String>? filter,
  }) async {
    final typeId = int.tryParse(tid);
    final videoList = await _apiService.fetchVideoList(
      site.api,
      page: page,
      typeId: typeId,
    );

    return SpiderListResult(
      list: videoList.list,
      page: videoList.page,
      pageCount: videoList.pageCount,
      total: videoList.total,
    );
  }

  @override
  Future<SpiderDetailResult> detailContent({required String id}) async {
    final detail = await _apiService.fetchVideoDetail(
      site.api,
      id,
      sourceKey: key,
    );
    return SpiderDetailResult(detail: detail);
  }

  @override
  Future<SpiderListResult> searchContent({
    required String keyword,
    int page = 1,
  }) async {
    final videoList = await _apiService.searchVideos(site.api, keyword);

    return SpiderListResult(
      list: videoList.list,
      page: videoList.page,
      pageCount: videoList.pageCount,
      total: videoList.total,
    );
  }

  @override
  Future<SpiderPlayResult> playerContent({
    required String flag,
    required String id,
  }) async {
    return SpiderPlayResult(url: id, parse: '0');
  }

  @override
  void dispose() {
    _apiService.clearAllCache();
  }
}
