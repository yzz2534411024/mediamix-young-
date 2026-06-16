import 'dart:async';
import 'package:logger/logger.dart';
import '../network/network_engine.dart' show BandwidthEstimator;

// ============================================================================
// 播放性能监控指标服务
// 对应优化文档第7章「监控与指标体系」，提供播放全链路质量数据采集与实时计算
// ============================================================================

/// 埋点事件枚举 — 对应优化文档 7.2 埋点方案中的关键事件
enum MetricsEvent {
  /// 用户点击播放
  playStart,

  /// 首帧渲染完成
  firstFrame,

  /// 缓冲开始（卡顿开始）
  bufferingStart,

  /// 缓冲结束（卡顿恢复）
  bufferingEnd,

  /// 码率/分辨率切换
  qualityChange,

  /// 用户发起 Seek
  seekStart,

  /// Seek 完成，画面更新
  seekEnd,

  /// 播放错误
  playError,

  /// 播放完成
  playComplete,

  /// 缓存命中
  cacheHit,

  /// 缓存未命中
  cacheMiss,
}

/// 播放指标汇总数据类 — 对应优化文档 7.1 QoE 核心监控指标
class PlaybackMetrics {
  /// 视频 ID
  final String videoId;

  /// 会话 ID（每次播放生成唯一标识）
  final String sessionId;

  /// 首屏时间（点击→首帧显示耗时，单位 ms）
  int firstFrameTimeMs;

  /// 卡顿次数
  int bufferingCount;

  /// 卡顿总时长（单位 ms）
  int bufferingTotalMs;

  /// 卡顿率 = 卡顿时长 / 总播放时长
  double stutterRate;

  /// 码率/分辨率切换次数
  int qualityChanges;

  /// Seek 操作次数
  int seekCount;

  /// Seek 平均延迟（单位 ms）
  int seekAvgMs;

  /// 播放错误次数
  int errorCount;

  /// 缓存命中次数
  int cacheHits;

  /// 缓存未命中次数
  int cacheMisses;

  /// 平均带宽估计（单位 kbps）
  double avgBandwidthKbps;

  /// 峰值带宽估计（单位 kbps）
  double peakBandwidthKbps;

  /// 会话开始时间
  final DateTime startTime;

  /// 会话结束时间
  DateTime? endTime;

  PlaybackMetrics({
    required this.videoId,
    required this.sessionId,
    this.firstFrameTimeMs = 0,
    this.bufferingCount = 0,
    this.bufferingTotalMs = 0,
    this.stutterRate = 0.0,
    this.qualityChanges = 0,
    this.seekCount = 0,
    this.seekAvgMs = 0,
    this.errorCount = 0,
    this.cacheHits = 0,
    this.cacheMisses = 0,
    this.avgBandwidthKbps = 0.0,
    this.peakBandwidthKbps = 0.0,
    required this.startTime,
    this.endTime,
  });

  /// 缓存命中率
  double get cacheHitRate {
    final total = cacheHits + cacheMisses;
    return total > 0 ? cacheHits / total : 0.0;
  }

  /// 总播放时长（单位 ms）
  int get totalPlayDurationMs {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime).inMilliseconds;
  }

  /// 导出为汇总报告 Map
  Map<String, dynamic> toSummaryMap() {
    return {
      'video_id': videoId,
      'session_id': sessionId,
      'first_frame_time_ms': firstFrameTimeMs,
      'buffering_count': bufferingCount,
      'buffering_total_ms': bufferingTotalMs,
      'stutter_rate': stutterRate.toStringAsFixed(4),
      'quality_changes': qualityChanges,
      'seek_count': seekCount,
      'seek_avg_ms': seekAvgMs,
      'error_count': errorCount,
      'cache_hits': cacheHits,
      'cache_misses': cacheMisses,
      'cache_hit_rate': cacheHitRate.toStringAsFixed(4),
      'avg_bandwidth_kbps': avgBandwidthKbps.toStringAsFixed(1),
      'peak_bandwidth_kbps': peakBandwidthKbps.toStringAsFixed(1),
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'total_play_duration_ms': totalPlayDurationMs,
    };
  }
}

