import '../../../../core/services/player_metrics_service.dart' show MetricsEvent;
import '../../../../core/services/power_manager_service.dart' show PowerMode;

// ============================================================================
// 引擎接口定义 — 播放器核心引擎的抽象层
// ============================================================================

/// 缓存引擎接口
abstract class CacheEngine {
  /// 解析视频 URL — 优先使用本地缓存，其次走本地代理边播边缓存
  Future<String> resolveVideoUrl(String url, String videoId);

  /// 是否正在使用本地缓存
  bool get isUsingCache;

  /// 通知预加载服务缓冲状态
  void notifyPreloadBuffering(bool isBuffering);

  /// 预加载下一集
  void preloadNextEpisode(String videoId, String url);

  /// 预加载相邻集
  void preloadAdjacentEpisodes(
    List<int> indices,
    String title,
    List<String> episodeUrls,
    PowerMode powerMode,
  );

  /// 释放资源
  void dispose();
}

/// 错误处理动作枚举
enum ErrorAction {
  /// 降级到软解码
  downgradeToSoftwareDecode,

  /// 等待网络恢复
  waitForNetworkRecovery,

  /// 使用相同 URL 重试
  retrySameUrl,

  /// 切换到下一个清晰度
  switchToNextQuality,

  /// 显示错误对话框
  showErrorDialog,
}

/// 错误处理结果
class ErrorHandleResult {
  /// 建议的处理动作
  final ErrorAction action;

  /// 下一个未尝试的清晰度索引（仅 switchToNextQuality 时有效）
  final int? nextQualityIndex;

  ErrorHandleResult({
    required this.action,
    this.nextQualityIndex,
  });
}

/// 播放错误处理器接口
abstract class PlaybackErrorHandler {
  /// 处理播放错误，返回处理结果
  ErrorHandleResult handleError(
    String error, {
    required bool hardwareDecodingEnabled,
    required bool hasQualityOptions,
    required int currentQualityIndex,
    required Duration lastPlaybackPosition,
  });

  /// 是否正在等待网络恢复
  bool get isWaitingForNetwork;

  /// 查找下一个未尝试的清晰度索引，-1 表示全部已尝试
  int findNextUntriedQuality();

  /// 重置重试计数
  void resetRetryCount();

  /// 清除已尝试的清晰度记录
  void clearTriedQualityIndices();

  /// 添加已尝试的清晰度索引
  void addTriedQualityIndex(int index);

  /// 启动网络恢复监听
  void startNetworkRecoveryMonitoring({
    required void Function() onNetworkRecovered,
  });

  /// 停止网络恢复监听
  void stopNetworkRecoveryMonitoring();

  /// 当前重试计数
  int get retryCount;

  /// 释放资源
  void dispose();
}

/// 指标引擎接口
abstract class MetricsEngine {
  /// 开始新的监控会话
  void startSession(String videoId);

  /// 结束当前监控会话，返回指标数据
  Map<String, dynamic>? endSession();

  /// 记录埋点事件
  void recordEvent(
    MetricsEvent event, {
    String? errorMessage,
    int? avSyncOffsetMs,
  });

  /// 获取当前实时指标快照
  Map<String, dynamic>? getCurrentMetrics();

  /// 是否已记录首帧
  bool get hasRecordedFirstFrame;

  /// 标记首帧已记录
  void markFirstFrameRecorded();

  /// 是否正在缓冲
  bool get isBuffering;

  /// 设置缓冲状态
  void setBuffering(bool value);

  /// 释放资源
  void dispose();
}
