import 'dart:async';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/network_engine.dart';

// ============================================================================
// 画质等级
// ============================================================================

/// 视频画质等级
enum QualityLevel {
  low('流畅'),
  medium('标清'),
  high('高清'),
  ultra('超清');

  final String label;
  const QualityLevel(this.label);
}

// ============================================================================
// 缓冲区管理器
// ============================================================================

/// 缓冲区水位线配置
class BufferWaterLines {
  final Duration low;
  final Duration high;
  final Duration max;

  const BufferWaterLines({
    required this.low,
    required this.high,
    required this.max,
  });

  static const wifi = BufferWaterLines(
    low: Duration(seconds: 3),
    high: Duration(seconds: 20),
    max: Duration(seconds: 60),
  );

  static const mobile4G = BufferWaterLines(
    low: Duration(seconds: 5),
    high: Duration(seconds: 15),
    max: Duration(seconds: 30),
  );

  static const weak = BufferWaterLines(
    low: Duration(seconds: 8),
    high: Duration(seconds: 10),
    max: Duration(seconds: 15),
  );
}

/// 缓冲区管理器 — 监控缓冲状态，动态调整水位线
class BufferManager {
  final Logger _logger = Logger(printer: SimplePrinter());

  BufferWaterLines _waterLines = BufferWaterLines.wifi;
  Duration _currentBuffer = Duration.zero;
  bool _isLowBuffer = false;

  void Function(bool isLow)? onBufferStateChanged;

  BufferManager({this.onBufferStateChanged})
      : _isLowBuffer = Duration.zero < BufferWaterLines.wifi.low;

  BufferWaterLines get waterLines => _waterLines;
  Duration get currentBuffer => _currentBuffer;
  bool get isLowBuffer => _isLowBuffer;

  static BufferWaterLines waterLinesForCondition(NetworkCondition condition) {
    switch (condition) {
      case NetworkCondition.wifi:
        return BufferWaterLines.wifi;
      case NetworkCondition.lte:
        return BufferWaterLines.mobile4G;
      case NetworkCondition.threeG:
        return BufferWaterLines.weak;
      case NetworkCondition.weak:
        return BufferWaterLines.weak;
      case NetworkCondition.offline:
        return BufferWaterLines.weak;
    }
  }

  void updateNetworkCondition(NetworkCondition condition) {
    _waterLines = waterLinesForCondition(condition);
    _logger.d('缓冲水位线更新: ${condition.name}');
    _checkBufferState();
  }

  void updateBuffer(Duration buffer) {
    _currentBuffer = buffer;
    _checkBufferState();
  }

  void _checkBufferState() {
    final wasLow = _isLowBuffer;
    _isLowBuffer = _currentBuffer < _waterLines.low;
    if (wasLow != _isLowBuffer) {
      onBufferStateChanged?.call(_isLowBuffer);
    }
  }

  double get bufferPercent {
    if (_waterLines.max.inMilliseconds <= 0) return 0.0;
    return (_currentBuffer.inMilliseconds / _waterLines.max.inMilliseconds)
        .clamp(0.0, 1.0);
  }
}

// ============================================================================
// ABR 自适应码率控制器
// ============================================================================

/// ABR 自适应码率控制器
///
/// 基于吞吐量预测的智能码率选择：
/// - 预测吞吐量（主因素，权重 60%）
/// - 当前缓冲水位（安全因素，权重 25%）
/// - 历史带宽稳定性（趋势因素，权重 15%）
/// - 切换防抖：连续 2 次预测一致才执行切换
/// - 安全余量：预测吞吐量 * 0.8 作为实际选择依据
class ABRController {
  final Logger _logger = Logger(printer: SimplePrinter());

  double _currentBandwidthKbps = 0;
  Duration _currentBuffer = Duration.zero;
  DateTime? _lastSwitchTime;
  DateTime? _highBandwidthStart;