/// 告警阈值配置 — 对应优化文档 7.1 中的告警阈值
class AlertThresholds {
  /// 首屏时间阈值（单位 ms），超过则告警。文档阈值：> 3s
  final int firstFrameTimeMs;

  /// 卡顿率阈值，超过则告警。文档阈值：> 3%
  final double stutterRate;

  /// 单次播放卡顿次数阈值，超过则告警。文档阈值：> 3次
  final int bufferingCount;

  /// 平均卡顿恢复时间阈值（单位 ms），超过则告警。文档阈值：> 2s
  final int bufferingAvgRecoveryMs;

  /// 码率切换次数阈值，超过则告警。文档阈值：> 5次
  final int qualityChangeCount;

  /// Seek 延迟阈值（单位 ms），超过则告警。文档阈值：> 2s
  final int seekLatencyMs;

  /// 播放失败率阈值，超过则告警。文档阈值：> 0.5%
  final double errorRate;

  /// 缓存命中率阈值，低于则告警。文档阈值：< 70%
  final double cacheHitRate;

  const AlertThresholds({
    this.firstFrameTimeMs = 3000,
    this.stutterRate = 0.03,
    this.bufferingCount = 3,
    this.bufferingAvgRecoveryMs = 2000,
    this.qualityChangeCount = 5,
    this.seekLatencyMs = 2000,
    this.errorRate = 0.005,
    this.cacheHitRate = 0.70,
  });
}

/// 单次会话内部状态，用于跟踪事件之间的时间差
class _SessionState {
  /// 会话 ID
  final String sessionId;

  /// 视频 ID
  final String videoId;

  /// 播放开始时间戳
  DateTime? playStartTime;

  /// 首帧时间戳
  DateTime? firstFrameTime;

  /// 当前缓冲开始时间戳（用于计算单次卡顿时长）
  DateTime? currentBufferingStart;

  /// 当前 Seek 开始时间戳（用于计算单次 Seek 延迟）
  DateTime? currentSeekStart;

  /// 所有 Seek 延迟记录（单位 ms）
  final List<int> seekLatencies = [];

  /// 所有卡顿时长记录（单位 ms）
  final List<int> bufferingDurations = [];

  /// 音视频同步偏移记录（单位 ms）
  final List<int> avSyncOffsets = [];

  /// 事件时间线（事件 → 时间戳）
  final List<MapEntry<MetricsEvent, DateTime>> eventTimeline = [];

  _SessionState({
    required this.sessionId,
    required this.videoId,
  });
}

/// 播放性能监控服务（单例）— 对应优化文档第7章监控与指标体系
///
/// 职责：
///   - 为每次视频播放创建独立会话
///   - 记录埋点事件及时间戳
///   - 实时计算 QoE 指标（首屏时间、卡顿率、Seek 延迟等）
///   - 提供指标更新流（Stream）
///   - 导出汇总报告
///   - 支持可配置的告警阈值
class PlayerMetricsService {
  static PlayerMetricsService? _instance;

  static PlayerMetricsService get instance => _instance ??= PlayerMetricsService._();

  PlayerMetricsService._();

  final Logger _logger = Logger(printer: const SimplePrinter());

  /// 当前活跃会话状态
  _SessionState? _currentSession;

  /// 当前会话的指标数据
  PlaybackMetrics? _currentMetrics;

  /// 带宽估计器
  final BandwidthEstimator _bandwidthEstimator = BandwidthEstimator();

  /// 告警阈值配置
  AlertThresholds _alertThresholds = const AlertThresholds();

