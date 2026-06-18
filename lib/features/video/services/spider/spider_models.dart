import 'package:mediamix/features/video/models/video_models.dart';

/// 蜘蛛类型
enum SpiderType {
  cms, // 标准CMS采集站
  xpath, // XPath爬虫
  json, // JSON API爬虫
  site, // 自定义站点爬虫
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
  final String? parse; // "0"=直连, "1"=需二次解析
  final String? playUrl; // 二次解析URL

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
