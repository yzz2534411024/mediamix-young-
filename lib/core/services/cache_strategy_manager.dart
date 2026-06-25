import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

// ============================================================
// 缓存优先级枚举
// ============================================================

/// 缓存优先级
///
/// 用于缓存淘汰排序，高优先级条目不容易被淘汰
enum CachePriority {
  /// 高优先级：用户偏好类型 / 高重播频率视频
  high,

  /// 普通优先级：默认
  normal,

  /// 低优先级：预加载但未被用户观看的内容
  low,
}

// ============================================================
// 观看习惯快照
// ============================================================

/// 用户观看习惯快照数据
class ViewingHabitSnapshot {
  /// 当前是否处于高频观看时段
  final bool isPeakHour;

  /// 当前时段的小时级别观看频率 (0.0~1.0)
  final double currentHourFrequency;

  /// 用户偏好的视频类型列表（按频率降序）
  final List<String> preferredCategories;

  /// 高重播频率的 videoId 集合
  final Set<String> highReplayVideoIds;

  /// 预测的接下来可能观看的类型
  final List<String> predictedCategories;

  const ViewingHabitSnapshot({
    required this.isPeakHour,
    required this.currentHourFrequency,
    required this.preferredCategories,
    required this.highReplayVideoIds,
    required this.predictedCategories,
  });
}

// ============================================================
// 缓存策略建议
// ============================================================

/// 缓存策略建议数据类
class CacheStrategySuggestion {
  /// TTL 倍数（1.0 = 默认，>1.0 = 延长，<1.0 = 缩短）
  final double ttlMultiplier;

  /// 容量倍数（1.0 = 默认，>1.0 = 扩大，<1.0 = 缩小）
  final double capacityMultiplier;

  /// 缓存优先级
  final CachePriority priority;

  const CacheStrategySuggestion({
    required this.ttlMultiplier,
    required this.capacityMultiplier,
    required this.priority,
  });

  /// 默认策略
  static const defaultSuggestion = CacheStrategySuggestion(
    ttlMultiplier: 1.0,
    capacityMultiplier: 1.0,
    priority: CachePriority.normal,
  );
}

// ============================================================
// 缓存策略管理器
// ============================================================

/// 智能缓存策略管理器
///
/// 基于用户观看习惯（观看时段、偏好类型、重播频率）动态调整缓存策略。
/// 独立于 [VideoCacheService]，不修改其内部逻辑，仅提供策略建议。
///
/// 数据来源：通过 [recordViewing] 记录每次观看行为，
/// 使用 SharedPreferences 轻量级持久化。
class CacheStrategyManager {
  static CacheStrategyManager? _instance;

  static CacheStrategyManager get instance =>
      _instance ??= CacheStrategyManager._();

  CacheStrategyManager._();

  final Logger _logger = Logger(printer: SimplePrinter());

  // ----------------------------------------------------------
  // SharedPreferences 键名
  // ----------------------------------------------------------
  static const String _prefix = 'cache_strategy_';
  static const String _keyHourHistogram = '${_prefix}hour_histogram';
  static const String _keyCategoryCounts = '${_prefix}category_counts';
  static const String _keyReplayCounts = '${_prefix}replay_counts';
  static const String _keyLastUpdated = '${_prefix}last_updated';

  // ----------------------------------------------------------
  // 阈值配置
  // ----------------------------------------------------------

  /// 高频时段阈值：该小时观看次数 >= 总次数 * 此比例 视为高频
  static const double _peakHourRatioThreshold = 0.06;

  /// 高重播频率阈值：同一视频观看次数 >= 此值视为高重播
  static const int _highReplayThreshold = 3;

  /// 偏好类型阈值：该类型观看次数 >= 总次数 * 此比例 视为偏好
  static const double _preferenceRatioThreshold = 0.15;

  /// 最大追踪的视频数量（防止 SharedPreferences 过大）
  static const int _maxTrackedVideos = 200;

  /// 最大追踪的类型数量
  static const int _maxTrackedCategories = 30;

  // ----------------------------------------------------------
  // 内存中的习惯数据
  // ----------------------------------------------------------

  /// 小时级别观看直方图（0~23 → 观看次数）
  final Map<int, int> _hourHistogram = {};

  /// 类型观看次数（category → count）
  final Map<String, int> _categoryCounts = {};

  /// 视频重播次数（videoId → count）
  final Map<String, int> _replayCounts = {};

  /// 总观看次数（用于计算比例）
  int _totalViewCount = 0;

  /// 是否已初始化
  bool _initialized = false;

