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
/// 由于当前应用没有多码率流，实现为网络质量指示器 + 画质偏好管理
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

  QualityLevel _currentQuality = QualityLevel.medium;

  void Function(QualityLevel level)? onQualityChanged;

  ABRController({
    this.onQualityChanged,
    Duration? upgradeDelay,
    Duration? minSwitchInterval,
  })  : _upgradeDelay = upgradeDelay ?? const Duration(seconds: 5),
        _minSwitchInterval = minSwitchInterval ?? const Duration(seconds: 10);

  QualityLevel get currentQuality => _currentQuality;

  void updateBandwidth(double kbps) {
    _currentBandwidthKbps = kbps;
    _evaluate();
  }

  void updateBuffer(Duration buffer) {
    _currentBuffer = buffer;
    _evaluate();
  }

  void _evaluate() {
    final now = DateTime.now();

    if (_lastSwitchTime != null &&
        now.difference(_lastSwitchTime!) < _minSwitchInterval) {
      return;
    }

    // 降级：缓冲 < 5s
    if (_currentBuffer < _downgradeBufferThreshold &&
        _currentQuality != QualityLevel.low) {
      _switchQuality(QualityLevel.low, '缓冲不足，降级画质');
      return;
    }

    // 升级：缓冲 > 30s 且带宽充足
    if (_currentBuffer > _upgradeBufferThreshold) {
      final target = _qualityForBandwidth(_currentBandwidthKbps);
      if (target.index > _currentQuality.index) {
        if (_highBandwidthStart == null) {
          _highBandwidthStart = now;
        } else if (now.difference(_highBandwidthStart!) >= _upgradeDelay) {
          _switchQuality(target, '带宽充足，升级画质');
        }
      } else {
        _highBandwidthStart = null;
      }
    } else {
      _highBandwidthStart = null;
    }
  }

  QualityLevel _qualityForBandwidth(double kbps) {
    if (kbps <= 0) return QualityLevel.low;
    if (kbps < 800) return QualityLevel.low;
    if (kbps < 2500) return QualityLevel.medium;
    if (kbps < 5000) return QualityLevel.high;
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
