import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:logger/logger.dart';
import '../utils/hash_utils.dart';
import 'cache_strategy_manager.dart';

// ============================================================
// 数据类与枚举
// ============================================================

/// 缓存策略枚举
///
/// 根据网络与存储状态动态切换缓存策略：
/// - normal: 常规模式
/// - aggressive: WiFi 下的激进预加载策略
/// - conservative: 移动网络下的保守策略
/// - emergency: 存储空间不足时的紧急策略
enum CachePolicy {
  normal,
  aggressive,
  conservative,
  emergency,
}

/// 缓存条目数据类
///
/// 记录每个缓存项的完整元信息，用于索引与淘汰决策
class CacheEntry {
  /// 缓存唯一标识
  final String cacheId;

  /// 视频ID
  final String videoId;

  /// 画质标签（如 720p / 1080p）
  final String quality;

  /// 缓存文件路径
  final String filePath;

  /// 文件大小（字节）
  int fileSize;

  /// 分段键列表（HLS/DASH 场景）
  List<String> segments;

  /// 命中次数
  int hitCount;

  /// 最后访问时间
  DateTime lastAccess;

  /// 创建时间
  final DateTime createdAt;

  /// 生存时间（秒），默认 7 天
  final int ttl;

  /// 优先级，数值越高越不容易被淘汰
  final int priority;

  /// 是否为完整视频缓存（非分段）
  bool isComplete;

  CacheEntry({
    required this.cacheId,
    required this.videoId,
    required this.quality,
    required this.filePath,
    this.fileSize = 0,
    List<String>? segments,
    this.hitCount = 0,
    DateTime? lastAccess,
    DateTime? createdAt,
    this.ttl = 604800,
    this.priority = 0,
    this.isComplete = true,
  })  : segments = segments ?? [],
        lastAccess = lastAccess ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  /// 是否已过期
  bool get isExpired {
    final expiresAt = createdAt.add(Duration(seconds: ttl));
    return DateTime.now().isAfter(expiresAt);
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'cacheId': cacheId,
        'videoId': videoId,
        'quality': quality,
        'filePath': filePath,
        'fileSize': fileSize,
        'segments': segments,
        'hitCount': hitCount,
        'lastAccess': lastAccess.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'ttl': ttl,
        'priority': priority,
        'isComplete': isComplete,
      };

  /// 从 JSON 反序列化
  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
        cacheId: json['cacheId'] as String,
        videoId: json['videoId'] as String,
        quality: json['quality'] as String,
        filePath: json['filePath'] as String,
        fileSize: json['fileSize'] as int? ?? 0,
        segments: (json['segments'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        hitCount: json['hitCount'] as int? ?? 0,
        lastAccess: json['lastAccess'] != null
            ? DateTime.parse(json['lastAccess'] as String)
            : DateTime.now(),
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        ttl: json['ttl'] as int? ?? 604800,
        priority: json['priority'] as int? ?? 0,
        isComplete: json['isComplete'] as bool? ?? true,
      );
}

/// 分段缓存查询结果
class SegmentCacheResult {
  /// 是否命中
  final bool hit;

  /// 分段数据（L2 内存命中时返回）
  final List<int>? data;

  /// 分段文件路径（L4 磁盘命中时返回）
  final String? path;

  SegmentCacheResult({
    required this.hit,
    this.data,
    this.path,
  });
}

/// 缓存统计数据
class CacheStats {
  /// 总缓存大小（字节）
  final int totalSize;

  /// 缓存条目数
  final int entryCount;

  /// 命中次数
  final int hitCount;

  /// 未命中次数
  final int missCount;

  /// 命中率 (0.0 ~ 1.0)
  final double hitRate;

  /// 磁盘使用百分比 (0.0 ~ 100.0)
  final double diskUsagePercent;

  CacheStats({
    required this.totalSize,
    required this.entryCount,
    required this.hitCount,
    required this.missCount,
    required this.hitRate,
    required this.diskUsagePercent,
  });

  @override
  String toString() =>
      'CacheStats(totalSize: ${(totalSize / 1024 / 1024).toStringAsFixed(1)}MB, '
      'entryCount: $entryCount, '
      'hitRate: ${(hitRate * 100).toStringAsFixed(1)}%, '
      'diskUsage: ${diskUsagePercent.toStringAsFixed(1)}%)';
}

// ============================================================
// 内存压力等级
// ============================================================

/// 内存压力等级
///
/// - normal: 正常，L1/L2 保持当前容量
/// - warning: 警告（>70%），L1 容量减半，L2 容量减半
/// - critical: 严重（>90%），清空 L1，L2 容量降至最低
enum MemoryPressureLevel {
  normal,
  warning,
  critical,
}

/// 内存使用信息
///
/// 返回 L1/L2 当前占用内存及内存压力等级
class MemoryUsageInfo {
  /// L1 帧缓存占用字节数
  final int l1Bytes;

  /// L2 流缓存占用字节数
  final int l2Bytes;

  /// 进程当前 RSS（常驻集大小）
  final int processRssBytes;

  /// 当前内存压力等级
  final MemoryPressureLevel pressureLevel;

  /// L1 当前最大条目数（动态调整）
  final int l1MaxEntries;

  /// L2 当前最大条目数（动态调整）
  final int l2MaxEntries;

  const MemoryUsageInfo({
    required this.l1Bytes,
    required this.l2Bytes,
    required this.processRssBytes,
    required this.pressureLevel,
    required this.l1MaxEntries,
    required this.l2MaxEntries,
  });

  @override
  String toString() =>
      'MemoryUsageInfo(L1: ${(l1Bytes / 1024).toStringAsFixed(1)}KB/$l1MaxEntries条, '
      'L2: ${(l2Bytes / 1024).toStringAsFixed(1)}KB/$l2MaxEntries条, '
      'RSS: ${(processRssBytes / 1024 / 1024).toStringAsFixed(1)}MB, '
      '压力: $pressureLevel)';
}

// ============================================================
// 内部缓存条目（L1 / L2 内存缓存）
// ============================================================

/// L1 内存缓存条目 — 解码帧缓冲
class _MemoryCacheEntry {
  /// 视频ID
  final String videoId;

  /// 画质
  final String quality;

  /// 帧数据缓冲
  final Map<String, dynamic> frameBuffer;

  /// 最后访问时间
  DateTime lastAccess;

  /// 命中次数
  int hitCount;

  /// 创建时间
  final DateTime createdAt;

  /// 估算内存占用（字节）
  final int estimatedBytes;

  _MemoryCacheEntry({
    required this.videoId,
    required this.quality,
    required this.frameBuffer,
    DateTime? lastAccess,
    DateTime? createdAt,
    int? estimatedBytes,
  })  : hitCount = 0,
        lastAccess = lastAccess ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        estimatedBytes = estimatedBytes ?? _estimateFrameBufferSize(frameBuffer);