  /// SharedPreferences 实例（可注入以便测试）
  SharedPreferences? _prefs;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  // ===========================================================
  // 初始化
  // ===========================================================

  /// 初始化，从 SharedPreferences 加载历史数据
  Future<void> initialize({SharedPreferences? prefs}) async {
    if (_initialized) return;

    try {
      _prefs = prefs ?? await SharedPreferences.getInstance();
      _loadFromPrefs();
      _initialized = true;
      _logger.i('缓存策略管理器初始化完成，'
          '追踪视频: ${_replayCounts.length}, '
          '类型: ${_categoryCounts.length}, '
          '总观看: $_totalViewCount');
    } catch (e) {
      _logger.e('缓存策略管理器初始化失败: $e');
      _initialized = true; // 允许降级运行
    }
  }

  // ===========================================================
  // 观看习惯追踪
  // ===========================================================

  /// 记录一次观看行为
  ///
  /// [videoId] 视频唯一标识
  /// [category] 视频类型/分类（如 "电影"、"电视剧"、"综艺" 等）
  /// [hour] 观看时段（小时级别，0~23），默认使用当前时间
  void recordViewing(String videoId, {String? category, int? hour}) {
    final h = hour ?? DateTime.now().hour;

    // 更新小时直方图
    _hourHistogram[h] = (_hourHistogram[h] ?? 0) + 1;

    // 更新类型计数
    if (category != null && category.isNotEmpty) {
      _categoryCounts[category] = (_categoryCounts[category] ?? 0) + 1;
      // 限制类型数量
      _trimCategoryCounts();
    }

    // 更新重播计数
    _replayCounts[videoId] = (_replayCounts[videoId] ?? 0) + 1;
    // 限制视频数量
    _trimReplayCounts();

    _totalViewCount++;

    // 异步持久化
    _saveToPrefs();

    _logger.d('记录观看: videoId=$videoId, category=$category, hour=$h, '
        '总观看=$_totalViewCount');
  }

  /// 获取当前观看习惯快照
  ViewingHabitSnapshot getSnapshot() {
    final currentHour = DateTime.now().hour;
    final currentHourFreq = _getCurrentHourFrequency(currentHour);
    final isPeak = _isPeakHour(currentHour);
    final preferred = _getPreferredCategories();
    final highReplay = _getHighReplayVideoIds();
    final predicted = _predictCategories(currentHour);

    return ViewingHabitSnapshot(
      isPeakHour: isPeak,
      currentHourFrequency: currentHourFreq,
      preferredCategories: preferred,
      highReplayVideoIds: highReplay,
      predictedCategories: predicted,
    );
  }

  // ===========================================================
  // 动态策略建议
  // ===========================================================

  /// 获取指定视频的缓存策略建议
  ///
  /// 综合考虑：当前时段、视频类型、重播频率
  CacheStrategySuggestion getSuggestion(String videoId, {String? category}) {
    if (!_initialized || _totalViewCount == 0) {
      return CacheStrategySuggestion.defaultSuggestion;
    }

    final currentHour = DateTime.now().hour;
    final isPeak = _isPeakHour(currentHour);

    // TTL 倍数
    double ttlMultiplier = 1.0;
    if (isPeak) {
      ttlMultiplier *= 1.5; // 高频时段延长 TTL
    } else {
      ttlMultiplier *= 0.7; // 低频时段缩短 TTL
    }

    // 容量倍数
    double capacityMultiplier = 1.0;
    if (isPeak) {
      capacityMultiplier *= 1.3; // 高频时段扩大缓存
    } else {
      capacityMultiplier *= 0.8; // 低频时段缩小缓存
    }

    // 优先级
    CachePriority priority = CachePriority.normal;

    // 高重播频率 → 高优先级 + 延长 TTL
    final replayCount = _replayCounts[videoId] ?? 0;
    if (replayCount >= _highReplayThreshold) {
      priority = CachePriority.high;
      ttlMultiplier *= 2.0;
    }

    // 用户偏好类型 → 高优先级
    if (category != null && _isPreferredCategory(category)) {
      if (priority != CachePriority.high) {
        priority = CachePriority.high;
      }
      ttlMultiplier *= 1.3;
      capacityMultiplier *= 1.2;
    }

    return CacheStrategySuggestion(
      ttlMultiplier: ttlMultiplier.clamp(0.3, 5.0),
      capacityMultiplier: capacityMultiplier.clamp(0.3, 3.0),
      priority: priority,
    );
  }

  /// 获取当前时段的容量倍数
  double getCapacityMultiplier() {
    if (!_initialized || _totalViewCount == 0) return 1.0;
    final currentHour = DateTime.now().hour;
    if (_isPeakHour(currentHour)) return 1.3;
    return 0.8;
  }