  /// 指标更新流控制器
  final StreamController<PlaybackMetrics> _metricsController =
      StreamController<PlaybackMetrics>.broadcast();

  /// 告警流控制器
  final StreamController<Map<String, dynamic>> _alertController =
      StreamController<Map<String, dynamic>>.broadcast();

  // ==========================================================================
  // 公开 API
  // ==========================================================================

  /// 指标更新流，每次事件处理后推送最新指标
  Stream<PlaybackMetrics> get metricsStream => _metricsController.stream;

  /// 告警流，当指标超过阈值时推送告警信息
  Stream<Map<String, dynamic>> get alertStream => _alertController.stream;

  /// 当前会话 ID
  String? get currentSessionId => _currentSession?.sessionId;

  /// 当前带宽估计值（kbps）
  double get currentBandwidthEstimate => _bandwidthEstimator.estimateBandwidth();

  /// 更新告警阈值配置
  void setAlertThresholds(AlertThresholds thresholds) {
    _alertThresholds = thresholds;
  }

  /// 开始新的播放会话
  ///
  /// 每次视频播放开始时调用，生成唯一 sessionId 并初始化指标
  String startSession(String videoId) {
    // 如果有未结束的会话，先结束
    if (_currentSession != null) {
      endSession();
    }

    final sessionId = _generateSessionId();
    _currentSession = _SessionState(
      sessionId: sessionId,
      videoId: videoId,
    );
    _currentMetrics = PlaybackMetrics(
      videoId: videoId,
      sessionId: sessionId,
      startTime: DateTime.now(),
    );
    _bandwidthEstimator.reset();

    _logger.i('播放监控会话已创建: sessionId=$sessionId, videoId=$videoId');
    return sessionId;
  }

  /// 结束当前播放会话
  PlaybackMetrics? endSession() {
    if (_currentSession == null || _currentMetrics == null) return null;

    _currentMetrics!.endTime = DateTime.now();
    _recalculateMetrics();

    final summary = _currentMetrics!;

    _logger.i(
      '播放监控会话已结束: sessionId=${summary.sessionId}, '
      '首屏=${summary.firstFrameTimeMs}ms, '
      '卡顿率=${(summary.stutterRate * 100).toStringAsFixed(2)}%, '
      '缓存命中率=${(summary.cacheHitRate * 100).toStringAsFixed(1)}%',
    );

    _currentSession = null;
    _currentMetrics = null;

    return summary;
  }

  /// 记录埋点事件 — 对应优化文档 7.2 埋点方案
  ///
  /// 每个事件携带 video_id、session_id、timestamp 等公共字段
  void recordEvent(
    MetricsEvent event, {
    int? bytesDownloaded,
    int? downloadDurationMs,
    int? avSyncOffsetMs,
    String? errorMessage,
    String? qualityInfo,
  }) {
    if (_currentSession == null || _currentMetrics == null) {
      _logger.w('记录事件失败：无活跃会话，事件=${event.name}');
      return;
    }

    final now = DateTime.now();

    // 记录事件时间线
    _currentSession!.eventTimeline.add(MapEntry(event, now));

    // 根据事件类型更新指标
    switch (event) {
      case MetricsEvent.playStart:
        _handlePlayStart(now);
        break;
      case MetricsEvent.firstFrame:
        _handleFirstFrame(now);
        break;
      case MetricsEvent.bufferingStart:
        _handleBufferingStart(now);
        break;
      case MetricsEvent.bufferingEnd:
        _handleBufferingEnd(now);
        break;
      case MetricsEvent.qualityChange:
        _handleQualityChange(qualityInfo);
        break;
      case MetricsEvent.seekStart:
        _handleSeekStart(now);
        break;
      case MetricsEvent.seekEnd:
        _handleSeekEnd(now);
        break;
      case MetricsEvent.playError:
        _handlePlayError(errorMessage);
        break;
      case MetricsEvent.playComplete:
        _handlePlayComplete(now);
        break;
      case MetricsEvent.cacheHit:
        _handleCacheHit();
        break;
      case MetricsEvent.cacheMiss:
        _handleCacheMiss();
        break;
    }

    // 处理带宽采样
    if (bytesDownloaded != null && downloadDurationMs != null) {
      _bandwidthEstimator.addSample(bytesDownloaded, downloadDurationMs);
      _currentMetrics!.avgBandwidthKbps = _bandwidthEstimator.estimateBandwidth();
      _currentMetrics!.peakBandwidthKbps = _bandwidthEstimator.peak;
    }

    // 记录音视频同步偏移
    if (avSyncOffsetMs != null) {
      _currentSession!.avSyncOffsets.add(avSyncOffsetMs.abs());
    }

    // 重新计算派生指标
    _recalculateMetrics();

    // 推送指标更新
    _metricsController.add(_currentMetrics!);

    // 检查告警
    _checkAlerts();
  }

