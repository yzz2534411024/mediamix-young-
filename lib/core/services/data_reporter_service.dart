import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database.dart';
import 'privacy_manager_service.dart';
import '../network/network_engine.dart';

// ============================================================================
// 数据上报服务 — 批量上报本地持久化的指标数据到云端
// ============================================================================

/// 上报结果
enum UploadResult {
  /// 上报成功
  success,

  /// 网络不可用
  networkUnavailable,

  /// 隐私限制（未授权或WiFi限制）
  privacyBlocked,

  /// 上报失败（服务端错误）
  failed,

  /// 无待上报数据
  noData,
}

/// 数据上报服务（单例）
///
/// 职责：
///   - 批量读取未上报的指标数据
///   - POST 到云端 API
///   - 上报成功标记已上传
///   - 失败保留本地，指数退避重试
///   - 仅 WiFi 下自动上报（可覆盖）
///   - 超过7天的未上报数据自动清理
class DataReporterService {
  static DataReporterService? _instance;
  static DataReporterService get instance => _instance ??= DataReporterService._();

  DataReporterService._();

  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  /// 数据库实例（由 initialize 注入）
  AppDatabase? _db;

  /// 云端 API endpoint（可配置）
  String _apiEndpoint = 'https://api.mediamix.app/v1/metrics/batch';

  /// 是否正在上报中
  bool _isUploading = false;

  /// 重试计数
  int _retryCount = 0;

  /// 最大重试次数
  static const int _maxRetries = 3;

  /// 重试定时器
  Timer? _retryTimer;

  /// 定时上报间隔
  static const Duration _autoUploadInterval = Duration(minutes: 5);

  /// 定时上报定时器
  Timer? _autoUploadTimer;

  /// 上报状态流控制器
  final StreamController<UploadResult> _uploadStatusController =
      StreamController<UploadResult>.broadcast();

  /// 上报状态流
  Stream<UploadResult> get onUploadStatusChanged => _uploadStatusController.stream;

  /// 是否正在上报
  bool get isUploading => _isUploading;

  /// 当前 API endpoint
  String get apiEndpoint => _apiEndpoint;

  /// 初始化
  Future<void> initialize(AppDatabase db, {String? apiEndpoint}) async {
    _db = db;
    if (apiEndpoint != null) {
      _apiEndpoint = apiEndpoint;
    }

    // 预加载设备 ID
    await _loadDeviceId();

    // 启动定时自动上报
    _startAutoUpload();

    _logger.i('数据上报服务已初始化，endpoint: $_apiEndpoint');
  }

  /// 设置 API endpoint
  void setApiEndpoint(String endpoint) {
    _apiEndpoint = endpoint;
    _logger.i('API endpoint 已更新: $endpoint');
  }

  /// 手动触发上报
  Future<UploadResult> uploadNow() async {
    return _doUpload();
  }

  /// 启动定时自动上报
  void _startAutoUpload() {
    _autoUploadTimer?.cancel();
    _autoUploadTimer = Timer.periodic(_autoUploadInterval, (_) {
      _doUpload();
    });
  }

  /// 执行上报
  Future<UploadResult> _doUpload() async {
    if (_isUploading || _db == null) return UploadResult.noData;

    // 检查隐私权限
    final privacy = PrivacyManagerService.instance;
    if (!privacy.canCollectMetrics) {
      return UploadResult.privacyBlocked;
    }

    // 检查 WiFi 限制
    final isOnWifi = _isWifiConnection();
    if (!privacy.canUploadData(isOnWifi: isOnWifi)) {
      _logger.d('当前非WiFi，跳过上报');
      return UploadResult.privacyBlocked;
    }

    _isUploading = true;

    try {
      // 清理过期数据
      await _cleanOldData();

      // 读取未上报数据
      final sessions = await _db!.getUnuploadedSessions(limit: 50);
      final events = await _db!.getUnuploadedEvents(limit: 50);

      if (sessions.isEmpty && events.isEmpty) {
        _isUploading = false;
        return UploadResult.noData;
      }

      // 构建上报 payload
      final payload = _buildPayload(sessions, events);

      // 发送 HTTP POST
      final result = await _sendPayload(payload);

      if (result == UploadResult.success) {
        // 标记已上传
        if (sessions.isNotEmpty) {
          await _db!.markSessionsUploaded(sessions.map((s) => s.sessionId).toList());
        }
        if (events.isNotEmpty) {
          await _db!.markEventsUploaded(events.map((e) => e.id).toList());
        }

        // 清理已上传的数据
        await _db!.deleteUploadedSessions();
        await _db!.deleteUploadedEvents();

        _retryCount = 0;
        _logger.i('数据上报成功: ${sessions.length} 个会话, ${events.length} 个事件');
      } else {
        // 上报失败，安排重试
        _scheduleRetry();
      }

      _isUploading = false;
      _uploadStatusController.add(result);
      return result;
    } catch (e) {
      _logger.e('数据上报异常: $e');
      _isUploading = false;
      _scheduleRetry();
      _uploadStatusController.add(UploadResult.failed);
      return UploadResult.failed;
    }
  }