  /// 是否已过期（基于 TTL）
  bool isExpired(Duration ttl) {
    return DateTime.now().difference(lastAccess) > ttl;
  }

  /// 估算帧缓冲大小
  static int _estimateFrameBufferSize(Map<String, dynamic> buffer) {
    // 粗略估算：遍历 buffer 中的值
    int size = 0;
    for (final value in buffer.values) {
      if (value is List<int>) {
        size += value.length;
      } else if (value is String) {
        size += value.length * 2;
      } else {
        size += 64; // 其他类型粗略估算
      }
    }
    return size > 0 ? size : 1024; // 至少 1KB
  }
}

/// L2 内存缓存条目 — 原始流数据
class _StreamCacheEntry {
  /// 视频ID
  final String videoId;

  /// 分段键
  final String segmentKey;

  /// 画质
  final String quality;

  /// 原始字节数据
  final List<int> data;

  /// 最后访问时间
  DateTime lastAccess;

  /// 命中次数
  int hitCount;

  /// 创建时间
  final DateTime createdAt;

  _StreamCacheEntry({
    required this.videoId,
    required this.segmentKey,
    required this.quality,
    required this.data,
    DateTime? lastAccess,
    DateTime? createdAt,
  })  : hitCount = 0,
        lastAccess = lastAccess ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  /// 是否已过期（基于 TTL）
  bool isExpired(Duration ttl) {
    return DateTime.now().difference(lastAccess) > ttl;
  }
}

// ============================================================
// 视频缓存服务（单例）
// ============================================================

/// 多级视频缓存服务
///
/// 缓存层级：
/// - L1: 解码帧缓冲内存缓存（_memoryCache）
/// - L2: 原始流数据内存缓存（_streamCache）
/// - L3: 完整视频文件磁盘缓存
/// - L4: 分段视频磁盘缓存（HLS/DASH segments）
///
/// 淘汰策略：LRU + 优先级，淘汰顺序：
///   过期条目 → 低优先级预加载 → LRU → 大文件
///
/// 保留策略：用户收藏、24h 内播放记录、热门视频
class VideoCacheService {
  static VideoCacheService? _instance;

  static VideoCacheService get instance => _instance ??= VideoCacheService._();

  VideoCacheService._();

  // ----------------------------------------------------------
  // L1 内存缓存 — 解码帧缓冲
  // ----------------------------------------------------------
  /// key: "${videoId}_${quality}"
  final Map<String, _MemoryCacheEntry> _memoryCache = {};

  /// L1 基础最大条目数（内存压力为 normal 时）
  static const int _l1BaseMaxEntries = 20;

  /// L2 基础最大条目数（内存压力为 normal 时）
  static const int _l2BaseMaxEntries = 50;

  /// L2 最低最大条目数（内存压力为 critical 时）
  static const int _l2MinEntries = 5;

  // ----------------------------------------------------------
  // L2 内存缓存 — 原始流数据
  // ----------------------------------------------------------
  /// key: "${videoId}_${segmentKey}_${quality}"
  final Map<String, _StreamCacheEntry> _streamCache = {};



  // ----------------------------------------------------------
  // L3/L4 磁盘缓存索引
  // ----------------------------------------------------------
  /// key: cacheId → CacheEntry
  final Map<String, CacheEntry> _diskIndex = {};

  /// 磁盘缓存总大小缓存（避免每次 O(n) 遍历 _diskIndex）
  int _cachedDiskTotalSize = 0;

  // ----------------------------------------------------------
  // 统计与状态
  // ----------------------------------------------------------
  int _hitCount = 0;
  int _missCount = 0;
  CachePolicy _policy = CachePolicy.normal;

  /// 统计变更通知流控制器
  final StreamController<CacheStats> _statsController =
      StreamController<CacheStats>.broadcast();

  /// 是否已初始化
  bool _initialized = false;

  /// 当前内存压力等级
  MemoryPressureLevel _memoryPressure = MemoryPressureLevel.normal;

  /// 当前活跃的 videoId 集合（用于区分活跃/非活跃 TTL）
  final Set<String> _activeVideoIds = {};

  /// TTL 定期清理定时器
  Timer? _ttlCleanupTimer;

  /// 内存压力检查计数器（避免每次操作都检查）
  int _memoryCheckCounter = 0;

  /// 内存压力检查间隔（每 N 次缓存操作检查一次）
  static const int _memoryCheckInterval = 10;

  final Logger _logger = Logger(printer: SimplePrinter());

  // ----------------------------------------------------------
  // 缓存策略管理器（可选依赖）
  // ----------------------------------------------------------

  /// 智能缓存策略管理器（可选）
  ///
  /// 如果已初始化，则使用动态 TTL / 容量倍数 / 优先级；
  /// 否则回退到硬编码默认值。
  CacheStrategyManager? _strategyManager;

  /// 设置缓存策略管理器
  ///
  /// 传入 null 可清除引用，回退到默认硬编码值。
  void setStrategyManager(CacheStrategyManager? manager) {
    _strategyManager = manager;
    _logger.i('缓存策略管理器已${manager != null ? "接入" : "移除"}');
  }

  /// 获取当前缓存策略管理器（可能为 null）
  CacheStrategyManager? get strategyManager => _strategyManager;

  // ----------------------------------------------------------
  // 常量配置
  // ----------------------------------------------------------

  /// 紧急阈值：可用磁盘空间低于此值触发紧急淘汰（500MB）
  static const int _emergencyThresholdBytes = 500 * 1024 * 1024;

  /// 常规淘汰阈值：磁盘使用率超过 80% 触发淘汰
  static const double _evictionThresholdPercent = 80.0;

  /// 最大缓存容量：min(可用磁盘 * 10%, 2GB)
  static const int _maxCacheBytes = 2 * 1024 * 1024 * 1024;

  /// 热门视频保留窗口：24 小时
  static const Duration _recentlyPlayedWindow = Duration(hours: 24);

  /// 索引文件名
  static const String _indexFileName = 'cache_index.json';

  /// 缓存子目录名
  static const String _cacheSubDir = 'video_cache';

  /// 分段缓存子目录名
  static const String _segmentSubDir = 'segments';

  // ----------------------------------------------------------
  // 内存压力阈值配置
  // ----------------------------------------------------------

  /// 内存压力警告阈值（70%）
  static const double _memoryWarningThreshold = 0.70;

  /// 内存压力严重阈值（90%）
  static const double _memoryCriticalThreshold = 0.90;

  /// 默认最大进程 RSS（512MB），超过此值视为内存压力严重
  static const int _defaultMaxRssBytes = 512 * 1024 * 1024;