  /// 获取指定视频的动态 TTL（秒）
  ///
  /// [baseTtl] 基础 TTL（秒）
  int getDynamicTtl(String videoId, {String? category, int baseTtl = 604800}) {
    final suggestion = getSuggestion(videoId, category: category);
    return (baseTtl * suggestion.ttlMultiplier).round();
  }

  /// 获取指定视频的缓存优先级
  CachePriority getPriority(String videoId, {String? category}) {
    return getSuggestion(videoId, category: category).priority;
  }

  // ===========================================================
  // 预测性预热
  // ===========================================================

  /// 预测并预热缓存策略
  ///
  /// 根据当前时段和用户历史，预测接下来可能观看的内容类型，
  /// 返回应提升缓存优先级的类型列表。
  /// 此方法是轻量的，不做实际网络请求，仅返回策略建议。
  ///
  /// 返回值为预测的优先类型列表（按优先级降序），
  /// 调用方可据此调整对应类型视频的缓存参数。
  List<String> predictAndPreheat() {
    if (!_initialized || _totalViewCount == 0) {
      _logger.d('predictAndPreheat: 无历史数据，返回空');
      return [];
    }

    final currentHour = DateTime.now().hour;
    final predicted = _predictCategories(currentHour);

    _logger.i('predictAndPreheat: 当前时段=$currentHour, '
        '预测类型=$predicted');

    return predicted;
  }

  /// 获取预测类型对应的缓存策略建议
  ///
  /// 对于预测类型中的视频，返回提升后的策略建议
  CacheStrategySuggestion getPreheatSuggestion(String category) {
    if (!_isPreferredCategory(category) &&
        !predictAndPreheat().contains(category)) {
      return CacheStrategySuggestion.defaultSuggestion;
    }

    return const CacheStrategySuggestion(
      ttlMultiplier: 1.5,
      capacityMultiplier: 1.2,
      priority: CachePriority.high,
    );
  }

  // ===========================================================
  // 内部方法 — 时段分析
  // ===========================================================

  /// 判断指定小时是否为高频观看时段
  bool _isPeakHour(int hour) {
    if (_totalViewCount == 0) return false;
    final count = _hourHistogram[hour] ?? 0;
    final ratio = count / _totalViewCount;
    return ratio >= _peakHourRatioThreshold;
  }

  /// 获取指定小时的观看频率 (0.0~1.0)
  double _getCurrentHourFrequency(int hour) {
    if (_totalViewCount == 0) return 0.0;
    final count = _hourHistogram[hour] ?? 0;
    return (count / _totalViewCount).clamp(0.0, 1.0);
  }

  /// 基于当前时段预测可能观看的类型
  ///
  /// 逻辑：找到该时段历史上最常观看的类型
  List<String> _predictCategories(int hour) {
    // 找到该时段及相邻时段的观看分布
    // 简化实现：使用当前时段的类型分布
    final hourCount = _hourHistogram[hour] ?? 0;
    if (hourCount == 0 || _totalViewCount == 0) {
      // 无时段数据时，使用全局偏好
      return _getPreferredCategories();
    }

    // 按时段频率比例排序类型
    // 简化：直接返回全局偏好类型（因为未追踪 hour×category 交叉数据）
    // 但可以根据时段活跃度加权
    final preferred = _getPreferredCategories();
    if (preferred.isEmpty) return [];

    // 如果当前时段活跃度高于平均，返回更多类型
    final avgHourFreq = _totalViewCount / 24.0;
    final currentFreq = _hourHistogram[hour] ?? 0;

    if (currentFreq > avgHourFreq * 1.5) {
      // 高频时段：返回前3个偏好类型
      return preferred.take(3).toList();
    } else if (currentFreq > avgHourFreq) {
      // 中频时段：返回前2个
      return preferred.take(2).toList();
    } else {
      // 低频时段：返回前1个
      return preferred.take(1).toList();
    }
  }

  // ===========================================================
  // 内部方法 — 类型偏好分析
  // ===========================================================

  /// 获取偏好类型列表（按频率降序）
  List<String> _getPreferredCategories() {
    if (_totalViewCount == 0 || _categoryCounts.isEmpty) return [];

    final entries = _categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries
        .where((e) => e.value / _totalViewCount >= _preferenceRatioThreshold)
        .map((e) => e.key)
        .toList();
  }

  /// 判断指定类型是否为用户偏好类型
  bool _isPreferredCategory(String category) {
    if (_totalViewCount == 0) return false;
    final count = _categoryCounts[category] ?? 0;
    return count / _totalViewCount >= _preferenceRatioThreshold;
  }