  /// 构建上报 payload
  Map<String, dynamic> _buildPayload(
    List<MetricsSession> sessions,
    List<MetricsEventRecord> events,
  ) {
    return {
      'device_id': _getDeviceId(),
      'app_version': '0.2.0',
      'platform': Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'other',
      'timestamp': DateTime.now().toIso8601String(),
      'sessions': sessions.map((s) => <String, dynamic>{
        'session_id': s.sessionId,
        'video_id': s.videoId,
        'first_frame_time_ms': s.firstFrameTimeMs,
        'buffering_count': s.bufferingCount,
        'buffering_total_ms': s.bufferingTotalMs,
        'stutter_rate': s.stutterRate,
        'quality_changes': s.qualityChanges,
        'seek_count': s.seekCount,
        'seek_avg_ms': s.seekAvgMs,
        'error_count': s.errorCount,
        'cache_hits': s.cacheHits,
        'cache_misses': s.cacheMisses,
        'avg_bandwidth_kbps': s.avgBandwidthKbps,
        'peak_bandwidth_kbps': s.peakBandwidthKbps,
        'start_time': s.startTime,
        'end_time': s.endTime,
      }).toList(),
      'events': events.map((e) => <String, dynamic>{
        'id': e.id,
        'session_id': e.sessionId,
        'video_id': e.videoId,
        'event_type': e.eventType,
        'timestamp': e.timestamp,
        'payload': e.payloadJson,
      }).toList(),
    };
  }

  /// 发送 payload 到云端
  Future<UploadResult> _sendPayload(Map<String, dynamic> payload) async {
    try {
      final dio = NetworkEngine.instance.dio;
      final response = await dio.post(
        _apiEndpoint,
        data: jsonEncode(payload),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return UploadResult.success;
      } else if (response.statusCode == 429) {
        _logger.w('上报被限流，稍后重试');
        return UploadResult.failed;
      } else {
        _logger.w('上报失败，状态码: ${response.statusCode}');
        return UploadResult.failed;
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        _logger.w('网络不可用，跳过上报');
        return UploadResult.networkUnavailable;
      }
      _logger.e('上报请求异常: $e');
      return UploadResult.failed;
    } catch (e) {
      _logger.e('上报未知异常: $e');
      return UploadResult.failed;
    }
  }

  /// 安排重试（指数退避）
  void _scheduleRetry() {
    if (_retryCount >= _maxRetries) {
      _logger.w('已达最大重试次数 $_maxRetries，停止重试');
      _retryCount = 0;
      return;
    }

    _retryCount++;
    final delaySeconds = 30 * (1 << (_retryCount - 1)); // 30s, 60s, 120s

    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delaySeconds), () {
      _logger.i('重试上报 (第 $_retryCount 次)');
      _doUpload();
    });
  }

  /// 清理过期数据（超过7天）
  Future<void> _cleanOldData() async {
    if (_db == null) return;
    try {
      await _db!.deleteOldEvents(olderThanDays: 7);
      await _db!.deleteOldSessions(olderThanDays: 7);
    } catch (e) {
      _logger.e('清理过期数据失败: $e');
    }
  }

  /// 判断当前是否为 WiFi 连接（带缓存，避免启动时误判）
  bool? _lastKnownWifi;

  bool _isWifiConnection() {
    final bandwidth = NetworkEngine.instance.currentBandwidthKbps;
    // 带宽未初始化（=0）时返回上次已知状态，若从未采样则假设 WiFi
    if (bandwidth <= 0) {
      return _lastKnownWifi ?? true;
    }
    _lastKnownWifi = bandwidth > 5000;
    return _lastKnownWifi!;
  }

  static const _keyDeviceId = 'data_reporter_device_id';
  String? _cachedDeviceId;

  /// 从 SharedPreferences 加载设备 ID（初始化时调用一次）
  Future<void> _loadDeviceId() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _cachedDeviceId = sp.getString(_keyDeviceId);
      if (_cachedDeviceId == null || _cachedDeviceId!.isEmpty) {
        _cachedDeviceId =
            'device_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
        await sp.setString(_keyDeviceId, _cachedDeviceId!);
      }
    } catch (e) {
      _cachedDeviceId =
          'device_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    }
  }

  /// 获取设备 ID（同步，需在 [_loadDeviceId] 后调用）
  String _getDeviceId() {
    return _cachedDeviceId ?? 'device_unknown';
  }

  /// 获取本地数据统计摘要
  Future<Map<String, dynamic>> getLocalDataSummary() async {
    if (_db == null) return {};
    return _db!.getMetricsSummary();
  }

  /// 清除所有本地指标数据
  Future<void> clearAllLocalData() async {
    if (_db == null) return;
    await _db!.deleteUploadedEvents();
    await _db!.deleteUploadedSessions();
    // 也删除未上传的
    try {
      await _db!.deleteOldEvents(olderThanDays: 0);
      await _db!.deleteOldSessions(olderThanDays: 0);
    } catch (_) {}
    _logger.i('所有本地指标数据已清除');
  }

  /// 释放资源
  void dispose() {
    _autoUploadTimer?.cancel();
    _retryTimer?.cancel();
    _uploadStatusController.close();
  }
}