  /// 可覆盖的最大进程 RSS（用于测试或高级配置）
  int _maxRssBytes = _defaultMaxRssBytes;

  /// 内存读取函数（可注入以便测试）
  ///
  /// 默认返回 0（安全值），实际使用时可通过 [setMemoryReader] 注入真实实现
  int Function() _memoryReader = () => 0;

  // ----------------------------------------------------------
  // L1/L2 帧缓存 TTL 配置
  // ----------------------------------------------------------

  /// 活跃视频 L1 帧缓存 TTL：5 分钟
  static const Duration _l1ActiveTtl = Duration(minutes: 5);

  /// 非活跃视频 L1 帧缓存 TTL：1 分钟
  static const Duration _l1InactiveTtl = Duration(minutes: 1);

  /// L2 流缓存 TTL：5 分钟
  static const Duration _l2Ttl = Duration(minutes: 5);

  /// TTL 定期清理间隔：30 秒
  static const Duration _ttlCleanupInterval = Duration(seconds: 30);

  // ============================================================
  // 公开属性
  // ============================================================

  /// 当前缓存策略
  CachePolicy get policy => _policy;

  /// 实时统计流
  Stream<CacheStats> get statsStream => _statsController.stream;

  /// 当前内存压力等级
  MemoryPressureLevel get memoryPressure => _memoryPressure;

  /// L1 当前动态最大条目数
  int get l1CurrentMaxEntries => _getL1MaxEntries();

  /// L2 当前动态最大条目数
  int get l2CurrentMaxEntries => _getL2MaxEntries();

  // ============================================================
  // 初始化
  // ============================================================

  /// 初始化缓存服务
  ///
  /// 加载磁盘索引，创建缓存目录
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 确保缓存目录存在
      final cacheDir = await _getCacheDirectory();
      final dir = Directory(cacheDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 确保分段缓存目录存在
      final segDir = await _getSegmentDirectory();
      final segDirectory = Directory(segDir);
      if (!await segDirectory.exists()) {
        await segDirectory.create(recursive: true);
      }

      // 从磁盘加载索引
      await _loadIndexFromDisk();

      // 启动 TTL 定期清理
      _startTtlCleanupTimer();

      _initialized = true;
      _logger.i('视频缓存服务初始化完成，索引条目: ${_diskIndex.length}');
    } catch (e) {
      _logger.e('视频缓存服务初始化失败: $e');
      _initialized = true; // 允许降级运行
    }
  }

  // ============================================================
  // 缓存查询
  // ============================================================

  /// 检查缓存是否存在
  ///
  /// 依次检查 L1 → L2 → L3/L4
  Future<bool> hasCache(String videoId, {String? quality}) async {
    final q = quality ?? '720p';

    // L1 检查
    final l1Key = _buildL1Key(videoId, q);
    if (_memoryCache.containsKey(l1Key)) return true;

    // L2 检查
    final l2Key = _buildL2Key(videoId, '', q);
    if (_streamCache.containsKey(l2Key)) return true;

    // L3/L4 磁盘检查
    final entry = _findDiskEntry(videoId, q);
    if (entry != null && !entry.isExpired) {
      return await File(entry.filePath).exists();
    }

    return false;
  }

  /// 获取缓存文件路径
  ///
  /// 返回 L3 完整视频缓存路径，不存在则返回 null
  Future<String?> getCachePath(String videoId, {String? quality}) async {
    final q = quality ?? '720p';

    // L3 磁盘缓存查找
    final entry = _findDiskEntry(videoId, q);
    if (entry != null && !entry.isExpired && entry.isComplete) {
      final file = File(entry.filePath);
      if (await file.exists()) {
        // 更新命中信息
        entry.hitCount++;
        entry.lastAccess = DateTime.now();
        _hitCount++;
        _notifyStats();
        _logger.d('缓存命中(L3): $videoId@$q');
        // 记录观看行为
        _recordViewingIfNeeded(videoId);
        return entry.filePath;
      }
    }

    _missCount++;
    _notifyStats();
    return null;
  }

  /// 跨清晰度缓存查找 — 清晰度降级命中
  ///
  /// 当请求的清晰度未命中时，尝试查找其他清晰度的缓存。
  /// 按清晰度优先级排序：请求的清晰度 > 高清 > 标清 > 流畅
  /// 返回 (path, quality) 或 null
  Future<({String path, String quality})?> getAnyQualityCachePath(
    String videoId, {
    String? preferredQuality,
  }) async {
    // 1. 先查找请求的清晰度
    if (preferredQuality != null) {
      final exact = await getCachePath(videoId, quality: preferredQuality);
      if (exact != null) {
        return (path: exact, quality: preferredQuality);
      }
    }

    // 2. 按清晰度优先级查找：超清 > 高清 > 标清 > 流畅
    const qualityPriority = ['超清', '高清', '标清', '流畅'];
    for (final q in qualityPriority) {
      if (q == preferredQuality) continue; // 已查过
      final path = await getCachePath(videoId, quality: q);
      if (path != null) {
        return (path: path, quality: q);
      }
    }

    // 3. 查找磁盘索引中该 videoId 的任何清晰度
    for (final entry in _diskIndex.values) {
      if (entry.videoId == videoId && !entry.isExpired && entry.isComplete) {
        final file = File(entry.filePath);
        if (await file.exists()) {
          entry.hitCount++;
          entry.lastAccess = DateTime.now();
          _hitCount++;
          _notifyStats();
          return (path: entry.filePath, quality: entry.quality);
        }
      }
    }

    return null;
  }

  // ============================================================
  // 缓存写入
  // ============================================================

