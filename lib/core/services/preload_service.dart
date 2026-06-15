import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:logger/logger.dart';
import 'video_cache_service.dart';
import '../network/network_engine.dart' show NetworkCondition, Semaphore;
import '../network/proxy_config_service.dart';

/// 预加载优先级枚举
enum PreloadPriority {
  /// 当前播放（最高优先级）
  currentPlayback(0),

  /// 下一集
  nextEpisode(1),

  /// 相邻项目
  adjacentItem(2),

  /// 播放列表项目
  playlistItem(3),

  /// 历史重播
  historyReplay(4);

  const PreloadPriority(this.value);

  /// 优先级数值，越小越高
  final int value;
}

/// 预加载任务状态枚举
enum PreloadTaskStatus {
  /// 等待中
  waiting,

  /// 下载中
  downloading,

  /// 已完成
  completed,

  /// 已失败
  failed,

  /// 已取消
  cancelled,
}

/// 网络条件使用 NetworkCondition（来自 network_engine.dart）
/// wifi / lte / threeG / weak / offline

/// 预加载任务
class PreloadTask {
  /// 任务唯一标识
  final String id;

  /// 视频ID
  final String videoId;

  /// 视频URL
  final String url;

  /// 优先级
  final PreloadPriority priority;

  /// 目标预加载字节数
  final int preloadBytes;

  /// 已加载字节数
  int loadedBytes;

  /// 任务状态
  PreloadTaskStatus status;

  /// 任务创建时间
  final DateTime createdAt;

  /// 取消令牌
  CancelToken? _cancelToken;

  PreloadTask({
    required this.id,
    required this.videoId,
    required this.url,
    required this.priority,
    required this.preloadBytes,
    this.loadedBytes = 0,
    this.status = PreloadTaskStatus.waiting,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 绑定取消令牌
  void attachCancelToken(CancelToken token) {
    _cancelToken = token;
  }

  /// 取消任务
  void cancel() {
    _cancelToken?.cancel('预加载任务已取消: $videoId');
    status = PreloadTaskStatus.cancelled;
  }
}

/// 预加载策略配置
class PreloadStrategy {
  /// 是否缓存完整视频
  final bool cacheFullVideo;

  /// 预加载数量
  final int preloadCount;

  /// 预加载字节数（首段缓存大小）
  final int initialBytes;

  /// 带宽占用比例上限（0.0 ~ 1.0）
  final double bandwidthFraction;

  const PreloadStrategy({
    required this.cacheFullVideo,
    required this.preloadCount,
    required this.initialBytes,
    required this.bandwidthFraction,
  });

  /// WiFi 策略：激进 — 缓存完整视频，预加载后续3个项目
  static const wifi = PreloadStrategy(
    cacheFullVideo: true,
    preloadCount: 3,
    initialBytes: 0, // 0 表示缓存完整视频
    bandwidthFraction: 0.30,
  );

  /// 移动网络策略：保守 — 仅缓存前3~5秒，预加载后续1个项目
  static const mobile = PreloadStrategy(
    cacheFullVideo: false,
    preloadCount: 1,
    initialBytes: 512 * 1024, // 约 512KB，大致覆盖3~5秒
    bandwidthFraction: 0.20,
  );

  /// 弱网策略：极简 — 仅缓存前1~2秒
  static const weak = PreloadStrategy(
    cacheFullVideo: false,
    preloadCount: 0,
    initialBytes: 128 * 1024, // 约 128KB，大致覆盖1~2秒
    bandwidthFraction: 0.10,
  );

  /// 离线策略：不预加载
  static const offline = PreloadStrategy(
    cacheFullVideo: false,
    preloadCount: 0,
    initialBytes: 0,
    bandwidthFraction: 0.0,
  );

  /// 根据网络条件自动选择策略
  static PreloadStrategy forCondition(NetworkCondition condition) {
    switch (condition) {
      case NetworkCondition.wifi:
        return wifi;
      case NetworkCondition.lte:
        return mobile;
      case NetworkCondition.threeG:
        return mobile;
      case NetworkCondition.weak:
        return weak;
      case NetworkCondition.offline:
        return offline;
    }
  }
}

/// 智能视频预加载服务
///
/// 根据用户行为上下文和网络条件，智能地预加载视频内容，
/// 控制并发数和带宽占用，不干扰当前播放下载。
class PreloadService {
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));
  final Dio _dio = PreloadService._createDio();

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