  /// 限制类型追踪数量
  void _trimCategoryCounts() {
    if (_categoryCounts.length <= _maxTrackedCategories) return;
    final entries = _categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _categoryCounts.clear();
    for (final e in entries.take(_maxTrackedCategories)) {
      _categoryCounts[e.key] = e.value;
    }
  }

  // ===========================================================
  // 内部方法 — 重播频率分析
  // ===========================================================

  /// 获取高重播频率的 videoId 集合
  Set<String> _getHighReplayVideoIds() {
    return _replayCounts.entries
        .where((e) => e.value >= _highReplayThreshold)
        .map((e) => e.key)
        .toSet();
  }

  /// 限制视频追踪数量（保留重播次数最高的）
  void _trimReplayCounts() {
    if (_replayCounts.length <= _maxTrackedVideos) return;
    final entries = _replayCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _replayCounts.clear();
    for (final e in entries.take(_maxTrackedVideos)) {
      _replayCounts[e.key] = e.value;
    }
  }

  // ===========================================================
  // 持久化 — SharedPreferences
  // ===========================================================

  /// 从 SharedPreferences 加载数据
  void _loadFromPrefs() {
    if (_prefs == null) return;

    try {
      // 加载小时直方图
      final hourJson = _prefs!.getString(_keyHourHistogram);
      if (hourJson != null && hourJson.isNotEmpty) {
        final decoded = jsonDecode(hourJson) as Map<String, dynamic>;
        _hourHistogram.clear();
        for (final e in decoded.entries) {
          _hourHistogram[int.parse(e.key)] = e.value as int;
        }
      }

      // 加载类型计数
      final catJson = _prefs!.getString(_keyCategoryCounts);
      if (catJson != null && catJson.isNotEmpty) {
        final decoded = jsonDecode(catJson) as Map<String, dynamic>;
        _categoryCounts.clear();
        for (final e in decoded.entries) {
          _categoryCounts[e.key] = e.value as int;
        }
      }

      // 加载重播计数
      final replayJson = _prefs!.getString(_keyReplayCounts);
      if (replayJson != null && replayJson.isNotEmpty) {
        final decoded = jsonDecode(replayJson) as Map<String, dynamic>;
        _replayCounts.clear();
        for (final e in decoded.entries) {
          _replayCounts[e.key] = e.value as int;
        }
      }

      // 计算总观看次数
      _totalViewCount = 0;
      for (final count in _hourHistogram.values) {
        _totalViewCount += count;
      }
    } catch (e) {
      _logger.w('从 SharedPreferences 加载习惯数据失败: $e');
    }
  }

  /// 保存数据到 SharedPreferences
  Future<void> _saveToPrefs() async {
    if (_prefs == null) return;

    try {
      // 保存小时直方图
      await _prefs!.setString(
        _keyHourHistogram,
        jsonEncode(_hourHistogram.map((k, v) => MapEntry(k.toString(), v))),
      );

      // 保存类型计数
      await _prefs!.setString(
        _keyCategoryCounts,
        jsonEncode(_categoryCounts),
      );

      // 保存重播计数
      await _prefs!.setString(
        _keyReplayCounts,
        jsonEncode(_replayCounts),
      );

      // 记录最后更新时间
      await _prefs!.setString(
        _keyLastUpdated,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      _logger.w('保存习惯数据到 SharedPreferences 失败: $e');
    }
  }

  // ===========================================================
  // 测试辅助
  // ===========================================================

  /// 重置所有数据（仅用于测试）
  void resetForTesting() {
    _hourHistogram.clear();
    _categoryCounts.clear();
    _replayCounts.clear();
    _totalViewCount = 0;
    _initialized = false;
    _prefs = null;
  }

  /// 注入 SharedPreferences 实例（仅用于测试）
  void setPrefsForTesting(SharedPreferences prefs) {
    _prefs = prefs;
  }

  /// 获取总观看次数（仅用于测试/调试）
  int get totalViewCount => _totalViewCount;

  /// 获取小时直方图副本（仅用于测试/调试）
  Map<int, int> get hourHistogram => Map.unmodifiable(_hourHistogram);

  /// 获取类型计数字副本（仅用于测试/调试）
  Map<String, int> get categoryCounts => Map.unmodifiable(_categoryCounts);

  /// 获取重播计数字副本（仅用于测试/调试）
  Map<String, int> get replayCounts => Map.unmodifiable(_replayCounts);

  /// 释放资源
  void dispose() {
    _instance = null;
  }
}