  /// 缓存完整视频文件（L3）
  ///
  /// 将视频文件存入磁盘缓存并更新索引。
  /// 如果已接入 [CacheStrategyManager]，TTL 和 priority 将使用动态值。
  Future<void> putVideo(
    String videoId,
    String filePath, {
    String quality = '720p',
    int priority = 0,
    int ttl = 604800,
    String? category,
  }) async {
    try {
      // 使用动态 TTL（如果策略管理器可用）
      final effectiveTtl = _strategyManager != null &&
              _strategyManager!.isInitialized
          ? _strategyManager!.getDynamicTtl(videoId,
              category: category, baseTtl: ttl)
          : ttl;

      // 使用动态优先级（如果策略管理器可用）
      int effectivePriority = priority;
      if (_strategyManager != null && _strategyManager!.isInitialized) {
        final dynamicPriority =
            _strategyManager!.getPriority(videoId, category: category);
        // 将 CachePriority 映射为数值：high=20, normal=0, low=-5
        final mappedPriority = dynamicPriority == CachePriority.high
            ? 20
            : dynamicPriority == CachePriority.low
                ? -5
                : 0;
        // 取调用方传入的 priority 和动态 priority 中的较大值
        if (mappedPriority > effectivePriority) {
          effectivePriority = mappedPriority;
        }
      }
      final cacheDir = await _getCacheDirectory();
      final sourceFile = File(filePath);

      if (!await sourceFile.exists()) {
        _logger.w('源文件不存在，无法缓存: $filePath');
        return;
      }

      final fileSize = await sourceFile.length();
      final cacheId = _generateCacheId(videoId, quality);
      final ext = p.extension(filePath);
      final destPath = p.join(cacheDir, '$cacheId$ext');

      // 若目标文件已存在则先删除
      final destFile = File(destPath);
      if (await destFile.exists()) {
        await destFile.delete();
      }

      // 复制文件到缓存目录
      await sourceFile.copy(destPath);

      // 更新磁盘索引
      final entry = CacheEntry(
        cacheId: cacheId,
        videoId: videoId,
        quality: quality,
        filePath: destPath,
        fileSize: fileSize,
        priority: effectivePriority,
        ttl: effectiveTtl,
        isComplete: true,
      );

      _diskIndex[cacheId] = entry;
      _addToDiskTotal(entry.fileSize);
      await _saveIndexToDisk();
      _notifyStats();

      _logger.i('视频已缓存(L3): $videoId@$quality, 大小: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');

      // 检查是否需要触发淘汰
      await _checkEvictionNeeded();
    } catch (e) {
      _logger.e('缓存视频失败: $videoId, 错误: $e');
    }
  }

  /// 缓存分段数据（L2 + L4）
  ///
  /// 同时写入 L2 内存缓存和 L4 磁盘缓存
  Future<void> putSegment(
    String videoId,
    String segmentKey,
    List<int> data, {
    String quality = '720p',
  }) async {
    try {
      // 内存压力检查
      _periodicMemoryPressureCheck();

      final l2Key = _buildL2Key(videoId, segmentKey, quality);

      // L2 内存缓存写入（内存压力严重时跳过）
      if (_memoryPressure != MemoryPressureLevel.critical) {
        _streamCache[l2Key] = _StreamCacheEntry(
          videoId: videoId,
          segmentKey: segmentKey,
          quality: quality,
          data: data,
        );

        // L2 淘汰：超出上限时移除最早条目
        _evictL2IfNeeded();
      }

      // L4 磁盘缓存写入
      final segDir = await _getSegmentDirectory();
      final segFileName = '${_generateCacheId(videoId, quality)}_$segmentKey.seg';
      final segPath = p.join(segDir, segFileName);
      final segFile = File(segPath);
      await segFile.writeAsBytes(data);

      // 更新磁盘索引
      final cacheId = _generateCacheId(videoId, quality);
      final existing = _diskIndex[cacheId];
      if (existing != null) {
        if (!existing.segments.contains(segmentKey)) {
          existing.segments.add(segmentKey);
        }
        _addToDiskTotal(data.length);
        existing.fileSize += data.length;
        existing.lastAccess = DateTime.now();
      } else {
        _diskIndex[cacheId] = CacheEntry(
          cacheId: cacheId,
          videoId: videoId,
          quality: quality,
          filePath: segPath,
          fileSize: data.length,
          segments: [segmentKey],
          isComplete: false,
        );
        _addToDiskTotal(data.length);
      }

      await _saveIndexToDisk();
      _notifyStats();

      _logger.d('分段已缓存: $videoId/$segmentKey@$quality, 大小: ${data.length}B');
    } catch (e) {
      _logger.e('缓存分段失败: $videoId/$segmentKey, 错误: $e');
    }
  }

  /// 获取分段缓存数据
  ///
  /// 查询顺序：L2 内存 → L4 磁盘
  Future<SegmentCacheResult> getSegment(
    String videoId,
    String segmentKey, {
    String? quality,
  }) async {
    final q = quality ?? '720p';

    // L2 内存缓存查询
    final l2Key = _buildL2Key(videoId, segmentKey, q);
    final streamEntry = _streamCache[l2Key];
    if (streamEntry != null) {
      // 检查 L2 TTL 是否已过期
      if (streamEntry.isExpired(_l2Ttl)) {
        _streamCache.remove(l2Key);
        _logger.d('L2 TTL 过期，移除: $videoId/$segmentKey@$q');
      } else {
        streamEntry.hitCount++;
        streamEntry.lastAccess = DateTime.now();
        _hitCount++;
        _notifyStats();
        _logger.d('分段命中(L2): $videoId/$segmentKey@$q');
        // 记录观看行为
        _recordViewingIfNeeded(videoId);
        return SegmentCacheResult(hit: true, data: streamEntry.data);
      }
    }

    // L4 磁盘缓存查询
    final cacheId = _generateCacheId(videoId, q);
    final diskEntry = _diskIndex[cacheId];
    if (diskEntry != null && diskEntry.segments.contains(segmentKey)) {
      final segDir = await _getSegmentDirectory();
      final segPath = p.join(segDir, '${cacheId}_$segmentKey.seg');
      final segFile = File(segPath);
      if (await segFile.exists()) {
        diskEntry.hitCount++;
        diskEntry.lastAccess = DateTime.now();
        _hitCount++;
        _notifyStats();
        _logger.d('分段命中(L4): $videoId/$segmentKey@$q');
        // 记录观看行为
        _recordViewingIfNeeded(videoId);
        return SegmentCacheResult(hit: true, path: segPath);
      }
    }

    _missCount++;
    _notifyStats();
    return SegmentCacheResult(hit: false);
  }

  // ============================================================
  // 淘汰策略
  // ============================================================

  /// 执行缓存淘汰
  ///
  /// 淘汰顺序：
  /// 1. 过期条目
  /// 2. 低优先级预加载条目
  /// 3. LRU（最近最少使用）
  /// 4. 大文件
  ///
  /// 保留：用户收藏、24h 内播放记录、热门视频
  Future<void> evict() async {
    _logger.i('开始缓存淘汰，当前条目数: ${_diskIndex.length}');

    int evictedCount = 0;

    // ---- 阶段 1：淘汰过期条目 ----
    evictedCount += await _evictExpired();

    // ---- 阶段 2：淘汰低优先级预加载 ----
    evictedCount += await _evictLowPriorityPreload();

    // 检查磁盘使用率
    final usagePercent = await _getDiskUsagePercent();
    if (usagePercent < _evictionThresholdPercent) {
      _logger.i('淘汰完成（阶段1-2），已淘汰: $evictedCount');
      await _saveIndexToDisk();
      _notifyStats();
      return;
    }

    // ---- 阶段 3：LRU 淘汰 ----
    evictedCount += await _evictLRU();

    // 检查磁盘使用率
    final usageAfterLRU = await _getDiskUsagePercent();
    if (usageAfterLRU < _evictionThresholdPercent) {
      _logger.i('淘汰完成（阶段1-3），已淘汰: $evictedCount');
      await _saveIndexToDisk();
      _notifyStats();
      return;
    }

    // ---- 阶段 4：大文件淘汰 ----
    evictedCount += await _evictLargeFiles();

    await _saveIndexToDisk();
    _notifyStats();
    _logger.i('淘汰完成（全部阶段），已淘汰: $evictedCount');
  }