  /// 视频缓存服务
  final VideoCacheService _cacheService;

  /// 最大并发预加载数
  static const int _maxConcurrency = 3;

  /// 并发信号量
  final Semaphore _semaphore = Semaphore(_maxConcurrency);

  /// 当前网络条件
  NetworkCondition _networkCondition = NetworkCondition.wifi;

  /// 当前预加载策略
  PreloadStrategy _strategy = PreloadStrategy.wifi;

  /// 预加载任务列表（优先队列，按优先级排序）
  final List<PreloadTask> _tasks = [];

  /// 任务流控制器
  final StreamController<List<PreloadTask>> _tasksController =
      StreamController<List<PreloadTask>>.broadcast();

  /// 当前是否正在播放缓冲中（用于暂停预加载）
  bool _isPlaybackBuffering = false;

  /// 任务ID计数器
  int _taskIdCounter = 0;

  /// 是否已销毁
  bool _disposed = false;

  PreloadService({required VideoCacheService cacheService})
      : _cacheService = cacheService;

  /// 观察预加载任务列表的流
  Stream<List<PreloadTask>> get tasksStream => _tasksController.stream;

  /// 当前活跃任务快照
  List<PreloadTask> get activeTasks =>
      List.unmodifiable(_tasks.where((t) => t.status == PreloadTaskStatus.downloading));

  /// 当前网络条件
  NetworkCondition get networkCondition => _networkCondition;

  /// 当前预加载策略
  PreloadStrategy get strategy => _strategy;

  /// 添加预加载任务
  ///
  /// [videoId] 视频唯一标识
  /// [url] 视频下载地址
  /// [priority] 预加载优先级，默认 nextEpisode
  /// [targetBytes] 目标预加载字节数，为 null 时使用策略默认值
  Future<void> preloadVideo(
    String videoId,
    String url, {
    PreloadPriority priority = PreloadPriority.nextEpisode,
    int? targetBytes,
  }) async {
    if (_disposed) return;

    // 离线时不预加载
    if (_networkCondition == NetworkCondition.offline) {
      _logger.d('当前离线，跳过预加载: $videoId');
      return;
    }

    // 检查是否已有相同视频的预加载任务
    final existing = _tasks.where((t) => t.videoId == videoId).firstOrNull;
    if (existing != null) {
      // 如果已有任务且优先级更高或相同，跳过
      if (existing.priority.value <= priority.value) {
        _logger.d('预加载任务已存在且优先级不低于新任务: $videoId');
        return;
      }
      // 否则取消旧任务，创建更高优先级的新任务
      await cancelPreload(videoId);
    }

    // 检查是否已缓存
    final isCached = await _cacheService.hasCache(videoId);
    if (isCached) {
      _logger.d('视频已缓存，跳过预加载: $videoId');
      return;
    }

    // 计算目标字节数
    final bytes = targetBytes ??
        (_strategy.cacheFullVideo ? 0 : _strategy.initialBytes);

    final task = PreloadTask(
      id: '_preload_${_taskIdCounter++}',
      videoId: videoId,
      url: url,
      priority: priority,
      preloadBytes: bytes,
    );

    _tasks.add(task);
    _sortTasks();
    _notifyTasksUpdate();

    _logger.d('添加预加载任务: $videoId, 优先级: ${priority.name}, 目标字节: $bytes');

    // 尝试执行任务
    _processQueue();
  }

