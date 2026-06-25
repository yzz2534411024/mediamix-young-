import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import 'spider_adapter.dart';
import 'spider_models.dart';
import 'spider_registry.dart';
import 'tvbox_config_parser.dart';
import 'tvbox_image_decoder.dart';

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
  ///
  /// 支持以下响应格式：
  /// 1. 标准 JSON（Content-Type: application/json）
  /// 2. JPEG 图片伪装（饭太硬格式：FF D8...FF D9 [标识]**[Base64 JSON]）
  /// 3. 纯 Base64 编码的 JSON
  Future<TvBoxConfig> fetchTvBoxConfig(String configUrl) async {
    try {
      // 以 bytes 方式请求，支持图片伪装格式
      final response = await _dio.get(
        configUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data as List<int>;
      if (bytes.isEmpty) {
        throw const FormatException('TVBox 配置响应为空');
      }

      _logger.d('TVBox配置响应: ${bytes.length} bytes, '
          'Content-Type: ${response.headers.value('content-type')}');

      // 尝试多种解码方式
      Map<String, dynamic>? json;

      // 方式1：JPEG/BMP 图片伪装格式
      if (TvBoxImageDecoder.isJpegDisguise(bytes) ||
          TvBoxImageDecoder.isBmpDisguise(bytes)) {
        _logger.d('检测到图片伪装格式，尝试解码...');
        json = TvBoxImageDecoder.decode(bytes);
      }

      // 方式2：直接作为文本解析
      json ??= _extractJsonFromBytes(bytes);

      // 方式3：尝试通用图片解码（兜底）
      json ??= TvBoxImageDecoder.decode(bytes);

      if (json == null) {
        throw const FormatException('无法解析 TVBox 配置：未知格式');
      }

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

  /// 从 bytes 提取 JSON（尝试 UTF-8 解码后直接解析）
  Map<String, dynamic>? _extractJsonFromBytes(List<int> bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.startsWith('{') || text.startsWith('[')) {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }
}