  /// 清除所有缓存
  Future<void> clearAll() async {
    // 取消 TTL 清理定时器
    _ttlCleanupTimer?.cancel();
    _ttlCleanupTimer = null;

    // 清除 L1
    _memoryCache.clear();

    // 清除 L2
    _streamCache.clear();

    // 重置内存压力状态
    _memoryPressure = MemoryPressureLevel.normal;
    _activeVideoIds.clear();
    _memoryCheckCounter = 0;

    // 清除 L3/L4 磁盘缓存
    try {
      final cacheDir = await _getCacheDirectory();
      final dir = Directory(cacheDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }

      // 重建分段目录
      final segDir = await _getSegmentDirectory();
      final segDirectory = Directory(segDir);
      if (!await segDirectory.exists()) {
        await segDirectory.create(recursive: true);
      }
    } catch (e) {
      _logger.e('清除磁盘缓存失败: $e');
    }

    // 清除索引
    _diskIndex.clear();
    _hitCount = 0;
    _missCount = 0;
    await _saveIndexToDisk();
    _notifyStats();

    _logger.i('所有缓存已清除');
  }

  // ============================================================
  // 统计
  // ============================================================

  /// 获取缓存统计数据
  Future<CacheStats> getStats() async {
    int totalSize = 0;
    for (final entry in _diskIndex.values) {
      totalSize += entry.fileSize;
    }

    final usagePercent = await _getDiskUsagePercent();
    final total = _hitCount + _missCount;
    final hitRate = total > 0 ? _hitCount / total : 0.0;

    return CacheStats(
      totalSize: totalSize,
      entryCount: _diskIndex.length,
      hitCount: _hitCount,
      missCount: _missCount,
      hitRate: hitRate,
      diskUsagePercent: usagePercent,
    );
  }

  // ============================================================
  // 缓存策略
  // ============================================================

  /// 设置缓存策略
  void setPolicy(CachePolicy policy) {
    _policy = policy;
    _logger.i('缓存策略已切换: $policy');
  }

  /// 根据网络与存储状态自动选择策略
  Future<void> autoSelectPolicy({
    required bool isWiFi,
    required int availableDiskBytes,
  }) async {
    if (availableDiskBytes < _emergencyThresholdBytes) {
      setPolicy(CachePolicy.emergency);
    } else if (!isWiFi) {
      setPolicy(CachePolicy.conservative);
    } else if (isWiFi && availableDiskBytes > _emergencyThresholdBytes * 4) {
      setPolicy(CachePolicy.aggressive);
    } else {
      setPolicy(CachePolicy.normal);
    }
  }

  // ============================================================
  // L1 内存缓存操作
  // ============================================================

  /// 写入 L1 帧缓冲缓存
  void putFrameBuffer(
    String videoId,
    Map<String, dynamic> frameBuffer, {
    String quality = '720p',
  }) {
    // 内存压力检查
    _periodicMemoryPressureCheck();

    // 严重内存压力下拒绝新的 L1 写入
    if (_memoryPressure == MemoryPressureLevel.critical) {
      _logger.w('内存压力严重，拒绝 L1 写入: $videoId@$quality');
      return;
    }

    // 标记为活跃视频
    _activeVideoIds.add(videoId);

    final key = _buildL1Key(videoId, quality);
    _memoryCache[key] = _MemoryCacheEntry(
      videoId: videoId,
      quality: quality,
      frameBuffer: frameBuffer,
    );
    _evictL1IfNeeded();
  }

  /// 读取 L1 帧缓冲缓存
  Map<String, dynamic>? getFrameBuffer(
    String videoId, {
    String quality = '720p',
  }) {
    final key = _buildL1Key(videoId, quality);
    final entry = _memoryCache[key];
    if (entry != null) {
      // 检查 TTL 是否已过期
      final ttl = _activeVideoIds.contains(videoId) ? _l1ActiveTtl : _l1InactiveTtl;
      if (entry.isExpired(ttl)) {
        _memoryCache.remove(key);
        _logger.d('L1 TTL 过期，移除: $videoId@$quality');
        _missCount++;
        _notifyStats();
        return null;
      }
      entry.hitCount++;
      entry.lastAccess = DateTime.now();
      _hitCount++;
      _notifyStats();
      // 记录观看行为
      _recordViewingIfNeeded(videoId);
      return entry.frameBuffer;
    }
    _missCount++;
    _notifyStats();
    return null;
  }

  /// 标记视频为活跃状态（影响 TTL 策略）
  void markVideoActive(String videoId) {
    _activeVideoIds.add(videoId);
  }

  /// 标记视频为非活跃状态
  void markVideoInactive(String videoId) {
    _activeVideoIds.remove(videoId);
  }

  // ============================================================
  // 内部方法 — 键生成
  // ============================================================

  /// L1 缓存键
  String _buildL1Key(String videoId, String quality) =>
      '${videoId}_$quality';

  /// L2 缓存键
  String _buildL2Key(String videoId, String segmentKey, String quality) =>
      '${videoId}_${segmentKey}_$quality';

  /// 生成缓存ID
  String _generateCacheId(String videoId, String quality) {
    return hashKey('${videoId}_$quality');
  }

  // ============================================================
  // 内部方法 — 磁盘索引
  // ============================================================

  /// 在磁盘索引中查找条目
  CacheEntry? _findDiskEntry(String videoId, String quality) {
    final cacheId = _generateCacheId(videoId, quality);
    return _diskIndex[cacheId];
  }

  /// 从磁盘加载索引
  Future<void> _loadIndexFromDisk() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final indexFile = File(p.join(cacheDir, _indexFileName));
      if (!await indexFile.exists()) return;

      final jsonStr = await indexFile.readAsString();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final entries = decoded['entries'] as Map<String, dynamic>? ?? {};

      _diskIndex.clear();
      for (final entry in entries.entries) {
        try {
          _diskIndex[entry.key] =
              CacheEntry.fromJson(entry.value as Map<String, dynamic>);
        } catch (e) {
          _logger.w('加载索引条目失败: ${entry.key}, 错误: $e');
        }
      }

