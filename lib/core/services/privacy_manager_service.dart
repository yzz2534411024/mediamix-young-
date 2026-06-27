import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

// ============================================================================
// 隐私管理服务 — 用户数据采集与回传的隐私控制中心
// ============================================================================

/// 隐私偏好配置
class PrivacyPreferences {
  /// 总开关：是否允许采集和上报数据（默认 false，需用户主动开启）
  final bool metricsEnabled;

  /// 性能数据开关：首屏时间、卡顿率、Seek延迟等
  final bool performanceDataEnabled;

  /// 仅 WiFi 下上报
  final bool wifiOnlyUpload;

  /// 是否已完成首次授权弹窗
  final bool hasShownConsentDialog;

  const PrivacyPreferences({
    this.metricsEnabled = false,
    this.performanceDataEnabled = true,
    this.wifiOnlyUpload = true,
    this.hasShownConsentDialog = false,
  });

  PrivacyPreferences copyWith({
    bool? metricsEnabled,
    bool? performanceDataEnabled,
    bool? wifiOnlyUpload,
    bool? hasShownConsentDialog,
  }) {
    return PrivacyPreferences(
      metricsEnabled: metricsEnabled ?? this.metricsEnabled,
      performanceDataEnabled: performanceDataEnabled ?? this.performanceDataEnabled,
      wifiOnlyUpload: wifiOnlyUpload ?? this.wifiOnlyUpload,
      hasShownConsentDialog: hasShownConsentDialog ?? this.hasShownConsentDialog,
    );
  }
}

/// 隐私管理服务（单例）
///
/// 职责：
///   - 管理用户隐私偏好（SharedPreferences 持久化）
///   - 判断是否允许采集/上报数据
///   - 首次授权弹窗状态管理
class PrivacyManagerService {
  static PrivacyManagerService? _instance;
  static PrivacyManagerService get instance => _instance ??= PrivacyManagerService._();

  PrivacyManagerService._();

  final Logger _logger = Logger(printer: SimplePrinter());

  // SharedPreferences 键名
  static const _keyMetricsEnabled = 'privacy_metrics_enabled';
  static const _keyPerformanceData = 'privacy_performance_data';
  static const _keyWifiOnly = 'privacy_wifi_only';
  static const _keyConsentShown = 'privacy_consent_shown';

  /// 当前偏好缓存
  PrivacyPreferences _prefs = const PrivacyPreferences();

  /// 偏好变化通知流
  final _preferencesController =
      StreamController<PrivacyPreferences>.broadcast();

  /// 当前偏好
  PrivacyPreferences get preferences => _prefs;

  /// 偏好变化流（供 Provider 监听）
  Stream<PrivacyPreferences> get preferencesStream =>
      _preferencesController.stream;

  /// 是否允许采集数据
  bool get canCollectMetrics => _prefs.metricsEnabled;

  /// 是否允许上报数据（总开关开启 + 非WiFi时检查WiFi限制）
  bool canUploadData({required bool isOnWifi}) {
    if (!_prefs.metricsEnabled) return false;
    if (_prefs.wifiOnlyUpload && !isOnWifi) return false;
    return true;
  }

  /// 是否允许采集性能数据
  bool get canCollectPerformanceData =>
      _prefs.metricsEnabled && _prefs.performanceDataEnabled;

  /// 是否需要显示首次授权弹窗
  bool get shouldShowConsentDialog => !_prefs.hasShownConsentDialog;

  /// 初始化 — 从 SharedPreferences 加载偏好
  Future<void> initialize() async {
    try {
      final sp = await _sp;
      _prefs = PrivacyPreferences(
        metricsEnabled: sp.getBool(_keyMetricsEnabled) ?? false,
        performanceDataEnabled: sp.getBool(_keyPerformanceData) ?? true,
        wifiOnlyUpload: sp.getBool(_keyWifiOnly) ?? true,
        hasShownConsentDialog: sp.getBool(_keyConsentShown) ?? false,
      );
      _notify();
      _logger.i('隐私管理服务初始化完成，数据分享: ${_prefs.metricsEnabled}');
    } catch (e) {
      _logger.e('隐私管理服务初始化失败: $e');
    }
  }

  /// 通知监听者偏好已变更
  void _notify() {
    _preferencesController.add(_prefs);
  }

  /// 获取缓存的 SharedPreferences 实例
  SharedPreferences? _spInstance;
  Future<SharedPreferences> get _sp async =>
      _spInstance ??= await SharedPreferences.getInstance();

  /// 更新总开关
  Future<void> setMetricsEnabled(bool enabled) async {
    _prefs = _prefs.copyWith(metricsEnabled: enabled);
    (await _sp).setBool(_keyMetricsEnabled, enabled);
    _notify();
    _logger.i('数据分享总开关: $enabled');
  }

  /// 更新性能数据开关
  Future<void> setPerformanceDataEnabled(bool enabled) async {
    _prefs = _prefs.copyWith(performanceDataEnabled: enabled);
    (await _sp).setBool(_keyPerformanceData, enabled);
    _notify();
  }

  /// 更新仅WiFi上报开关
  Future<void> setWifiOnlyUpload(bool wifiOnly) async {
    _prefs = _prefs.copyWith(wifiOnlyUpload: wifiOnly);
    (await _sp).setBool(_keyWifiOnly, wifiOnly);
    _notify();
  }

  /// 标记首次授权弹窗已显示
  Future<void> markConsentDialogShown() async {
    _prefs = _prefs.copyWith(hasShownConsentDialog: true);
    (await _sp).setBool(_keyConsentShown, true);
    _notify();
  }

  /// 用户同意数据分享（首次授权弹窗点击"同意"）
  Future<void> grantConsent() async {
    _prefs = _prefs.copyWith(
      metricsEnabled: true,
      hasShownConsentDialog: true,
    );
    final sp = await _sp;
    await sp.setBool(_keyMetricsEnabled, true);
    await sp.setBool(_keyConsentShown, true);
    _notify();
    _logger.i('用户已同意数据分享');
  }

  /// 用户拒绝数据分享（首次授权弹窗点击"暂不开启"）
  Future<void> denyConsent() async {
    _prefs = _prefs.copyWith(
      metricsEnabled: false,
      hasShownConsentDialog: true,
    );
    final sp = await _sp;
    await sp.setBool(_keyMetricsEnabled, false);
    await sp.setBool(_keyConsentShown, true);
    _notify();
    _logger.i('用户拒绝数据分享');
  }

  /// 释放资源
  void dispose() {
    _preferencesController.close();
  }

  /// 重置所有隐私设置（调试用）
  Future<void> reset() async {
    _prefs = const PrivacyPreferences();
    final sp = await _sp;
    await sp.remove(_keyMetricsEnabled);
    await sp.remove(_keyPerformanceData);
    await sp.remove(_keyWifiOnly);
    await sp.remove(_keyConsentShown);
    _notify();
  }
}