  /// 获取当前实时指标快照
  PlaybackMetrics? getCurrentMetrics() {
    if (_currentMetrics == null) return null;
    _recalculateMetrics();
    return _currentMetrics!;
  }

  /// 导出当前会话的汇总报告
  Map<String, dynamic>? exportSummary() {
    if (_currentMetrics == null) return null;
    _recalculateMetrics();
    return _currentMetrics!.toSummaryMap();
  }

  /// 释放资源
  void dispose() {
    _metricsController.close();
    _alertController.close();
  }

  // ==========================================================================
  // 事件处理
  // ==========================================================================

  void _handlePlayStart(DateTime timestamp) {
    _currentSession!.playStartTime = timestamp;
  }

  void _handleFirstFrame(DateTime timestamp) {
    _currentSession!.firstFrameTime = timestamp;

    // 计算首屏时间：点击→首帧显示耗时
    if (_currentSession!.playStartTime != null) {
      _currentMetrics!.firstFrameTimeMs =
          timestamp.difference(_currentSession!.playStartTime!).inMilliseconds;
    }
  }

  void _handleBufferingStart(DateTime timestamp) {
    _currentSession!.currentBufferingStart = timestamp;
  }

  void _handleBufferingEnd(DateTime timestamp) {
    final bufferingStart = _currentSession!.currentBufferingStart;
    if (bufferingStart != null) {
      final durationMs = timestamp.difference(bufferingStart).inMilliseconds;
      _currentSession!.bufferingDurations.add(durationMs);
      _currentMetrics!.bufferingCount++;
      _currentMetrics!.bufferingTotalMs += durationMs;
      _currentSession!.currentBufferingStart = null;
    }
  }

  void _handleQualityChange(String? qualityInfo) {
    _currentMetrics!.qualityChanges++;
    _logger.d('码率切换: $qualityInfo');
  }

  void _handleSeekStart(DateTime timestamp) {
    _currentSession!.currentSeekStart = timestamp;
  }

  void _handleSeekEnd(DateTime timestamp) {
    final seekStart = _currentSession!.currentSeekStart;
    if (seekStart != null) {
      final latencyMs = timestamp.difference(seekStart).inMilliseconds;
      _currentSession!.seekLatencies.add(latencyMs);
      _currentMetrics!.seekCount++;
      _currentSession!.currentSeekStart = null;
    }
  }

  void _handlePlayError(String? errorMessage) {
    _currentMetrics!.errorCount++;
    _logger.w('播放错误: $errorMessage');
  }

  void _handlePlayComplete(DateTime timestamp) {
    _currentMetrics!.endTime = timestamp;
  }

  void _handleCacheHit() {
    _currentMetrics!.cacheHits++;
  }

  void _handleCacheMiss() {
    _currentMetrics!.cacheMisses++;
  }

  // ==========================================================================
  // 指标计算
  // ==========================================================================

