import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:logger/logger.dart';
import '../database/database.dart';
import 'player_metrics_service.dart';
import 'privacy_manager_service.dart';

// ============================================================================
// 指标采集服务 — 将 PlayerMetricsService 的数据持久化到 Drift 数据库
// ============================================================================

/// 指标采集服务（单例）
///
/// 职责：
///   - 监听 PlayerMetricsService 的事件流
///   - 将原始事件和会话汇总持久化到 Drift 数据库
///   - 受 PrivacyManager 控制，仅在用户授权时采集
class MetricsCollectorService {
  static MetricsCollectorService? _instance;
  static MetricsCollectorService get instance => _instance ??= MetricsCollectorService._();

  MetricsCollectorService._();

  final Logger _logger = Logger(printer: SimplePrinter());

  /// 数据库实例（由 initialize 注入）
  AppDatabase? _db;

  /// 懒加载初始化 Completer（线程安全）
  Completer<void>? _initCompleter;

  /// PlayerMetricsService 事件订阅
  StreamSubscription<PlaybackMetrics>? _metricsSubscription;

  /// 当前会话的事件缓冲（会话结束时批量写入事件）
  final List<_PendingEvent> _pendingEvents = [];

  /// 是否已初始化
  bool _initialized = false;

  /// 初始化
  void initialize(AppDatabase db) {
    if (_initialized) return;
    _db = db;
    _initialized = true;

    // 监听 PlayerMetricsService 的指标流
    _metricsSubscription = PlayerMetricsService.instance.metricsStream.listen(
      _onMetricsUpdate,
      onError: (e) => _logger.e('指标流错误: $e'),
    );

    _logger.i('指标采集服务已初始化');
  }

  /// 确保服务已初始化（懒加载入口）
  ///
  /// 首次调用时执行初始化，后续调用直接返回。
  /// 多个并发调用会等待同一个 Completer，保证线程安全。
  Future<void> ensureInitialized(AppDatabase db) async {
    if (_initialized) return;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();
    try {
      initialize(db);
      _initCompleter!.complete();
    } catch (e) {
      if (!_initCompleter!.isCompleted) _initCompleter!.complete();
    }
  }

  /// 记录单个事件（由 PlayerPage 调用）
  void recordEvent(
    MetricsEvent event, {
    String? sessionId,
    String? videoId,
    Map<String, dynamic>? payload,
  }) {
    if (!_initialized || _db == null) return;

    // 检查隐私权限
    final privacy = PrivacyManagerService.instance;
    if (!privacy.canCollectMetrics) return;

    // 性能类事件检查性能数据开关
    if (_isPerformanceEvent(event) && !privacy.canCollectPerformanceData) return;

    final sid = sessionId ?? PlayerMetricsService.instance.currentSessionId ?? '';
    final vid = videoId ?? '';

    // 添加到待写入缓冲
    _pendingEvents.add(_PendingEvent(
      sessionId: sid,
      videoId: vid,
      eventType: event.name,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payloadJson: payload != null ? jsonEncode(payload) : '{}',
    ));

    // 异步写入数据库
    _flushPendingEvents();
  }

  /// 会话结束时写入会话汇总
  Future<void> onSessionEnd(PlaybackMetrics metrics) async {
    if (!_initialized || _db == null) return;

    final privacy = PrivacyManagerService.instance;
    if (!privacy.canCollectMetrics) return;

    try {
      await _db!.insertMetricsSession(MetricsSessionsCompanion.insert(
        sessionId: metrics.sessionId,
        videoId: metrics.videoId,
        startTime: metrics.startTime.millisecondsSinceEpoch,
        firstFrameTimeMs: Value(metrics.firstFrameTimeMs),
        bufferingCount: Value(metrics.bufferingCount),
        bufferingTotalMs: Value(metrics.bufferingTotalMs),
        stutterRate: Value(metrics.stutterRate),
        qualityChanges: Value(metrics.qualityChanges),
        seekCount: Value(metrics.seekCount),
        seekAvgMs: Value(metrics.seekAvgMs),
        errorCount: Value(metrics.errorCount),
        cacheHits: Value(metrics.cacheHits),
        cacheMisses: Value(metrics.cacheMisses),
        avgBandwidthKbps: Value(metrics.avgBandwidthKbps),
        peakBandwidthKbps: Value(metrics.peakBandwidthKbps),
        endTime: metrics.endTime != null
            ? Value(metrics.endTime!.millisecondsSinceEpoch)
            : const Value.absent(),
      ));

      _logger.d('会话汇总已持久化: ${metrics.sessionId}');
    } catch (e) {
      _logger.e('持久化会话汇总失败: $e');
    }
  }

  /// 指标流更新回调
  void _onMetricsUpdate(PlaybackMetrics metrics) {
    // 仅在会话有实质更新时触发，不主动写入
    // 实际写入由 recordEvent 和 onSessionEnd 驱动
  }

  /// 将待写入事件批量持久化
  Future<void> _flushPendingEvents() async {
    if (_pendingEvents.isEmpty || _db == null) return;

    final events = List<_PendingEvent>.from(_pendingEvents);
    _pendingEvents.clear();

    for (final event in events) {
      try {
        await _db!.insertMetricsEvent(MetricsEventsCompanion.insert(
          id: _generateEventId(event.timestamp),
          sessionId: event.sessionId,
          videoId: event.videoId,
          eventType: event.eventType,
          timestamp: event.timestamp,
          payloadJson: Value(event.payloadJson),
        ));
      } catch (e) {
        _logger.e('持久化事件失败: $e');
      }
    }
  }

  /// 判断事件是否属于性能数据类别
  bool _isPerformanceEvent(MetricsEvent event) {
    switch (event) {
      case MetricsEvent.firstFrame:
      case MetricsEvent.bufferingStart:
      case MetricsEvent.bufferingEnd:
      case MetricsEvent.qualityChange:
      case MetricsEvent.seekStart:
      case MetricsEvent.seekEnd:
      case MetricsEvent.playError:
      case MetricsEvent.cacheHit:
      case MetricsEvent.cacheMiss:
        return true;
      case MetricsEvent.playStart:
      case MetricsEvent.playComplete:
        return false;
    }
  }

  /// 生成事件 ID
  String _generateEventId(int timestamp) {
    return 'evt_${timestamp}_${DateTime.now().microsecond}';
  }

  /// 释放资源
  void dispose() {
    _metricsSubscription?.cancel();
    _flushPendingEvents();
    _initialized = false;
  }
}

/// 待写入事件
class _PendingEvent {
  final String sessionId;
  final String videoId;
  final String eventType;
  final int timestamp;
  final String payloadJson;

  _PendingEvent({
    required this.sessionId,
    required this.videoId,
    required this.eventType,
    required this.timestamp,
    required this.payloadJson,
  });
}
