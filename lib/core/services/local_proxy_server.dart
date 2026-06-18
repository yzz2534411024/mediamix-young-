import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'video_cache_service.dart';
import '../network/network_engine.dart';
import '../network/proxy_config_service.dart';

/// 本地 HTTP 代理服务器
///
/// 拦截播放器的视频请求，从缓存返回数据或代理 CDN 请求的同时缓存。
/// 对播放器完全透明——播放器只需要请求 http://127.0.0.1:PORT/vod/... 即可。
///
/// 请求路径: /vod/{videoId}?url={cdn_url}&quality={quality}
class LocalProxyServer {
  static LocalProxyServer? _instance;
  static LocalProxyServer get instance => _instance ??= LocalProxyServer._();

  final Logger _logger = Logger(printer: SimplePrinter());
  final Dio _dio = _createDio();

  HttpServer? _server;
  int _port = 0;

  /// 当前端口号，0 表示未启动
  int get port => _port;

  /// 是否正在运行
  bool get isRunning => _server != null;

  LocalProxyServer._();

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 30),
      responseType: ResponseType.stream,
      headers: {'User-Agent': 'okhttp/3.12.11'},
    ));
    (dio.httpClientAdapter as dynamic).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      try {
        ProxyConfigService.instance.configureHttpClient(client);
      } catch (_) {}
      return client;
    };
    return dio;
  }

  /// 启动代理服务器，绑定到随机可用端口
  /// Fix 2: 添加超时保护和重试机制
  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
          .timeout(const Duration(seconds: 5));
      _port = _server!.port;
      _server!.listen(_handleRequest);
      _logger.i('本地代理已启动: http://127.0.0.1:$_port');
    } on TimeoutException {
      _logger.w('本地代理启动超时(5s)，尝试重试');
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
            .timeout(const Duration(seconds: 3));
        _port = _server!.port;
        _server!.listen(_handleRequest);
        _logger.i('本地代理重试成功: http://127.0.0.1:$_port');
      } catch (e) {
        _logger.e('本地代理启动失败: $e');
        _server = null;
        _port = 0;
      }
    } catch (e) {
      _logger.e('本地代理启动失败: $e');
      _server = null;
      _port = 0;
    }
  }

  /// 停止代理服务器
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
    _logger.d('本地代理已停止');
  }

  /// 构建代理 URL
  ///
  /// [cdnUrl] 原始 CDN 视频地址
  /// [videoId] 视频唯一标识（用于缓存查找）
  /// [quality] 画质标签
  String proxyUrl(String cdnUrl, String videoId, {String quality = '720p'}) {
    final encoded = Uri.encodeComponent(cdnUrl);
    return 'http://127.0.0.1:$_port/vod/$videoId?url=$encoded&quality=$quality';
  }

  /// 处理 HTTP 请求
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.pathSegments;
      if (path.length < 2 || path[0] != 'vod') {
        _sendError(request.response, 404, 'Not Found');
        return;
      }

      final videoId = path[1];
      final cdnUrl = request.uri.queryParameters['url'] ?? '';
      final quality = request.uri.queryParameters['quality'] ?? '720p';

      if (cdnUrl.isEmpty) {
        _sendError(request.response, 400, 'Missing url parameter');
        return;
      }

      _logger.d('代理请求: $videoId, Range: ${request.headers.value('range') ?? 'none'}');

      // 1. 检查 L3 完整文件
      final cachePath = await VideoCacheService.instance
          .getCachePath(videoId, quality: quality);
      if (cachePath != null) {
        await _serveFile(request.response, File(cachePath), request.headers);
        return;
      }

      // 2. 尝试从 L4 分片拼接服务
      final segments = await _getSegmentsForVideo(videoId, quality);
      if (segments.isNotEmpty) {
        await _serveFromSegments(request.response, segments, request.headers);
        return;
      }

      // 3. 无缓存，代理 CDN 并边播边缓存
      await _proxyAndCache(request, videoId, cdnUrl, quality);
    } catch (e) {
      _logger.e('代理请求处理失败: $e');
      try {
        _sendError(request.response, 500, 'Internal Error');
      } catch (_) {}
    }
  }

  /// 获取视频的所有 L4 分片路径（按序号排列）
  Future<List<String>> _getSegmentsForVideo(String videoId, String quality) async {
    final result = <String>[];
    // 尝试获取已知分段（通过递增分段 key 探测）
    for (int i = 0; i < 200; i++) {
      final segResult = await VideoCacheService.instance
          .getSegment(videoId, 'preload_$i', quality: quality);
      if (segResult.hit && segResult.path != null) {
        result.add(segResult.path!);
      } else {
        // 也尝试通用 segment key 格式
        final segResult2 = await VideoCacheService.instance
            .getSegment(videoId, 'seg_$i', quality: quality);
        if (segResult2.hit && segResult2.path != null) {
          result.add(segResult2.path!);
        }
      }
    }
    return result;
  }

  /// 从文件流式发送响应（支持 Range）
  Future<void> _serveFile(
    HttpResponse response,
    File file,
    HttpHeaders headers,
  ) async {
    final fileSize = await file.length();
    final rangeHeader = headers.value('range');

    if (rangeHeader != null) {
      await _serveFileWithRange(response, file, fileSize, rangeHeader);
    } else {
      response.headers.set('Content-Type', 'video/mp4');
      response.headers.set('Content-Length', fileSize);
      response.headers.set('Accept-Ranges', 'bytes');
      await response.addStream(file.openRead());
      await response.close();
    }
  }

  /// Range 请求：发送文件的指定字节范围
  Future<void> _serveFileWithRange(
    HttpResponse response,
    File file,
    int fileSize,
    String rangeHeader,
  ) async {
    final range = _parseRange(rangeHeader, fileSize);
    if (range == null) {
      response.statusCode = 416;
      response.headers.set('Content-Range', 'bytes */$fileSize');
      await response.close();
      return;
    }

    final (start, end) = range;
    final length = end - start + 1;

    response.statusCode = 206;
    response.headers.set('Content-Type', 'video/mp4');
    response.headers.set('Content-Length', length);
    response.headers.set('Content-Range', 'bytes $start-$end/$fileSize');
    response.headers.set('Accept-Ranges', 'bytes');

    final stream = file.openRead(start, end + 1);
    await response.addStream(stream);
    await response.close();
  }

  /// 从 L4 分片拼接服务
  Future<void> _serveFromSegments(
    HttpResponse response,
    List<String> segmentPaths,
    HttpHeaders headers,
  ) async {
    // 计算总大小
    int totalSize = 0;
    final files = <File>[];
    for (final path in segmentPaths) {
      final f = File(path);
      if (await f.exists()) {
        totalSize += await f.length();
        files.add(f);
      }
    }

    if (files.isEmpty) {
      _sendError(response, 404, 'Segments missing');
      return;
    }

    final rangeHeader = headers.value('range');
    response.headers.set('Content-Type', 'video/mp4');
    response.headers.set('Accept-Ranges', 'bytes');

    if (rangeHeader != null) {
      final range = _parseRange(rangeHeader, totalSize);
      if (range == null) {
        response.statusCode = 416;
        await response.close();
        return;
      }
      final (start, end) = range;
      response.statusCode = 206;
      response.headers.set('Content-Length', end - start + 1);
      response.headers.set('Content-Range', 'bytes $start-$end/$totalSize');
      await _streamSegmentRange(response, files, start, end);
    } else {
      response.headers.set('Content-Length', totalSize);
      for (final file in files) {
        await response.addStream(file.openRead());
      }
      await response.close();
    }
  }

  /// 从分片流中发送指定范围的字节
  Future<void> _streamSegmentRange(
    HttpResponse response,
    List<File> files,
    int rangeStart,
    int rangeEnd,
  ) async {
    int offset = 0;
    int remaining = rangeEnd - rangeStart + 1;

    for (final file in files) {
      final fileSize = await file.length();
      final fileStart = offset;
      final fileEnd = offset + fileSize - 1;

      if (fileEnd >= rangeStart && fileStart <= rangeEnd) {
        // 该文件在请求范围内
        final segStart = (rangeStart - fileStart).clamp(0, fileSize - 1);
        final segEnd = (rangeEnd - fileStart).clamp(0, fileSize - 1);

        final stream = file.openRead(segStart, segEnd + 1);
        final sub = stream.listen((data) {
          if (remaining > 0) {
            final chunk = data.length <= remaining ? data : data.sublist(0, remaining);
            response.add(chunk);
            remaining -= chunk.length;
          }
        });
        await sub.asFuture();
      }

      offset += fileSize;
      if (remaining <= 0) break;
    }
    await response.close();
  }

  /// 代理 CDN 请求，边下载边返回边缓存
  Future<void> _proxyAndCache(
    HttpRequest request,
    String videoId,
    String cdnUrl,
    String quality,
  ) async {
    final rangeHeader = request.headers.value('range');
    final headers = <String, dynamic>{
      'User-Agent': 'okhttp/3.12.11',
    };
    if (rangeHeader != null) {
      headers['Range'] = rangeHeader;
    }

    int segIndex = 0;
    int segBytes = 0;
    final segBuffer = <int>[];
    const segMaxBytes = 512 * 1024; // 512KB 一片

    final downloadStopwatch = Stopwatch()..start();
    int totalDownloadBytes = 0;

    try {
      final dioResponse = await _dio.get<ResponseBody>(
        cdnUrl,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
      );

      final statusCode = dioResponse.statusCode ?? 200;
      final contentLength = dioResponse.headers.value('content-length');
      final contentType = dioResponse.headers.value('content-type');

      request.response.statusCode = statusCode;
      if (contentType != null) {
        request.response.headers.set('Content-Type', contentType);
      }
      if (contentLength != null) {
        request.response.headers.set('Content-Length', contentLength);
      }
      request.response.headers.set('Accept-Ranges', 'bytes');

      final stream = dioResponse.data!.stream;
      await for (final chunk in stream) {
        request.response.add(chunk);
        totalDownloadBytes += chunk.length;
        segBuffer.addAll(chunk);
        segBytes += chunk.length;

        // 每满 512KB 写一片
        if (segBytes >= segMaxBytes) {
          VideoCacheService.instance.putSegment(
            videoId,
            'seg_$segIndex',
            List.from(segBuffer),
            quality: quality,
          );
          segIndex++;
          segBuffer.clear();
          segBytes = 0;
        }
      }

      // 写入最后不满 512KB 的剩余数据
      if (segBuffer.isNotEmpty) {
        VideoCacheService.instance.putSegment(
          videoId,
          'seg_$segIndex',
          List.from(segBuffer),
          quality: quality,
        );
      }

      downloadStopwatch.stop();
      if (totalDownloadBytes > 0 && downloadStopwatch.elapsedMilliseconds > 0) {
        NetworkEngine.instance.reportBandwidthSample(totalDownloadBytes, downloadStopwatch.elapsedMilliseconds);
      }
      await request.response.close();
      _logger.d('代理缓存完成: $videoId, ${segIndex + 1} 个分片, ${(totalDownloadBytes / 1024).toStringAsFixed(0)}KB, ${downloadStopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      _logger.e('代理 CDN 请求失败: $e');
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  /// 解析 Range 头，返回 (start, end)，null 表示无效
  (int, int)? _parseRange(String header, int fileSize) {
    if (fileSize <= 0) return null;
    try {
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(header);
      if (match == null) return null;
      final start = int.parse(match.group(1)!);
      final endStr = match.group(2);
      int end = endStr != null && endStr.isNotEmpty
          ? int.parse(endStr)
          : fileSize - 1;
      if (start >= fileSize || start > end) return null;
      end = end.clamp(0, fileSize - 1);
      return (start, end);
    } catch (_) {
      return null;
    }
  }

  /// 发送 HTTP 错误响应
  void _sendError(HttpResponse response, int status, String message) {
    response.statusCode = status;
    response.headers.set('Content-Type', 'text/plain');
    response.write(message);
    response.close();
  }
}