  /// 重新计算所有派生指标
  void _recalculateMetrics() {
    if (_currentMetrics == null || _currentSession == null) return;

    // 卡顿率 = 卡顿时长 / 总播放时长
    final totalDurationMs = _currentMetrics!.totalPlayDurationMs;
    if (totalDurationMs > 0) {
      _currentMetrics!.stutterRate =
          _currentMetrics!.bufferingTotalMs / totalDurationMs;
    }

    // Seek 平均延迟
    final seekLatencies = _currentSession!.seekLatencies;
    if (seekLatencies.isNotEmpty) {
      _currentMetrics!.seekAvgMs =
          seekLatencies.reduce((a, b) => a + b) ~/ seekLatencies.length;
    }

    // 带宽估计
    _currentMetrics!.avgBandwidthKbps = _bandwidthEstimator.estimateBandwidth();
    _currentMetrics!.peakBandwidthKbps = _bandwidthEstimator.peak;
  }

  // ==========================================================================
  // 告警检查 — 对应优化文档 7.1 告警阈值
  // ==========================================================================

  void _checkAlerts() {
    if (_currentMetrics == null) return;
    final m = _currentMetrics!;
    final t = _alertThresholds;

    // 首屏时间告警
    if (m.firstFrameTimeMs > 0 && m.firstFrameTimeMs > t.firstFrameTimeMs) {
      _emitAlert('first_frame_time', '首屏时间 ${m.firstFrameTimeMs}ms 超过阈值 ${t.firstFrameTimeMs}ms');
    }

    // 卡顿率告警
    if (m.stutterRate > t.stutterRate) {
      _emitAlert('stutter_rate', '卡顿率 ${(m.stutterRate * 100).toStringAsFixed(2)}% 超过阈值 ${(t.stutterRate * 100).toStringAsFixed(2)}%');
    }

    // 卡顿次数告警
    if (m.bufferingCount > t.bufferingCount) {
      _emitAlert('buffering_count', '卡顿次数 ${m.bufferingCount} 超过阈值 ${t.bufferingCount}');
    }

    // 平均卡顿恢复时间告警
    if (m.bufferingCount > 0 && m.bufferingTotalMs ~/ m.bufferingCount > t.bufferingAvgRecoveryMs) {
      final avgRecovery = m.bufferingTotalMs ~/ m.bufferingCount;
      _emitAlert('buffering_avg_recovery', '平均卡顿恢复时间 ${avgRecovery}ms 超过阈值 ${t.bufferingAvgRecoveryMs}ms');
    }

    // 码率切换次数告警
    if (m.qualityChanges > t.qualityChangeCount) {
      _emitAlert('quality_change_count', '码率切换次数 ${m.qualityChanges} 超过阈值 ${t.qualityChangeCount}');
    }

    // Seek 延迟告警
    if (m.seekAvgMs > t.seekLatencyMs) {
      _emitAlert('seek_latency', 'Seek 平均延迟 ${m.seekAvgMs}ms 超过阈值 ${t.seekLatencyMs}ms');
    }

    // 缓存命中率告警
    if (m.cacheHits + m.cacheMisses > 0 && m.cacheHitRate < t.cacheHitRate) {
      _emitAlert('cache_hit_rate', '缓存命中率 ${(m.cacheHitRate * 100).toStringAsFixed(1)}% 低于阈值 ${(t.cacheHitRate * 100).toStringAsFixed(1)}%');
    }
  }

  void _emitAlert(String alertType, String message) {
    _logger.w('[告警] $message');
    _alertController.add({
      'type': alertType,
      'message': message,
      'session_id': _currentMetrics?.sessionId,
      'video_id': _currentMetrics?.videoId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ==========================================================================
  // 工具方法
  // ==========================================================================

  /// 生成唯一会话 ID
  String _generateSessionId() {
    final now = DateTime.now();
    return 'sess_${now.millisecondsSinceEpoch}_${now.microsecond}';
  }
}
