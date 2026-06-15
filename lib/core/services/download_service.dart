import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../network/proxy_config_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';
import '../database/database.dart';
import '../database/database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0));

/// 下载状态枚举
enum DownloadStatus {
  waiting,    // 0
  downloading, // 1
  completed,  // 2
  failed,     // 3
}

/// 下载服务 Provider
final downloadServiceProvider = Provider<DownloadService>((ref) {
  return DownloadService(ref);
});

class DownloadService {
  final Ref _ref;
  final Dio _dio = DownloadService._createDio();

  static Dio _createDio() {
    final dio = Dio();
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      try { ProxyConfigService.instance.configureHttpClient(client); } catch (_) {}
      return client;
    };
    return dio;
  }
  final Map<String, CancelToken> _cancelTokens = {};

  DownloadService(this._ref);

  /// 开始下载
  Future<void> startDownload({
    required String vodId,
    required String vodName,
    required String episodeName,
    required String videoUrl,
  }) async {
    final db = _ref.read(databaseProvider);
    final id = const Uuid().v4();

    // 插入下载任务记录
    await db.insertDownloadTask(DownloadTasksCompanion.insert(
      id: id,
      vodId: vodId,
      vodName: vodName,
      episodeName: episodeName,
      videoUrl: videoUrl,
      createTime: DateTime.now().millisecondsSinceEpoch,
    ));

    // 执行下载
    _doDownload(id, videoUrl, vodName, episodeName);
  }

  /// 执行下载
  Future<void> _doDownload(String taskId, String url, String vodName, String episodeName) async {
    final db = _ref.read(databaseProvider);
    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;

    try {
      // 更新状态为下载中
      await db.updateDownloadTask(DownloadTasksCompanion(
        id: Value(taskId),
        status: Value(DownloadStatus.downloading.index),
      ));

      // 获取保存路径
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory(p.join(dir.path, 'downloads'));
      if (!downloadDir.existsSync()) {
        downloadDir.createSync(recursive: true);
      }

      // 生成文件名（清理非法字符）
      final safeName = '${vodName}_${episodeName}'.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final filePath = p.join(downloadDir.path, '$safeName.mp4');

      await _dio.download(
        url,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received * 100 / total).round();
            db.updateDownloadTask(DownloadTasksCompanion(
              id: Value(taskId),
              progress: Value(progress),
              fileSize: Value(received),
            ));
          }
        },
        options: Options(
          headers: {'User-Agent': 'okhttp/3.12.11'},
          receiveTimeout: const Duration(minutes: 30),
        ),
      );

      // 下载完成
      await db.updateDownloadTask(DownloadTasksCompanion(
        id: Value(taskId),
        status: Value(DownloadStatus.completed.index),
        progress: Value(100),
        localPath: Value(filePath),
      ));

      _logger.i('下载完成: $vodName - $episodeName');
    } catch (e) {
      if (cancelToken.isCancelled) {
        _logger.d('下载已取消: $taskId');
      } else {
        _logger.e('下载失败: $e');
        await db.updateDownloadTask(DownloadTasksCompanion(
          id: Value(taskId),
          status: Value(DownloadStatus.failed.index),
        ));
      }
    } finally {
      _cancelTokens.remove(taskId);
    }
  }

  /// 取消下载
  void cancelDownload(String taskId) {
    _cancelTokens[taskId]?.cancel();
    _cancelTokens.remove(taskId);
  }

  /// 删除下载任务和文件
  Future<void> deleteTask(String taskId) async {
    final db = _ref.read(databaseProvider);
    // 取消进行中的下载
    cancelDownload(taskId);
    // 获取任务信息以删除本地文件
    final tasks = await db.watchAllDownloadTasks().first;
    final task = tasks.where((t) => t.id == taskId).firstOrNull;
    if (task != null && task.localPath.isNotEmpty) {
      final file = File(task.localPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    await db.deleteDownloadTask(taskId);
  }

  /// 清除已完成下载的记录（保留文件）
  Future<void> clearCompletedRecords() async {
    final db = _ref.read(databaseProvider);
    await db.deleteCompletedDownloads();
  }
}