  /// 便捷方法：预加载下一集
  Future<void> preloadNextEpisode(String videoId, String url) {
    return preloadVideo(videoId, url, priority: PreloadPriority.nextEpisode);
  }

  /// 便捷方法：预加载相邻项目
  Future<void> preloadAdjacent(String videoId, String url) {
    return preloadVideo(videoId, url, priority: PreloadPriority.adjacentItem);
  }

  /// 取消指定视频的预加载任务
  Future<void> cancelPreload(String videoId) async {
    final task = _tasks.where((t) => t.videoId == videoId).firstOrNull;
    if (task == null) return;

    task.cancel();
    _tasks.remove(task);
    _notifyTasksUpdate();
    _logger.d('已取消预加载任务: $videoId');
  }

  /// 取消所有预加载任务
  Future<void> cancelAll() async {
    for (final task in _tasks) {
      task.cancel();
    }
    _tasks.clear();
    _notifyTasksUpdate();
    _logger.d('已取消所有预加载任务');
  }

  /// 更新网络条件，自动调整预加载策略
  void updateNetworkCondition(NetworkCondition condition) {
    if (_networkCondition == condition) return;

    _networkCondition = condition;
    _strategy = PreloadStrategy.forCondition(condition);
    _logger.i('网络条件变更: ${condition.name}, 策略: '
        '缓存完整视频=${_strategy.cacheFullVideo}, '
        '预加载数量=${_strategy.preloadCount}, '
        '首段字节=${_strategy.initialBytes}, '
        '带宽占比=${(_strategy.bandwidthFraction * 100).toStringAsFixed(0)}%');

    // 离线时取消所有任务
    if (condition == NetworkCondition.offline) {
      cancelAll();
      return;
    }

    // 弱网时取消低优先级任务
    if (condition == NetworkCondition.weak) {
      _tasks
          .where((t) =>
              t.priority.value > PreloadPriority.nextEpisode.value &&
              t.status != PreloadTaskStatus.downloading)
          .toList()
          .forEach((t) {
        t.cancel();
        _tasks.remove(t);
      });
      _notifyTasksUpdate();
    }

    // 重新处理队列
    _processQueue();
  }

  /// 通知播放缓冲状态变更
  ///
  /// 当检测到播放缓冲时暂停预加载，播放稳定后恢复
  void notifyPlaybackBuffering(bool isBuffering) {
    if (_isPlaybackBuffering == isBuffering) return;

    _isPlaybackBuffering = isBuffering;
    if (isBuffering) {
      _logger.d('检测到播放缓冲，暂停预加载');
      // 取消正在下载的任务（释放带宽给播放）
      _pauseDownloadingTasks();
    } else {
      _logger.d('播放已稳定，恢复预加载');
      _processQueue();
    }
  }

  /// 销毁服务，释放资源
  void dispose() {
    _disposed = true;
    cancelAll();
    _tasksController.close();
  }

  // ==================== 内部方法 ====================

  /// 按优先级排序任务队列（优先级数值越小越靠前）
  void _sortTasks() {
    _tasks.sort((a, b) => a.priority.value.compareTo(b.priority.value));
  }

  /// 通知任务列表更新
  void _notifyTasksUpdate() {
    if (!_tasksController.isClosed) {
      _tasksController.add(List.unmodifiable(_tasks));
    }
  }

  /// 处理任务队列
  void _processQueue() {
    if (_disposed) return;
    if (_isPlaybackBuffering) return;
    if (_networkCondition == NetworkCondition.offline) return;

    // 取出等待中的任务并执行
    final waitingTasks = _tasks
        .where((t) => t.status == PreloadTaskStatus.waiting)
        .toList();

    for (final task in waitingTasks) {
      _executeTask(task);
    }
  }

