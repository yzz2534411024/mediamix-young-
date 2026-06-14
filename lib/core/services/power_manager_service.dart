import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

/// 电源模式枚举
enum PowerMode {
  /// 最高性能 - 60fps, 高分辨率, 积极缓冲
  fullPerformance,

  /// 平衡模式 - 30fps, 中等分辨率, 适中缓冲
  balanced,

  /// 省电模式 - 24fps, 低分辨率, 减少预加载, 关闭弹幕
  powerSaving,
}

/// 电池信息
class BatteryInfo {
  /// 电池电量 (0-100)
  final int level;

  /// 是否正在充电
  final bool isCharging;

  /// 是否低电量 (< 20%)
  bool get isLowPower => level < 20;

  const BatteryInfo({
    required this.level,
    required this.isCharging,
  });

  /// 默认值（无法获取电池信息时的回退）
  static const BatteryInfo fallback = BatteryInfo(level: 100, isCharging: true);

  @override
  String toString() => 'BatteryInfo(level: $level, isCharging: $isCharging, isLowPower: $isLowPower)';
}

/// 电源模式配置
class PowerModeConfig {
  /// 目标帧率
  final int targetFps;

  /// 最大分辨率
  final String maxResolution;

  /// 缓冲策略
  final String bufferSizeLevel;

  /// 是否启用预加载
  final bool enablePreload;

  /// 是否启用弹幕
  final bool enableDanmaku;

  /// 是否启用后台播放
  final bool enableBackgroundPlay;

  const PowerModeConfig({
    required this.targetFps,
    required this.maxResolution,
    required this.bufferSizeLevel,
    required this.enablePreload,
    required this.enableDanmaku,
    required this.enableBackgroundPlay,
  });

  @override
  String toString() =>
      'PowerModeConfig(fps: $targetFps, resolution: $maxResolution, '
      'buffer: $bufferSizeLevel, preload: $enablePreload, '
      'danmaku: $enableDanmaku, backgroundPlay: $enableBackgroundPlay)';
}

/// 各电源模式对应的配置表
const Map<PowerMode, PowerModeConfig> _modeConfigs = {
  PowerMode.fullPerformance: PowerModeConfig(
    targetFps: 60,
    maxResolution: '1080p',
    bufferSizeLevel: 'aggressive',
    enablePreload: true,
    enableDanmaku: true,
    enableBackgroundPlay: true,
  ),
  PowerMode.balanced: PowerModeConfig(
    targetFps: 30,
    maxResolution: '720p',
    bufferSizeLevel: 'normal',
    enablePreload: true,
    enableDanmaku: true,
    enableBackgroundPlay: true,
  ),
  PowerMode.powerSaving: PowerModeConfig(
    targetFps: 24,
    maxResolution: '480p',
    bufferSizeLevel: 'minimal',
    enablePreload: false,
    enableDanmaku: false,
    enableBackgroundPlay: false,
  ),
};

/// 电源管理服务（单例）
///
/// 根据电池状态自动切换电源模式，也支持用户手动覆盖。
/// 提供各模式下的播放配置（帧率、分辨率、缓冲策略等）。
class PowerManagerService {
  PowerManagerService._();

  static final PowerManagerService _instance = PowerManagerService._();

  /// 获取单例实例
  static PowerManagerService get instance => _instance;

  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  /// 电池信息 MethodChannel
  static const MethodChannel _batteryChannel =
      MethodChannel('com.mediamix.app/battery');

  /// SharedPreferences 中存储用户手动覆盖的 key
  static const String _prefKeyOverride = 'power_mode_override';

  /// 电池轮询间隔（30秒）
  static const Duration _batteryPollInterval = Duration(seconds: 30);

  PowerMode _currentMode = PowerMode.balanced;
  BatteryInfo _batteryInfo = BatteryInfo.fallback;
  bool _isInitialized = false;
  bool _hasUserOverride = false;

  /// 模式变更控制器
  final StreamController<PowerMode> _modeController =
      StreamController<PowerMode>.broadcast();

  /// 电池信息变更控制器
  final StreamController<BatteryInfo> _batteryController =
      StreamController<BatteryInfo>.broadcast();

  /// 电池轮询定时器
  Timer? _batteryPollTimer;

  /// 当前电源模式
  PowerMode get currentMode => _currentMode;

  /// 当前电池信息
  BatteryInfo get batteryInfo => _batteryInfo;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 是否存在用户手动覆盖
  bool get hasUserOverride => _hasUserOverride;

  /// 电源模式变更流
  Stream<PowerMode> get onModeChanged => _modeController.stream;

  /// 电池信息变更流
  Stream<BatteryInfo> get onBatteryChanged => _batteryController.stream;

  /// 初始化服务
  ///
  /// 检测初始电池状态，读取用户偏好，确定初始电源模式。
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 读取用户手动覆盖设置
      final prefs = await SharedPreferences.getInstance();
      final overrideValue = prefs.getString(_prefKeyOverride);
      if (overrideValue != null) {
        _hasUserOverride = true;
        _currentMode = _parseModeFromString(overrideValue);
        _logger.i('检测到用户手动覆盖模式: $_currentMode');
      }