  final Duration _upgradeDelay;
  final Duration _minSwitchInterval;
  static const Duration _downgradeBufferThreshold = Duration(seconds: 5);
  static const Duration _upgradeBufferThreshold = Duration(seconds: 30);

  // ---- 吞吐量预测相关 ----
  ThroughputPrediction? _latestPrediction;

  // 决策权重
  static const double _throughputWeight = 0.60;
  static const double _bufferWeight = 0.25;
  static const double _stabilityWeight = 0.15;

  // 安全余量系数
  static const double _safetyMargin = 0.8;

  // 切换防抖：连续 2 次预测一致才执行
  static const int _debounceCount = 2;
  QualityLevel? _pendingQuality;
  int _pendingCount = 0;

  QualityLevel _currentQuality = QualityLevel.medium;

  void Function(QualityLevel level)? onQualityChanged;

  ABRController({
    this.onQualityChanged,
    Duration? upgradeDelay,
    Duration? minSwitchInterval,
  })  : _upgradeDelay = upgradeDelay ?? const Duration(seconds: 5),
        _minSwitchInterval = minSwitchInterval ?? const Duration(seconds: 10);

  QualityLevel get currentQuality => _currentQuality;

  /// 当前吞吐量预测结果（可能为 null）
  ThroughputPrediction? get latestPrediction => _latestPrediction;

  /// 更新带宽值（兼容旧接口，同时作为回退）
  void updateBandwidth(double kbps) {
    _currentBandwidthKbps = kbps;
    _evaluate();
  }

  /// 更新缓冲区状态
  void updateBuffer(Duration buffer) {
    _currentBuffer = buffer;
    _evaluate();
  }

  /// 更新吞吐量预测数据（新接口，由 PlayerCoreManager 调用）
  void updateThroughputPrediction(ThroughputPrediction prediction) {
    _latestPrediction = prediction;
    _currentBandwidthKbps = prediction.predictedKbps;
    _evaluate();
  }

  void _evaluate() {
    final now = DateTime.now();

    // 切换冷却期保护
    if (_lastSwitchTime != null &&
        now.difference(_lastSwitchTime!) < _minSwitchInterval) {
      return;
    }

    // 紧急降级：缓冲 < 5s 时立即降级，不受防抖约束
    if (_currentBuffer < _downgradeBufferThreshold &&
        _currentQuality != QualityLevel.low) {
      _pendingQuality = null;
      _pendingCount = 0;
      _switchQuality(QualityLevel.low, '缓冲不足，紧急降级画质');
      return;
    }

    // 智能码率决策
    final targetQuality = _computeTargetQuality();
    if (targetQuality == null) return;

    if (targetQuality.index > _currentQuality.index) {
      // 升级需要防抖 + 延迟确认
      _applyDebounce(targetQuality, now);
    } else if (targetQuality.index < _currentQuality.index) {
      // 降级也需要防抖（但缓冲紧急降级已在上面处理）
      _applyDebounce(targetQuality, now);
    } else {
      // 目标与当前一致，重置防抖
      _pendingQuality = null;
      _pendingCount = 0;
      _highBandwidthStart = null;
    }
  }

  /// 应用切换防抖逻辑
  void _applyDebounce(QualityLevel target, DateTime now) {
    if (target == _pendingQuality) {
      _pendingCount++;
    } else {
      _pendingQuality = target;
      _pendingCount = 1;
    }

    if (_pendingCount >= _debounceCount) {
      // 防抖通过，执行升级延迟检查
      if (target.index > _currentQuality.index) {
        // 升级：需要缓冲充足 + 延迟确认
        if (_currentBuffer > _upgradeBufferThreshold) {
          if (_highBandwidthStart == null) {
            _highBandwidthStart = now;
          } else if (now.difference(_highBandwidthStart!) >= _upgradeDelay) {
            _switchQuality(target, '预测吞吐量充足，升级画质');
            _pendingQuality = null;
            _pendingCount = 0;
          }
        } else {
          _highBandwidthStart = null;
        }
      } else {
        // 降级：防抖通过直接执行
        _switchQuality(target, '预测吞吐量不足，降级画质');
        _pendingQuality = null;
        _pendingCount = 0;
      }
    }
  }

