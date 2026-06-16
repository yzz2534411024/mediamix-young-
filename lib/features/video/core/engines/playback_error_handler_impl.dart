import 'dart:async';
import 'package:logger/logger.dart';

import '../../../../core/network/network_engine.dart';
import 'engine_interfaces.dart';

// ============================================================================
// 播放错误处理器实现 — 从 PlayerCoreManager 提取的错误处理逻辑
// ============================================================================

/// 播放错误处理器实现
///
/// 负责播放错误的分类、重试、清晰度降级、弱网自动重连等策略。
/// 从 PlayerCoreManager 的优化12（错误处理增强 + 弱网自动重连）中提取。
class PlaybackErrorHandlerImpl implements PlaybackErrorHandler {
  final Logger _logger = Logger(printer: const SimplePrinter());

  // ========== 重试逻辑 ==========
  /// 当前重试计数
  int _retryCount = 0;

  /// 最大自动重试次数
  static const int _maxAutoRetry = 1;

  // ========== 清晰度降级 ==========
  /// 已尝试过的清晰度索引集合
  final Set<int> _triedQualityIndices = {};

  /// 清晰度选项总数（由外部设置）
  int _qualityCount = 0;

  // ========== 网络恢复 ==========
  /// 是否正在等待网络恢复
  bool _isWaitingForNetwork = false;

  /// 重连探测定时器
  Timer? _reconnectTimer;

  /// 当前重连探测次数
  int _reconnectAttempt = 0;

  /// 最大重连探测次数
  static const int _maxReconnectAttempts = 10;

  /// 网络条件变化订阅
  StreamSubscription<NetworkCondition>? _networkRecoverySubscription;

  /// 网络恢复回调
  void Function()? _onNetworkRecovered;

  // ========== 上次播放位置 ==========
  /// 上次播放位置（由 handleError 保存）
  Duration _lastPlaybackPosition = Duration.zero;

  @override
  int get retryCount => _retryCount;

  @override
  bool get isWaitingForNetwork => _isWaitingForNetwork;

  /// 设置清晰度选项总数（供外部在清晰度列表变化时调用）
  set qualityCount(int count) => _qualityCount = count;

  // ========================================================================
  // 错误分类
  // ========================================================================

