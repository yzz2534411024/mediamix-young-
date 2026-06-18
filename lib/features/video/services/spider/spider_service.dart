import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import 'spider_adapter.dart';
import 'spider_models.dart';
import 'spider_registry.dart';
import 'tvbox_config_parser.dart';

/// 蜘蛛服务 — 统一入口，封装 Registry + TVBox 配置获取
class SpiderService {
  final Logger _logger = Logger(printer: SimplePrinter());
  final SpiderRegistry _registry = SpiderRegistry.instance;
  final Dio _dio;

  SpiderService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'User-Agent': 'okhttp/3.12.11'},
            ));

  /// 获取 TVBox 配置
  Future<TvBoxConfig> fetchTvBoxConfig(String configUrl) async {
    try {
      final response = await _dio.get(configUrl);
      final json = _extractJson(response.data);
      final config = const TvBoxConfigParser().parse(json);
      _logger.d(
          'TVBox配置解析完成: ${config.sites.length}个站点, spider=${config.spiderUrl}');
      return config;
    } catch (e) {
      _logger.e('获取TVBox配置失败: $e');
      rethrow;
    }
  }

  /// 从 TVBox 配置创建所有蜘蛛
  Future<List<SpiderAdapter>> initFromConfig(TvBoxConfig config) async {
    return _registry.createFromSites(config.sites);
  }

  /// 获取蜘蛛实例
  SpiderAdapter? getSpider(String key) => _registry.get(key);

  /// 获取所有蜘蛛
  List<SpiderAdapter> get allSpiders => _registry.all;

  /// 通过蜘蛛获取首页内容
  Future<SpiderHomeResult> fetchHome(SpiderAdapter spider, {int page = 1}) {
    return spider.homeContent(page: page);
  }

  /// 通过蜘蛛获取分类内容
  Future<SpiderListResult> fetchCategory(
    SpiderAdapter spider, {
    required String tid,
    int page = 1,
  }) {
    return spider.categoryContent(tid: tid, page: page);
  }

  /// 通过蜘蛛获取详情
  Future<SpiderDetailResult> fetchDetail(
    SpiderAdapter spider, {
    required String id,
  }) {
    return spider.detailContent(id: id);
  }

  /// 通过蜘蛛搜索
  Future<SpiderListResult> fetchSearch(
    SpiderAdapter spider, {
    required String keyword,
    int page = 1,
  }) {
    return spider.searchContent(keyword: keyword, page: page);
  }

  /// 通过蜘蛛解析播放地址
  Future<SpiderPlayResult> fetchPlay(
    SpiderAdapter spider, {
    required String flag,
    required String id,
  }) {
    return spider.playerContent(flag: flag, id: id);
  }

  /// 释放所有蜘蛛
  void disposeAll() => _registry.disposeAll();

  Map<String, dynamic> _extractJson(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }

    throw const FormatException('TVBox 配置不是有效的 JSON 对象');
  }
}
