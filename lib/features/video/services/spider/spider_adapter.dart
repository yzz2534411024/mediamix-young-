import 'spider_models.dart';

/// 蜘蛛适配器抽象接口
abstract interface class SpiderAdapter {
  /// 唯一标识
  String get key;

  /// 显示名称
  String get name;

  /// 蜘蛛类型
  SpiderType get type;

  /// 是否支持搜索，默认 true
  bool get isSearchSupported => true;

  /// 初始化
  Future<void> init(Map<String, dynamic> config);

  /// 首页内容
  Future<SpiderHomeResult> homeContent({int page = 1});

  /// 分类内容
  Future<SpiderListResult> categoryContent({
    required String tid,
    int page = 1,
    Map<String, String>? filter,
  });

  /// 详情内容
  Future<SpiderDetailResult> detailContent({required String id});

  /// 搜索内容
  Future<SpiderListResult> searchContent({
    required String keyword,
    int page = 1,
  });

  /// 播放内容
  Future<SpiderPlayResult> playerContent({
    required String flag,
    required String id,
  });

  /// 释放资源，默认空实现
  void dispose() {}
}
