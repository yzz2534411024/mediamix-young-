import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

/// Java Spider Bridge HTTP 客户端
///
/// 与本地 Java SpiderBridgeServer 通信，调用 TVBox Java 蜘蛛方法。
class JavaBridgeClient {
  final Logger _logger = Logger(printer: SimplePrinter());
  final Dio _dio;
  final String baseUrl;
  bool _available = false;

  JavaBridgeClient({required this.baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Content-Type': 'application/json'},
            ));

  /// 桥接是否可用
  bool get isAvailable => _available;

  /// 检查桥接状态
  Future<bool> checkStatus() async {
    try {
      final response = await _dio.get('$baseUrl/status');
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        _available = true;
        return true;
      }
    } catch (e) {
      _available = false;
    }
    return false;
  }

  /// 获取已加载的蜘蛛列表
  Future<List<Map<String, dynamic>>> listSpiders() async {
    try {
      final response = await _dio.get('$baseUrl/spiders');
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        final spiders = data['data'];
        if (spiders is List) {
          return spiders.whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (e) {
      _logger.w('获取蜘蛛列表失败: $e');
    }
    return [];
  }

  /// 初始化蜘蛛
  Future<Map<String, dynamic>> initSpider(
    String spiderKey, {
    Map<String, dynamic>? config,
  }) async {
    return _callMethod('/init', {
      'spiderKey': spiderKey,
      'config': config != null ? jsonEncode(config) : '{}',
    });
  }

  /// 获取首页内容
  Future<Map<String, dynamic>> homeContent(String spiderKey, {int page = 1}) {
    return _callMethod('/home', {
      'spiderKey': spiderKey,
      'page': page,
    });
  }

  /// 获取分类内容
  Future<Map<String, dynamic>> categoryContent(
    String spiderKey, {
    required String tid,
    int page = 1,
    Map<String, String>? filter,
  }) {
    return _callMethod('/category', {
      'spiderKey': spiderKey,
      'tid': tid,
      'page': page,
      if (filter != null) 'filter': jsonEncode(filter),
    });
  }

  /// 获取详情
  Future<Map<String, dynamic>> detailContent(String spiderKey, String id) {
    return _callMethod('/detail', {
      'spiderKey': spiderKey,
      'id': id,
    });
  }

  /// 搜索
  Future<Map<String, dynamic>> searchContent(
    String spiderKey, {
    required String keyword,
    int page = 1,
  }) {
    return _callMethod('/search', {
      'spiderKey': spiderKey,
      'keyword': keyword,
      'page': page,
    });
  }

  /// 获取播放地址
  Future<Map<String, dynamic>> playerContent(
    String spiderKey, {
    required String flag,
    required String id,
  }) {
    return _callMethod('/player', {
      'spiderKey': spiderKey,
      'flag': flag,
      'id': id,
    });
  }

  /// 关闭桥接服务
  Future<void> shutdown() async {
    try {
      await _dio.post('$baseUrl/shutdown');
    } catch (_) {}
    _available = false;
  }

  /// 通用方法调用
  Future<Map<String, dynamic>> _callMethod(
    String path,
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await _dio.post(
        '$baseUrl$path',
        data: jsonEncode(params),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is String) {
        return jsonDecode(data) as Map<String, dynamic>;
      }
      return {'code': -1, 'msg': '无效的响应格式'};
    } on DioException catch (e) {
      _available = false;
      _logger.e('Bridge 请求失败 [$path]: $e');
      return {'code': -1, 'msg': 'Bridge 请求失败: ${e.message}'};
    } catch (e) {
      _logger.e('Bridge 调用异常 [$path]: $e');
      return {'code': -1, 'msg': 'Bridge 调用异常: $e'};
    }
  }

  /// 释放资源
  void dispose() {
    _dio.close(force: true);
    _available = false;
  }
}