  /// 执行单个预加载任务
  Future<void> _executeTask(PreloadTask task) async {
    // 获取信号量许可（控制并发）
    await _semaphore.acquire();

    if (_disposed || task.status == PreloadTaskStatus.cancelled) {
      _semaphore.release();
      return;
    }

    task.status = PreloadTaskStatus.downloading;
    final cancelToken = CancelToken();
    task.attachCancelToken(cancelToken);
    _notifyTasksUpdate();

    try {
      _logger.d('开始预加载: ${task.videoId}, 目标字节: ${task.preloadBytes}');

      // 构建请求头，限制下载范围以控制带宽
      final headers = <String, dynamic>{
        'User-Agent': 'okhttp/3.12.11',
      };

      // 如果指定了预加载字节数且非完整缓存，使用 Range 头
      if (task.preloadBytes > 0 && !_strategy.cacheFullVideo) {
        headers['Range'] = 'bytes=0-${task.preloadBytes - 1}';
      }

      final response = await _dio.get<List<int>>(
        task.url,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 30),
        ),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          task.loadedBytes = received;
          // 如果只需要预加载部分字节，在达到目标后取消
          if (task.preloadBytes > 0 &&
              !_strategy.cacheFullVideo &&
              received >= task.preloadBytes) {
            cancelToken.cancel('预加载目标字节已达到');
          }
        },
      );

      // 保存预加载数据到缓存
      final data = response.data;
      if (data != null && data.isNotEmpty) {
        task.loadedBytes = data.length;

        // 完整视频下载 → 存为 L3 完整文件，播放器可直接用
        // 部分预加载（Range 请求）→ 存为 L4 分片，后续通过代理服务使用
        final isFullVideo = task.preloadBytes == 0;
        if (isFullVideo) {
          final tempDir = await Directory.systemTemp.createTemp('yl_preload_');
          try {
            final ext = task.url.contains('.ts')
                ? '.ts'
                : task.url.contains('.m3u8')
                    ? '.m3u8'
                    : '.mp4';
            final tempFile = File('${tempDir.path}/video$ext');
            await tempFile.writeAsBytes(data);
            await _cacheService.putVideo(
              task.videoId,
              tempFile.path,
              quality: '720p',
            );
            _logger.i('完整视频已缓存(L3): ${task.videoId}');
          } finally {
            await tempDir.delete(recursive: true);
          }
        } else {
          await _cacheService.putSegment(
            task.videoId,
            'preload_${task.id}',
            data,
            quality: '720p',
          );
        }
      }

      task.status = PreloadTaskStatus.completed;
      _logger.i('预加载完成: ${task.videoId}, 已加载: ${task.loadedBytes} 字节');
    } catch (e) {
      if (cancelToken.isCancelled) {
        // 正常取消（达到目标字节或手动取消），不标记为失败
        if (task.status != PreloadTaskStatus.cancelled) {
          task.status = PreloadTaskStatus.completed;
          _logger.d('预加载正常终止: ${task.videoId}');
        }
      } else {
        task.status = PreloadTaskStatus.failed;
        _logger.e('预加载失败: ${task.videoId}, 错误: $e');
      }
    } finally {
      _semaphore.release();
      _notifyTasksUpdate();

      // 从任务列表中移除已完成或已取消的任务
      _tasks.removeWhere((t) =>
          t.status == PreloadTaskStatus.completed ||
          t.status == PreloadTaskStatus.cancelled);

      // 继续处理队列
      _processQueue();
    }
  }

  /// 暂停正在下载的任务（播放缓冲时释放带宽）
  void _pauseDownloadingTasks() {
    final downloadingTasks = _tasks
        .where((t) => t.status == PreloadTaskStatus.downloading)
        .toList();

    for (final task in downloadingTasks) {
      task.cancel();
      _logger.d('暂停预加载任务（播放缓冲中）: ${task.videoId}');
    }

    _tasks.removeWhere((t) => t.status == PreloadTaskStatus.cancelled);
    _notifyTasksUpdate();
  }
}