  /// 基于加权模型计算目标画质
  ///
  /// 决策因素：
  /// - 预测吞吐量（60%）：使用安全余量后的有效吞吐量
  /// - 当前缓冲水位（25%）：缓冲充足时倾向于更高画质
  /// - 历史带宽稳定性（15%）：稳定性高时更信任预测
  QualityLevel? _computeTargetQuality() {
    // 获取三个因素的评分
    final throughputScore = _computeThroughputScore();
    final bufferScore = _computeBufferScore();
    final stabilityScore = _computeStabilityScore();

    // 加权综合评分（0.0 - 1.0）
    final weightedScore = throughputScore * _throughputWeight +
        bufferScore * _bufferWeight +
        stabilityScore * _stabilityWeight;

    // 将综合评分映射到画质等级
    return _scoreToQuality(weightedScore);
  }

  /// 吞吐量评分（0.0 - 1.0）
  ///
  /// 使用预测吞吐量 * 安全余量，映射到 [0, 1]。
  double _computeThroughputScore() {
    double effectiveKbps;
    if (_latestPrediction != null) {
      effectiveKbps = _latestPrediction!.predictedKbps * _safetyMargin;
    } else {
      effectiveKbps = _currentBandwidthKbps * _safetyMargin;
    }
    if (effectiveKbps <= 0) return 0.0;
    // 映射到 [0, 1]：10000kbps 为满分
    return (effectiveKbps / 10000).clamp(0.0, 1.0);
  }

  /// 缓冲水位评分（0.0 - 1.0）
  ///
  /// 缓冲充足时评分高，允许更高画质。
  double _computeBufferScore() {
    final bufferSec = _currentBuffer.inSeconds;
    if (bufferSec >= 30) return 1.0;
    if (bufferSec <= 5) return 0.0;
    return (bufferSec - 5) / 25.0; // 5s→0, 30s→1
  }

  /// 稳定性评分（0.0 - 1.0）
  ///
  /// 基于历史带宽稳定性，稳定性高时更信任预测结果。
  double _computeStabilityScore() {
    if (_latestPrediction != null) {
      return _latestPrediction!.stability;
    }
    // 无预测数据时默认中等稳定性
    return 0.5;
  }

  /// 将综合评分映射到画质等级
  QualityLevel _scoreToQuality(double score) {
    if (score < 0.15) return QualityLevel.low;
    if (score < 0.35) return QualityLevel.medium;
    if (score < 0.60) return QualityLevel.high;
    return QualityLevel.ultra;
  }

  void _switchQuality(QualityLevel newQuality, String reason) {
    if (newQuality == _currentQuality) return;
    _logger.i('ABR 画质切换: ${_currentQuality.name} -> ${newQuality.name}, 原因: $reason');
    _currentQuality = newQuality;
    _lastSwitchTime = DateTime.now();
    _highBandwidthStart = null;
    onQualityChanged?.call(newQuality);
  }

  String get networkQualityDescription {
    if (_currentBandwidthKbps <= 0) return '未知';
    if (_currentBandwidthKbps < 800) return '弱网';
    if (_currentBandwidthKbps < 2500) return '一般';
    if (_currentBandwidthKbps < 5000) return '良好';
    return '优秀';
  }

  Future<void> saveQualityPreference(QualityLevel level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_quality', level.name);
  }

  Future<QualityLevel> loadQualityPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('preferred_quality');
    if (name == null) return QualityLevel.medium;
    return QualityLevel.values.firstWhere(
      (e) => e.name == name,
      orElse: () => QualityLevel.medium,
    );
  }
}
