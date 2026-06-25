import '../../../../core/services/player_metrics_service.dart';
import '../../../../core/services/metrics_collector_service.dart';
import 'engine_interfaces.dart';

// ============================================================================
// 指标引擎实现 — 从 PlayerCoreManager 提取的指标采集逻辑
// ============================================================================

/// 指标引擎实现
///
/// 将播放性能监控委托给 PlayerMetricsService 和 MetricsCollectorService，
/// 同时管理首帧标记和缓冲状态。
class MetricsEngineImpl implements MetricsEngine {
  // ========== 首帧标记 ==========
  /// 是否已记录首帧
  bool _hasRecordedFirstFrame = false;

  // ========== 缓冲状态 ==========
  /// 是否正在缓冲
  bool _isBuffering = false;

  // ========== 会话状态 ==========
  /// 是否有活跃会话
  bool _hasActiveSession = false;

  @override
  bool get hasRecordedFirstFrame => _hasRecordedFirstFrame;

  @override
  bool get isBuffering => _isBuffering;

  // ========================================================================
  // 会话管理
  // ========================================================================

  @override
  void startSession(String videoId) {
    // 重置首帧标记
    _hasRecordedFirstFrame = false;
    _hasActiveSession = true;

    // 委托给 PlayerMetricsService 开始会话
    PlayerMetricsService.instance.startSession(videoId);
  }

  @override
  Map<String, dynamic>? endSession() {
    if (!_hasActiveSession) return null;
    _hasActiveSession = false;

    // 委托给 PlayerMetricsService 结束会话，获取指标数据
    final metrics = PlayerMetricsService.instance.endSession();

    if (metrics != null) {
      // 委托给 MetricsCollectorService 持久化会话汇总
      MetricsCollectorService.instance.onSessionEnd(metrics);
      return metrics.toSummaryMap();
    }

    return null;
  }

  // ========================================================================
  // 事件记录
  // ========================================================================

  @override
  void recordEvent(
    MetricsEvent event, {
    String? errorMessage,
    int? avSyncOffsetMs,
  }) {
    // 委托给 PlayerMetricsService 记录事件
    PlayerMetricsService.instance.recordEvent(
      event,
      errorMessage: errorMessage,
      avSyncOffsetMs: avSyncOffsetMs,
    );

    // 委托给 MetricsCollectorService 持久化事件，带诊断 payload
    final payload = <String, dynamic>{};
    if (errorMessage != null) payload['error'] = errorMessage;
    if (avSyncOffsetMs != null) payload['avSyncOffsetMs'] = avSyncOffsetMs;
    MetricsCollectorService.instance.recordEvent(
      event,
      payload: payload.isNotEmpty ? payload : null,
    );
  }

  // ========================================================================
  // 实时指标
  // ========================================================================

  @override
  Map<String, dynamic>? getCurrentMetrics() {
    if (!_hasActiveSession) return null;
    final metrics = PlayerMetricsService.instance.getCurrentMetrics();
    return metrics?.toSummaryMap();
  }

  // ========================================================================
  // 首帧与缓冲状态管理
  // ========================================================================

  @override
  void markFirstFrameRecorded() {
    _hasRecordedFirstFrame = true;
  }

  @override
  void setBuffering(bool value) {
    _isBuffering = value;
  }

  // ========================================================================
  // 资源释放
  // ========================================================================

  @override
  void dispose() {
    // 重置内部状态
    _hasRecordedFirstFrame = false;
    _isBuffering = false;
    _hasActiveSession = false;
  }
}