      _recomputeDiskTotal();
      _logger.d('磁盘索引已加载，条目数: ${_diskIndex.length}');
    } catch (e) {
      _logger.w('加载磁盘索引失败: $e');
    }
  }

  /// 保存索引到磁盘
  Future<void> _saveIndexToDisk() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final indexFile = File(p.join(cacheDir, _indexFileName));
      final tempFile = File(p.join(cacheDir, '$_indexFileName.tmp'));

      final entriesMap = <String, dynamic>{};
      for (final entry in _diskIndex.entries) {
        entriesMap[entry.key] = entry.value.toJson();
      }

      final jsonStr = jsonEncode({'entries': entriesMap});

      // 先写入临时文件
      await tempFile.writeAsString(jsonStr);
      // 原子替换：删除旧文件，重命名临时文件
      if (await indexFile.exists()) {
        await indexFile.delete();
      }
      await tempFile.rename(indexFile.path);
    } catch (e) {
      _logger.e('保存磁盘索引失败: $e');
    }
  }

  // ============================================================
  // 内部方法 — 目录与磁盘空间
  // ============================================================

  /// 获取缓存根目录
  Future<String> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, _cacheSubDir);
  }

  /// 获取分段缓存目录
  Future<String> _getSegmentDirectory() async {
    final cacheDir = await _getCacheDirectory();
    return p.join(cacheDir, _segmentSubDir);
  }

  /// 获取最大缓存容量（字节）
  Future<int> _getMaxCacheSize() async {
    try {
      final available = await _getAvailableDiskSpace();
      final tenPercent = (available * 0.1).round();
      return tenPercent < _maxCacheBytes ? tenPercent : _maxCacheBytes;
    } catch (e) {
      return _maxCacheBytes;
    }
  }

  /// 获取可用磁盘空间（字节）
  Future<int> _getAvailableDiskSpace() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (Platform.isAndroid || Platform.isLinux) {
        final result =
            await Process.run('df', ['-B1', appDir.path],
                runInShell: true);
        if (result.exitCode == 0) {
          final lines =
              (result.stdout as String).split('\n');
          if (lines.length >= 2) {
            final parts =
                lines[1].trim().split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final available =
                  int.tryParse(parts[3]);
              if (available != null &&
                  available > 0) {
                return available;
              }
            }
          }
        }
      }
    } catch (e) {
      _logger.w('获取磁盘可用空间失败: $e');
    }
    return _maxCacheBytes * 10;
  }

  /// 计算当前磁盘缓存使用率百分比
  Future<double> _getDiskUsagePercent() async {
    final maxSize = await _getMaxCacheSize();
    if (maxSize <= 0) return 0.0;
    return (_cachedDiskTotalSize / maxSize) * 100.0;
  }

  /// 计算当前缓存总大小
  // ignore: unused_element
  int _calculateTotalCacheSize() => _cachedDiskTotalSize;

  void _addToDiskTotal(int size) => _cachedDiskTotalSize += size;
  void _subtractFromDiskTotal(int size) => _cachedDiskTotalSize -= size;
  void _recomputeDiskTotal() {
    _cachedDiskTotalSize = 0;
    for (final entry in _diskIndex.values) {
      _cachedDiskTotalSize += entry.fileSize;
    }
  }

  // ============================================================
  // 内部方法 — 淘汰实现
  // ============================================================

  /// 检查是否需要触发淘汰
  Future<void> _checkEvictionNeeded() async {
    // 紧急淘汰：可用空间不足
    final available = await _getAvailableDiskSpace();
    if (available < _emergencyThresholdBytes) {
      _logger.w('磁盘空间不足，触发紧急淘汰');
      setPolicy(CachePolicy.emergency);
      await evict();
      return;
    }

    // 常规淘汰：使用率超阈值
    final usagePercent = await _getDiskUsagePercent();
    if (usagePercent > _evictionThresholdPercent) {
      _logger.i('缓存使用率 ${usagePercent.toStringAsFixed(1)}%，触发常规淘汰');
      await evict();
    }
  }

  /// 阶段 1：淘汰过期条目
  Future<int> _evictExpired() async {
    final expiredKeys = <String>[];

    for (final entry in _diskIndex.entries) {
      if (entry.value.isExpired) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      await _removeDiskEntry(key);
    }

    if (expiredKeys.isNotEmpty) {
      _logger.d('淘汰过期条目: ${expiredKeys.length}');
    }
    return expiredKeys.length;
  }

  /// 阶段 2：淘汰低优先级预加载条目
  Future<int> _evictLowPriorityPreload() async {
    final preloadKeys = <String>[];

    for (final entry in _diskIndex.entries) {
      // 有效优先级 <= 0 且非完整视频（预加载分段），且不在保留窗口内
      final effectivePri = _getEffectivePriorityForEntry(entry.value);
      if (effectivePri <= 0 &&
          !entry.value.isComplete &&
          !_shouldKeep(entry.value)) {
        preloadKeys.add(entry.key);
      }
    }

    // 按优先级升序、最后访问时间升序排列
    preloadKeys.sort((a, b) {
      final ea = _diskIndex[a]!;
      final eb = _diskIndex[b]!;
      final priA = _getEffectivePriorityForEntry(ea);
      final priB = _getEffectivePriorityForEntry(eb);
      final priCmp = priA.compareTo(priB);
      if (priCmp != 0) return priCmp;
      return ea.lastAccess.compareTo(eb.lastAccess);
    });

    int evicted = 0;
    for (final key in preloadKeys) {
      await _removeDiskEntry(key);
      evicted++;
      // 每淘汰一个检查使用率
      final usage = await _getDiskUsagePercent();
      if (usage < _evictionThresholdPercent) break;
    }

    if (evicted > 0) {
      _logger.d('淘汰低优先级预加载: $evicted');
    }
    return evicted;
  }

  /// 阶段 3：LRU 淘汰
  Future<int> _evictLRU() async {
    // 收集可淘汰条目（排除需保留的）
    final candidates = <String>[];

    for (final entry in _diskIndex.entries) {
      if (!_shouldKeep(entry.value)) {
        candidates.add(entry.key);
      }
    }

    // 按最后访问时间升序排列（最久未访问排前面），同时考虑动态优先级
    candidates.sort((a, b) {
      final ea = _diskIndex[a]!;
      final eb = _diskIndex[b]!;
      final priA = _getEffectivePriorityForEntry(ea);
      final priB = _getEffectivePriorityForEntry(eb);
      // 高优先级条目排后面（不容易被淘汰）
      if (priA != priB) return priA.compareTo(priB);
      return ea.lastAccess.compareTo(eb.lastAccess);
    });

    int evicted = 0;
    for (final key in candidates) {
      await _removeDiskEntry(key);
      evicted++;
      final usage = await _getDiskUsagePercent();
      if (usage < _evictionThresholdPercent) break;
    }

    if (evicted > 0) {
      _logger.d('LRU淘汰: $evicted');
    }
    return evicted;
  }

  /// 阶段 4：大文件淘汰
  Future<int> _evictLargeFiles() async {
    final candidates = <String>[];

    for (final entry in _diskIndex.entries) {
      if (!_shouldKeep(entry.value)) {
        candidates.add(entry.key);
      }
    }

    // 按文件大小降序排列（大文件优先淘汰），同时考虑动态优先级
    candidates.sort((a, b) {
      final ea = _diskIndex[a]!;
      final eb = _diskIndex[b]!;
      final priA = _getEffectivePriorityForEntry(ea);
      final priB = _getEffectivePriorityForEntry(eb);
      // 高优先级条目排后面（不容易被淘汰）
      if (priA != priB) return priA.compareTo(priB);
      return eb.fileSize.compareTo(ea.fileSize);
    });

    int evicted = 0;
    for (final key in candidates) {
      await _removeDiskEntry(key);
      evicted++;
      final usage = await _getDiskUsagePercent();
      if (usage < _evictionThresholdPercent) break;
    }

    if (evicted > 0) {
      _logger.d('大文件淘汰: $evicted');
    }
    return evicted;
  }

  /// 判断条目是否应保留
  ///
  /// 保留条件：用户收藏（effectivePriority >= 10）、24h 内播放记录、热门视频（hitCount >= 10）
  bool _shouldKeep(CacheEntry entry) {
    // 使用动态优先级（如果可用）
    final effectivePriority = _getEffectivePriorityForEntry(entry);

    // 用户收藏
    if (effectivePriority >= 10) return true;

    // 24h 内播放记录
    if (DateTime.now().difference(entry.lastAccess) < _recentlyPlayedWindow) {
      return true;
    }

    // 热门视频
    if (entry.hitCount >= 10) return true;

    return false;
  }

  /// 从磁盘索引中移除条目并删除文件
  Future<void> _removeDiskEntry(String cacheId) async {
    final entry = _diskIndex[cacheId];
    if (entry == null) return;

    try {
      // 删除完整视频文件
      if (entry.isComplete) {
        final file = File(entry.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        // 删除分段文件
        final segDir = await _getSegmentDirectory();
        for (final seg in entry.segments) {
          final segFile = File(p.join(segDir, '${cacheId}_$seg.seg'));
          if (await segFile.exists()) {
            await segFile.delete();
          }
        }
      }
    } catch (e) {
      _logger.w('删除缓存文件失败: ${entry.filePath}, 错误: $e');
    }

    _subtractFromDiskTotal(entry.fileSize);
    _diskIndex.remove(cacheId);
  }

  // ============================================================
  // 内部方法 — L1/L2 内存淘汰
  // ============================================================

  /// 从 Map 中淘汰最久未访问的条目（通用 LRU）
  void _evictOldestFromMap<T>(Map<String, T> map, int maxEntries) {
    while (map.length > maxEntries) {
      String? oldestKey;
      DateTime? oldestTime;
      for (final entry in map.entries) {
        final lastAccess = (entry.value as dynamic).lastAccess as DateTime;
        if (oldestTime == null || lastAccess.isBefore(oldestTime)) {
          oldestKey = entry.key;
          oldestTime = lastAccess;
        }
      }
      if (oldestKey != null) {
        map.remove(oldestKey);
      } else {
        break;
      }
    }
  }

  /// L1 内存缓存淘汰（使用动态容量）
  void _evictL1IfNeeded() =>
      _evictOldestFromMap(_memoryCache, _getL1MaxEntries());

  /// L2 内存缓存淘汰（使用动态容量）
  void _evictL2IfNeeded() =>
      _evictOldestFromMap(_streamCache, _getL2MaxEntries());

  /// 根据内存压力等级计算 L1 动态最大条目数
  int _getL1MaxEntries() {
    switch (_memoryPressure) {
      case MemoryPressureLevel.normal:
        return _l1BaseMaxEntries;
      case MemoryPressureLevel.warning:
        return _l1BaseMaxEntries ~/ 2; // 减半
      case MemoryPressureLevel.critical:
        return 0; // 清空
    }
  }

  /// 根据内存压力等级计算 L2 动态最大条目数
  ///
  /// 如果已接入 [CacheStrategyManager]，基础容量会乘以动态容量倍数。
  int _getL2MaxEntries() {
    int base;
    switch (_memoryPressure) {
      case MemoryPressureLevel.normal:
        base = _l2BaseMaxEntries;
      case MemoryPressureLevel.warning:
        base = _l2BaseMaxEntries ~/ 2; // 减半
      case MemoryPressureLevel.critical:
        base = _l2MinEntries; // 最低
    }
    // 应用策略管理器的容量倍数
    if (_strategyManager != null && _strategyManager!.isInitialized) {
      final multiplier = _strategyManager!.getCapacityMultiplier();
      return (base * multiplier).round().clamp(_l2MinEntries, _l2BaseMaxEntries * 3);
    }
    return base;
  }

  // ============================================================
  // 内部方法 — 内存压力感知
  // ============================================================

  /// 检查当前内存压力等级
  ///
  /// 使用 ProcessInfo.currentRss 获取进程常驻集大小，
  /// 与配置的阈值比较确定内存压力等级
  MemoryPressureLevel _checkMemoryPressure() {
    final rss = _memoryReader();
    final ratio = _maxRssBytes > 0 ? rss / _maxRssBytes : 0.0;

    final MemoryPressureLevel newLevel;
    if (ratio >= _memoryCriticalThreshold) {
      newLevel = MemoryPressureLevel.critical;
    } else if (ratio >= _memoryWarningThreshold) {
      newLevel = MemoryPressureLevel.warning;
    } else {
      newLevel = MemoryPressureLevel.normal;
    }

    if (newLevel != _memoryPressure) {
      _logger.w('内存压力等级变更: $_memoryPressure → $newLevel '
          '(RSS: ${(rss / 1024 / 1024).toStringAsFixed(1)}MB, '
          '阈值: ${(_maxRssBytes / 1024 / 1024).toStringAsFixed(0)}MB)');
      _memoryPressure = newLevel;

      // 压力变更时立即执行淘汰
      _evictL1IfNeeded();
      _evictL2IfNeeded();
    }

    return newLevel;
  }

  /// 周期性内存压力检查（每 N 次缓存操作检查一次）
  void _periodicMemoryPressureCheck() {
    _memoryCheckCounter++;
    if (_memoryCheckCounter >= _memoryCheckInterval) {
      _memoryCheckCounter = 0;
      _checkMemoryPressure();
    }
  }

  // ============================================================
  // 内部方法 — L1/L2 TTL 淘汰
  // ============================================================

  /// 淘汰过期的 L1 帧缓存条目
  int _evictExpiredL1Entries() {
    final expiredKeys = <String>[];
    for (final entry in _memoryCache.entries) {
      final videoId = entry.value.videoId;
      final ttl =
          _activeVideoIds.contains(videoId) ? _l1ActiveTtl : _l1InactiveTtl;
      if (entry.value.isExpired(ttl)) {
        expiredKeys.add(entry.key);
      }
    }
    for (final key in expiredKeys) {
      _memoryCache.remove(key);
    }
    if (expiredKeys.isNotEmpty) {
      _logger.d('L1 TTL 淘汰: ${expiredKeys.length} 条');
    }
    return expiredKeys.length;
  }

  /// 淘汰过期的 L2 流缓存条目
  int _evictExpiredL2Entries() {
    final expiredKeys = <String>[];
    for (final entry in _streamCache.entries) {
      if (entry.value.isExpired(_l2Ttl)) {
        expiredKeys.add(entry.key);
      }
    }
    for (final key in expiredKeys) {
      _streamCache.remove(key);
    }
    if (expiredKeys.isNotEmpty) {
      _logger.d('L2 TTL 淘汰: ${expiredKeys.length} 条');
    }
    return expiredKeys.length;
  }

  /// 启动 TTL 定期清理定时器
  void _startTtlCleanupTimer() {
    _ttlCleanupTimer?.cancel();
    _ttlCleanupTimer = Timer.periodic(_ttlCleanupInterval, (_) {
      _ttlCleanup();
    });
  }

  /// TTL 定期清理执行
  void _ttlCleanup() {
    final l1Evicted = _evictExpiredL1Entries();
    final l2Evicted = _evictExpiredL2Entries();
    if (l1Evicted > 0 || l2Evicted > 0) {
      _logger.d('TTL 定期清理: L1=$l1Evicted, L2=$l2Evicted');
    }
    // 同时检查内存压力
    _checkMemoryPressure();
  }

  // ============================================================
  // 公开方法 — 内存监控接口
  // ============================================================

  /// 获取当前内存使用信息
  ///
  /// 返回 L1/L2 当前占用内存、进程 RSS、内存压力等级等
  MemoryUsageInfo getMemoryUsage() {
    int l1Bytes = 0;
    for (final entry in _memoryCache.values) {
      l1Bytes += entry.estimatedBytes;
    }

    int l2Bytes = 0;
    for (final entry in _streamCache.values) {
      l2Bytes += entry.data.length;
    }

    return MemoryUsageInfo(
      l1Bytes: l1Bytes,
      l2Bytes: l2Bytes,
      processRssBytes: _memoryReader(),
      pressureLevel: _memoryPressure,
      l1MaxEntries: _getL1MaxEntries(),
      l2MaxEntries: _getL2MaxEntries(),
    );
  }

  /// 裁剪内存
  ///
  /// 供外部在收到系统内存警告时调用。
  /// 立即检查内存压力并执行淘汰。
  void trimMemory() {
    _logger.i('trimMemory 被调用，当前压力: $_memoryPressure');
    _checkMemoryPressure();

    // 严重压力时清空 L1
    if (_memoryPressure == MemoryPressureLevel.critical) {
      _memoryCache.clear();
      _logger.w('trimMemory: 内存压力严重，已清空 L1');
    }

    // 无论如何都执行 TTL 淘汰
    _evictExpiredL1Entries();
    _evictExpiredL2Entries();

    // 按动态容量淘汰
    _evictL1IfNeeded();
    _evictL2IfNeeded();
  }

  /// 清空所有内存缓存（L1 + L2），不影响磁盘缓存
  ///
  /// 供外部在需要快速释放内存时调用（如页面切换、后台切换）。
  /// 与 [trimMemory] 不同，此方法无条件清空所有 L1/L2 条目，
  /// 不检查内存压力等级。
  void clearAllMemoryCaches() {
    final l1Count = _memoryCache.length;
    final l2Count = _streamCache.length;
    _memoryCache.clear();
    _streamCache.clear();
    _logger.i('clearAllMemoryCaches: 已清空 L1($l1Count条) + L2($l2Count条)');
  }

  /// 设置最大 RSS 阈值（用于测试或高级配置）
  void setMaxRssBytes(int maxRssBytes) {
    _maxRssBytes = maxRssBytes;
  }

  /// 设置内存读取函数（用于测试或注入真实实现）
  ///
  /// 示例：
  /// ```dart
  /// // 注入真实实现
  /// import 'dart:developer' show ProcessInfo;
  /// service.setMemoryReader(() => ProcessInfo.currentRss);
  ///
  /// // 测试时注入模拟值
  /// service.setMemoryReader(() => 400 * 1024 * 1024);
  /// ```
  void setMemoryReader(int Function() reader) {
    _memoryReader = reader;
  }

  // ============================================================
  // 内部方法 — 观看行为记录
  // ============================================================

  /// 记录观看行为到策略管理器（如果可用）
  ///
  /// 在缓存命中时调用，用于追踪用户观看习惯。
  void _recordViewingIfNeeded(String videoId) {
    if (_strategyManager != null && _strategyManager!.isInitialized) {
      try {
        _strategyManager!.recordViewing(videoId);
      } catch (e) {
        _logger.w('记录观看行为失败: $e');
      }
    }
  }

  // ============================================================
  // 内部方法 — 淘汰策略管理器感知的优先级
  // ============================================================

  /// 获取条目的有效优先级（用于淘汰排序）
  ///
  /// 如果策略管理器可用，使用动态优先级；否则使用条目自身的 priority 字段。
  int _getEffectivePriorityForEntry(CacheEntry entry) {
    if (_strategyManager != null && _strategyManager!.isInitialized) {
      try {
        final dynamicPriority =
            _strategyManager!.getPriority(entry.videoId);
        // 将 CachePriority 映射为数值，与 entry.priority 取较大值
        final mappedPriority = dynamicPriority == CachePriority.high
            ? 20
            : dynamicPriority == CachePriority.low
                ? -5
                : 0;
        return mappedPriority > entry.priority ? mappedPriority : entry.priority;
      } catch (e) {
        // 降级到条目自身优先级
      }
    }
    return entry.priority;
  }

  // ============================================================
  // 内部方法 — 统计通知
  // ============================================================

  /// 通知统计数据变更
  void _notifyStats() {
    if (_statsController.isClosed) return;

    // 异步计算统计，避免阻塞
    Future.microtask(() async {
      try {
        final stats = await getStats();
        if (!_statsController.isClosed) {
          _statsController.add(stats);
        }
      } catch (e) {
        // 静默处理，避免通知流程影响主逻辑
      }
    });
  }

  // ============================================================
  // 资源释放
  // ============================================================

  /// 释放资源
  void dispose() {
    _ttlCleanupTimer?.cancel();
    _ttlCleanupTimer = null;
    _statsController.close();
    _memoryCache.clear();
    _streamCache.clear();
    _activeVideoIds.clear();
  }
}