      // 获取初始电池信息
      _batteryInfo = await getBatteryInfo();
      _logger.i('初始电池信息: $_batteryInfo');

      // 如果没有用户覆盖，则根据电池自动选择
      if (!_hasUserOverride) {
        autoSelectMode();
      }

      // 启动电池轮询
      _startBatteryPolling();

      _isInitialized = true;
      _logger.i('电源管理服务初始化完成，当前模式: $_currentMode');
    } catch (e) {
      _logger.e('电源管理服务初始化失败: $e');
      // 使用默认值继续运行
      _currentMode = PowerMode.balanced;
      _startBatteryPolling();
      _isInitialized = true;
    }
  }

  /// 获取当前电池信息
  ///
  /// 通过 MethodChannel 获取原生电池信息，失败时返回回退默认值。
  Future<BatteryInfo> getBatteryInfo() async {
    try {
      final result = await _batteryChannel.invokeMethod<Map>('getBatteryInfo');
      if (result != null) {
        return BatteryInfo(
          level: (result['level'] as num?)?.toInt() ?? 100,
          isCharging: result['isCharging'] as bool? ?? true,
        );
      }
    } on PlatformException catch (e) {
      _logger.w('获取电池信息失败（平台异常）: ${e.message}');
    } on MissingPluginException catch (e) {
      _logger.w('获取电池信息失败（插件未注册）: ${e.message}');
    } catch (e) {
      _logger.w('获取电池信息失败: $e');
    }

    // 回退默认值：满电且充电中，避免误触发省电模式
    return BatteryInfo.fallback;
  }

  /// 手动设置电源模式
  ///
  /// 设置后会持久化到 SharedPreferences，优先级高于自动选择。
  /// 传入 null 可清除手动覆盖，恢复自动选择。
  void setPowerMode(PowerMode? mode) async {
    if (mode != null) {
      _hasUserOverride = true;
      _applyMode(mode);

      // 持久化用户选择
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKeyOverride, mode.name);
        _logger.i('用户手动设置电源模式: $mode，已持久化');
      } catch (e) {
        _logger.e('持久化电源模式失败: $e');
      }
    } else {
      // 清除手动覆盖，恢复自动选择
      _hasUserOverride = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefKeyOverride);
        _logger.i('已清除电源模式手动覆盖，恢复自动选择');
      } catch (e) {
        _logger.e('清除电源模式偏好失败: $e');
      }
      autoSelectMode();
    }
  }

  /// 根据电池状态自动选择电源模式
  ///
  /// 自动选择逻辑：
  /// - 电量 > 50% 或正在充电 → fullPerformance
  /// - 电量 20%-50% → balanced
  /// - 电量 < 20% → powerSaving
  void autoSelectMode() {
    if (_hasUserOverride) {
      _logger.d('存在用户手动覆盖，跳过自动选择');
      return;
    }

    PowerMode targetMode;

    if (_batteryInfo.isCharging || _batteryInfo.level > 50) {
      targetMode = PowerMode.fullPerformance;
    } else if (_batteryInfo.level >= 20) {
      targetMode = PowerMode.balanced;
    } else {
      targetMode = PowerMode.powerSaving;
    }

    _applyMode(targetMode);
  }

  /// 获取当前电源模式的配置
  PowerModeConfig getConfig() => _modeConfigs[_currentMode]!;

  /// 应用新的电源模式
  void _applyMode(PowerMode newMode) {
    if (_currentMode == newMode) return;

    final oldMode = _currentMode;
    _currentMode = newMode;
    _logger.i('电源模式变更: $oldMode → $newMode');

    if (!_modeController.isClosed) {
      _modeController.add(newMode);
    }
  }

  /// 启动电池信息轮询
  void _startBatteryPolling() {
    _batteryPollTimer?.cancel();
    _batteryPollTimer = Timer.periodic(_batteryPollInterval, (_) async {
      final newInfo = await getBatteryInfo();
      if (newInfo.level != _batteryInfo.level ||
          newInfo.isCharging != _batteryInfo.isCharging) {
        _batteryInfo = newInfo;
        _logger.d('电池信息更新: $_batteryInfo');

        if (!_batteryController.isClosed) {
          _batteryController.add(newInfo);
        }

        // 电池状态变化时尝试自动选择
        autoSelectMode();
      }
    });
  }

  /// 从字符串解析 PowerMode
  PowerMode _parseModeFromString(String value) {
    return PowerMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => PowerMode.balanced,
    );
  }

  /// 释放资源
  void dispose() {
    _batteryPollTimer?.cancel();
    _batteryPollTimer = null;
    _modeController.close();
    _batteryController.close();
    _isInitialized = false;
    _logger.i('电源管理服务已释放');
  }
}
