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

  /// 使用习惯数据开关：观看时长、操作频次等
  final bool usageDataEnabled;

  /// 仅 WiFi 下上报
  final bool wifiOnlyUpload;

  /// 是否已完成首次授权弹窗
  final bool hasShownConsentDialog;

  const PrivacyPreferences({
    this.metricsEnabled = false,
    this.performanceDataEnabled = true,
    this.usageDataEnabled = true,
    this.wifiOnlyUpload = true,
    this.hasShownConsentDialog = false,
  });

  PrivacyPreferences copyWith({
    bool? metricsEnabled,
    bool? performanceDataEnabled,
    bool? usageDataEnabled,
    bool? wifiOnlyUpload,
    bool? hasShownConsentDialog,
  }) {
    return PrivacyPreferences(
      metricsEnabled: metricsEnabled ?? this.metricsEnabled,
      performanceDataEnabled: performanceDataEnabled ?? this.performanceDataEnabled,
      usageDataEnabled: usageDataEnabled ?? this.usageDataEnabled,
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

  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  // SharedPreferences 键名
  static const _keyMetricsEnabled = 'privacy_metrics_enabled';
  static const _keyPerformanceData = 'privacy_performance_data';
  static const _keyUsageData = 'privacy_usage_data';
  static const _keyWifiOnly = 'privacy_wifi_only';
  static const _keyConsentShown = 'privacy_consent_shown';

  /// 当前偏好缓存
  PrivacyPreferences _prefs = const PrivacyPreferences();

  /// 当前偏好
  PrivacyPreferences get preferences => _prefs;

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

  /// 是否允许采集使用习惯数据
  bool get canCollectUsageData =>
      _prefs.metricsEnabled && _prefs.usageDataEnabled;

  /// 是否需要显示首次授权弹窗
  bool get shouldShowConsentDialog => !_prefs.hasShownConsentDialog;

  /// 初始化 — 从 SharedPreferences 加载偏好
  Future<void> initialize() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _prefs = PrivacyPreferences(
        metricsEnabled: sp.getBool(_keyMetricsEnabled) ?? false,
        performanceDataEnabled: sp.getBool(_keyPerformanceData) ?? true,
        usageDataEnabled: sp.getBool(_keyUsageData) ?? true,
        wifiOnlyUpload: sp.getBool(_keyWifiOnly) ?? true,
        hasShownConsentDialog: sp.getBool(_keyConsentShown) ?? false,
      );
      _logger.i('隐私管理服务初始化完成，数据分享: ${_prefs.metricsEnabled}');
    } catch (e) {
      _logger.e('隐私管理服务初始化失败: $e');
    }
  }

  /// 更新总开关
  Future<void> setMetricsEnabled(bool enabled) async {
    _prefs = _prefs.copyWith(metricsEnabled: enabled);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyMetricsEnabled, enabled);
    _logger.i('数据分享总开关: $enabled');
  }

  /// 更新性能数据开关
  Future<void> setPerformanceDataEnabled(bool enabled) async {
    _prefs = _prefs.copyWith(performanceDataEnabled: enabled);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyPerformanceData, enabled);
  }

  /// 更新使用习惯数据开关
  Future<void> setUsageDataEnabled(bool enabled) async {
    _prefs = _prefs.copyWith(usageDataEnabled: enabled);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyUsageData, enabled);
  }

  /// 更新仅WiFi上报开关
  Future<void> setWifiOnlyUpload(bool wifiOnly) async {
    _prefs = _prefs.copyWith(wifiOnlyUpload: wifiOnly);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyWifiOnly, wifiOnly);
  }

  /// 标记首次授权弹窗已显示
  Future<void> markConsentDialogShown() async {
    _prefs = _prefs.copyWith(hasShownConsentDialog: true);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyConsentShown, true);
  }

  /// 用户同意数据分享（首次授权弹窗点击"同意"）
  Future<void> grantConsent() async {
    _prefs = _prefs.copyWith(
      metricsEnabled: true,
      hasShownConsentDialog: true,
    );
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyMetricsEnabled, true);
    await sp.setBool(_keyConsentShown, true);
    _logger.i('用户已同意数据分享');
  }

  /// 用户拒绝数据分享（首次授权弹窗点击"暂不开启"）
  Future<void> denyConsent() async {
    _prefs = _prefs.copyWith(
      metricsEnabled: false,
      hasShownConsentDialog: true,
    );
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyMetricsEnabled, false);
    await sp.setBool(_keyConsentShown, true);
    _logger.i('用户拒绝数据分享');
  }

  /// 重置所有隐私设置（调试用）
  Future<void> reset() async {
    _prefs = const PrivacyPreferences();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyMetricsEnabled);
    await sp.remove(_keyPerformanceData);
    await sp.remove(_keyUsageData);
    await sp.remove(_keyWifiOnly);
    await sp.remove(_keyConsentShown);
  }
}