  /// 判断错误是否为编解码相关
  bool _isCodecError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('codec') ||
        lower.contains('decoder') ||
        lower.contains('mediacodec') ||
        lower.contains('unsupported') ||
        lower.contains('format') ||
        lower.contains('avc') ||
        lower.contains('hevc') ||
        lower.contains('vp9') ||
        lower.contains('av1') ||
        lower.contains('hwdec') ||
        lower.contains('hardware') ||
        lower.contains('software');
  }

  /// 判断错误是否与网络相关
  bool _isErrorNetworkRelated(String error) {
    final lower = error.toLowerCase();
    return lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('timeout') ||
        lower.contains('dns') ||
        lower.contains('unreachable') ||
        lower.contains('refused') ||
        lower.contains('socket') ||
        lower.contains('host') ||
        lower.contains('econnreset') ||
        lower.contains('econnrefused') ||
        lower.contains('etimedout') ||
        lower.contains('enotfound');
  }

  // ========================================================================
  // 核心错误处理
  // ========================================================================

  @override
  ErrorHandleResult handleError(
    String error, {
    required bool hardwareDecodingEnabled,
    required bool hasQualityOptions,
    required int currentQualityIndex,
    required Duration lastPlaybackPosition,
  }) {
    // 保存断点位置
    _lastPlaybackPosition = lastPlaybackPosition;

    // 1. 检查是否为编解码错误 + 硬解码开启 → 降级软解
    if (_isCodecError(error) && hardwareDecodingEnabled) {
      _logger.w('检测到硬解码失败，建议降级软解');
      return ErrorHandleResult(action: ErrorAction.downgradeToSoftwareDecode);
    }

    // 2. 检查是否为网络错误或离线/弱网 → 等待网络恢复
    final isNetworkError = _isErrorNetworkRelated(error);
    final networkOffline =
        NetworkEngine.instance.currentCondition == NetworkCondition.offline ||
            NetworkEngine.instance.currentCondition == NetworkCondition.weak;

    if (isNetworkError || networkOffline) {
      _logger.w('网络原因导致播放中断，等待网络恢复后自动重连');
      _isWaitingForNetwork = true;
      return ErrorHandleResult(action: ErrorAction.waitForNetworkRecovery);
    }

    // 3. 非网络错误：快速重试一次（同 URL）
    if (_retryCount < _maxAutoRetry) {
      _retryCount++;
      _logger.i('播放错误，自动重试 ($_retryCount/$_maxAutoRetry): $error');
      return ErrorHandleResult(action: ErrorAction.retrySameUrl);
    }

    // 4. 降级策略：同 URL 重试失败后，尝试其他清晰度源
    if (hasQualityOptions && !_isWaitingForNetwork) {
      _triedQualityIndices.add(currentQualityIndex);
      final nextIndex = _findNextUntriedQuality();
      if (nextIndex >= 0) {
        _logger.i('降级切换清晰度: 当前=$currentQualityIndex → 下一个=$nextIndex');
        _retryCount = 0; // 重置重试计数，给新源一次重试机会
        return ErrorHandleResult(
          action: ErrorAction.switchToNextQuality,
          nextQualityIndex: nextIndex,
        );
      }
    }

    // 5. 所有源都失败，显示错误对话框
    return ErrorHandleResult(action: ErrorAction.showErrorDialog);
  }

  // ========================================================================
  // 清晰度降级
  // ========================================================================

  /// 找到下一个未尝试的清晰度索引，-1 表示全部已尝试
  int _findNextUntriedQuality() {
    for (int i = 0; i < _qualityCount; i++) {
      if (!_triedQualityIndices.contains(i)) return i;
    }
    return -1;
  }

  @override
  int findNextUntriedQuality() => _findNextUntriedQuality();

  @override
  void clearTriedQualityIndices() {
    _triedQualityIndices.clear();
  }

  @override
  void addTriedQualityIndex(int index) {
    _triedQualityIndices.add(index);
  }

  @override
  void resetRetryCount() {
    _retryCount = 0;
  }

  // ========================================================================
  // 网络恢复监听
  // ========================================================================

  @override
  void startNetworkRecoveryMonitoring({
    required void Function() onNetworkRecovered,
  }) {
    _onNetworkRecovered = onNetworkRecovered;
    _networkRecoverySubscription?.cancel();
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;

    // 监听网络条件恢复
    _networkRecoverySubscription =
        NetworkEngine.instance.onConditionChanged.listen((condition) {
      if (_isWaitingForNetwork &&
          condition != NetworkCondition.offline &&
          condition != NetworkCondition.weak) {
        _logger.i('网络已恢复(${condition.name})，触发重连回调');
        _handleNetworkRecovered();
      }
    });

    // 同时启动指数退避探测定时器（防止流事件丢失）
    _scheduleReconnectProbe();
  }

  @override
  void stopNetworkRecoveryMonitoring() {
    _networkRecoverySubscription?.cancel();
    _networkRecoverySubscription = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isWaitingForNetwork = false;
    _reconnectAttempt = 0;
    _onNetworkRecovered = null;
  }

  /// 网络恢复后的处理
  void _handleNetworkRecovered() {
    _networkRecoverySubscription?.cancel();
    _reconnectTimer?.cancel();
    _isWaitingForNetwork = false;
    _reconnectAttempt = 0;
    _retryCount = 0; // 重置重试计数
    _onNetworkRecovered?.call();
  }

  /// 指数退避探测：在网络未恢复前周期性尝试
  ///
  /// 退避策略：1s, 2s, 4s, 8s, 16s, 32s, 32s, 32s...
  /// 最大探测次数为 [_maxReconnectAttempts]（10次）
  void _scheduleReconnectProbe() {
    if (!_isWaitingForNetwork) return;

    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _logger.w('已达最大重连次数($_maxReconnectAttempts)，停止自动重连');
      _isWaitingForNetwork = false;
      return;
    }

    // 指数退避：1 << 0 = 1s, 1 << 1 = 2s, ..., 1 << 5 = 32s（上限）
    final delay = Duration(
      seconds: 1 << _reconnectAttempt.clamp(0, 5),
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_isWaitingForNetwork) return;

      final condition = NetworkEngine.instance.currentCondition;
      if (condition != NetworkCondition.offline &&
          condition != NetworkCondition.weak) {
        _logger.i('探测到网络恢复，触发重连回调');
        _handleNetworkRecovered();
      } else {
        _logger.d('网络未恢复，${delay.inSeconds}s 后再次探测');
        _reconnectAttempt++;
        _scheduleReconnectProbe();
      }
    });
  }

  // ========================================================================
  // 资源释放
  // ========================================================================

  @override
  void dispose() {
    _networkRecoverySubscription?.cancel();
    _networkRecoverySubscription = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _onNetworkRecovered = null;
    _triedQualityIndices.clear();
  }
}
