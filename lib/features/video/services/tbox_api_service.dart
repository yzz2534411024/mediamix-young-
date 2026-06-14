import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:logger/logger.dart';
import '../models/video_models.dart';

/// CMS API 视频服务
/// 支持采集站 API 格式：{apiUrl}?ac=detail&pg=1 获取影片列表
/// {apiUrl}?ac=detail&ids={vodId} 获取详情
/// {apiUrl}?wd=关键词 搜索影片
class VideoApiService {
  final Dio _dio;
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  VideoApiService({Dio? dio}) : _dio = dio ?? _createDio();

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': 'okhttp/3.12.11',
        'Accept': '*/*',
        'Accept-Encoding': 'gzip, deflate',
      },
      validateStatus: (status) => status != null && status < 500,
      followRedirects: true,
      maxRedirects: 5,
    ));

    // 允许自签名证书
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };

    return dio;
  }

  /// 获取分类列表
  Future<List<VideoCategory>> fetchCategories(String apiUrl) async {
    try {
      final url = _buildUrl(apiUrl, {'ac': 'list'});
      _logger.d('获取分类列表: $url');
      final response = await _dio.get(url);
      final data = _extractJson(response);
      final List<VideoCategory> categories = [];
      for (final c in (data['class'] as List?) ?? []) {
        if (c is Map<String, dynamic>) {
          categories.add(VideoCategory.fromJson(c));
        }
      }
      return categories;
    } on DioException catch (e) {
      throw Exception(_formatDioError(e));
    } catch (e) {
      _logger.e('获取分类列表失败: $e');
      throw Exception('获取分类失败: $e');
    }
  }

  /// 获取影片列表
  Future<VideoListResponse> fetchVideoList(String apiUrl, {int page = 1, int? typeId}) async {
    try {
      final params = {'ac': 'detail', 'pg': page.toString()};
      if (typeId != null) params['t'] = typeId.toString();
      final url = _buildUrl(apiUrl, params);
      _logger.d('获取影片列表: $url');

      final response = await _dio.get(url);
      final data = _extractJson(response);
      return VideoListResponse.fromJson(data);
    } on DioException catch (e) {
      final errMsg = _formatDioError(e);
      _logger.e('获取影片列表失败: $errMsg');
      throw Exception(errMsg);
    } catch (e) {
      _logger.e('获取影片列表失败: $e');
      throw Exception('加载失败: $e');
    }
  }

  /// 获取影片详情
  Future<VideoDetail> fetchVideoDetail(String apiUrl, String vodId, {String sourceKey = ''}) async {
    try {
      final url = _buildUrl(apiUrl, {'ac': 'detail', 'ids': vodId});
      _logger.d('获取影片详情: $url');

      final response = await _dio.get(url);
      final data = _extractJson(response);

      final list = data['list'] as List?;
      if (list == null || list.isEmpty) {
        throw Exception('影片不存在');
      }

      return VideoDetail.fromJson(list.first as Map<String, dynamic>, sourceKey: sourceKey);
    } on DioException catch (e) {
      final errMsg = _formatDioError(e);
      _logger.e('获取影片详情失败: $errMsg');
      throw Exception(errMsg);
    } catch (e) {
      _logger.e('获取影片详情失败: $e');
      throw Exception('加载失败: $e');
    }
  }

  /// 搜索影片
  Future<VideoListResponse> searchVideos(String apiUrl, String keyword) async {
    try {
      final url = _buildUrl(apiUrl, {'wd': keyword});
      _logger.d('搜索影片: $url');

      final response = await _dio.get(url);
      final data = _extractJson(response);
      return VideoListResponse.fromJson(data);
    } on DioException catch (e) {
      final errMsg = _formatDioError(e);
      _logger.e('搜索影片失败: $errMsg');
      throw Exception(errMsg);
    } catch (e) {
      _logger.e('搜索影片失败: $e');
      throw Exception('搜索失败: $e');
    }
  }

  /// 构建请求 URL
  String _buildUrl(String apiUrl, Map<String, String> params) {
    var url = apiUrl.trim();
    // 确保有协议前缀
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    // 拼接查询参数
    final separator = url.contains('?') ? '&' : '?';
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return '$url$separator$query';
  }

  /// 从响应中提取 JSON 数据
  Map<String, dynamic> _extractJson(Response response) {
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final dynamic body = response.data;

    if (body is Map<String, dynamic>) {
      return body;
    }

    if (body is String) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw Exception('JSON 不是对象格式');
      } catch (e) {
        throw Exception('JSON 解析失败: $e');
      }
    }

    throw Exception('无效的响应格式: ${body.runtimeType}');
  }

  /// 格式化 Dio 错误信息
  String _formatDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查网络';
      case DioExceptionType.receiveTimeout:
        return '接收超时，服务器响应过慢';
      case DioExceptionType.sendTimeout:
        return '发送超时';
      case DioExceptionType.connectionError:
        final msg = e.message ?? '';
        if (msg.contains('Failed host lookup')) {
          return 'DNS 解析失败，域名无法访问';
        }
        if (msg.contains('Connection refused')) {
          return '服务器拒绝连接';
        }
        return '网络连接失败: $msg';
      case DioExceptionType.badResponse:
        return '服务器返回错误: HTTP ${e.response?.statusCode}';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        final msg = e.message ?? '';
        final errorStr = e.error?.toString() ?? '';
        if (msg.isNotEmpty) return '网络错误: $msg';
        if (errorStr.isNotEmpty) return '网络错误: $errorStr';
        return '网络错误: 请检查接口地址是否正确';
    }
  }
}
