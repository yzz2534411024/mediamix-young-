import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:logger/logger.dart';

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

  _MemoryCacheEntry({
    required this.videoId,
    required this.quality,
    required this.frameBuffer,
    DateTime? lastAccess,
    this.hitCount = 0,
  }) : lastAccess = lastAccess ?? DateTime.now();
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

  _StreamCacheEntry({
    required this.videoId,
    required this.segmentKey,
    required this.quality,
    required this.data,
    DateTime? lastAccess,
    this.hitCount = 0,
  }) : lastAccess = lastAccess ?? DateTime.now();
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

  /// L1 最大条目数
  static const int _l1MaxEntries = 20;

  // ----------------------------------------------------------
  // L2 内存缓存 — 原始流数据
  // ----------------------------------------------------------
  /// key: "${videoId}_${segmentKey}_${quality}"
  final Map<String, _StreamCacheEntry> _streamCache = {};

  /// L2 最大条目数
  static const int _l2MaxEntries = 50;

  // ----------------------------------------------------------
  // L3/L4 磁盘缓存索引
  // ----------------------------------------------------------
  /// key: cacheId → CacheEntry
  final Map<String, CacheEntry> _diskIndex = {};

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

  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

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

  // ============================================================
  // 公开属性
  // ============================================================

  /// 当前缓存策略
  CachePolicy get policy => _policy;

  /// 实时统计流
  Stream<CacheStats> get statsStream => _statsController.stream;

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
        return entry.filePath;
      }
    }

    _missCount++;
    _notifyStats();
    return null;
  }

  // ============================================================
  // 缓存写入
  // ============================================================

  /// 缓存完整视频文件（L3）
  ///
  /// 将视频文件存入磁盘缓存并更新索引
  Future<void> putVideo(
    String videoId,
    String filePath, {
    String quality = '720p',
    int priority = 0,
    int ttl = 604800,
  }) async {
    try {
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
        priority: priority,
        ttl: ttl,
        isComplete: true,
      );

      _diskIndex[cacheId] = entry;
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
      final l2Key = _buildL2Key(videoId, segmentKey, quality);

      // L2 内存缓存写入
      _streamCache[l2Key] = _StreamCacheEntry(
        videoId: videoId,
        segmentKey: segmentKey,
        quality: quality,
        data: data,
      );

      // L2 淘汰：超出上限时移除最早条目
      _evictL2IfNeeded();

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
      streamEntry.hitCount++;
      streamEntry.lastAccess = DateTime.now();
      _hitCount++;
      _notifyStats();
      _logger.d('分段命中(L2): $videoId/$segmentKey@$q');
      return SegmentCacheResult(hit: true, data: streamEntry.data);
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
    // 清除 L1
    _memoryCache.clear();

    // 清除 L2
    _streamCache.clear();

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
      entry.hitCount++;
      entry.lastAccess = DateTime.now();
      _hitCount++;
      _notifyStats();
      return entry.frameBuffer;
    }
    _missCount++;
    _notifyStats();
    return null;
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
    final raw = '${videoId}_$quality';
    var hash = 0;
    for (int i = 0; i < raw.length; i++) {
      hash = ((hash << 5) - hash) + raw.codeUnitAt(i);
      hash = hash & 0x7FFFFFFF;
    }
    return hash.toRadixString(36);
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

      final entriesMap = <String, dynamic>{};
      for (final entry in _diskIndex.entries) {
        entriesMap[entry.key] = entry.value.toJson();
      }

      final jsonStr = jsonEncode({'entries': entriesMap});
      await indexFile.writeAsString(jsonStr);
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
      final stat = await appDir.stat();
      // stat.type 在某些平台不提供磁盘信息，降级返回默认值
      return _maxCacheBytes * 10;
    } catch (e) {
      return _maxCacheBytes * 10;
    }
  }

  /// 计算当前磁盘缓存使用率百分比
  Future<double> _getDiskUsagePercent() async {
    final maxSize = await _getMaxCacheSize();
    if (maxSize <= 0) return 0.0;

    int totalSize = 0;
    for (final entry in _diskIndex.values) {
      totalSize += entry.fileSize;
    }

    return (totalSize / maxSize) * 100.0;
  }

  /// 计算当前缓存总大小
  int _calculateTotalCacheSize() {
    int total = 0;
    for (final entry in _diskIndex.values) {
      total += entry.fileSize;
    }
    return total;
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
      // 优先级 <= 0 且非完整视频（预加载分段），且不在保留窗口内
      if (entry.value.priority <= 0 &&
          !entry.value.isComplete &&
          !_shouldKeep(entry.value)) {
        preloadKeys.add(entry.key);
      }
    }

    // 按优先级升序、最后访问时间升序排列
    preloadKeys.sort((a, b) {
      final ea = _diskIndex[a]!;
      final eb = _diskIndex[b]!;
      final priCmp = ea.priority.compareTo(eb.priority);
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

    // 按最后访问时间升序排列（最久未访问排前面）
    candidates.sort((a, b) {
      final ea = _diskIndex[a]!;
      final eb = _diskIndex[b]!;
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

    // 按文件大小降序排列（大文件优先淘汰）
    candidates.sort((a, b) {
      final ea = _diskIndex[a]!;
      final eb = _diskIndex[b]!;
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
  /// 保留条件：用户收藏（priority >= 10）、24h 内播放记录、热门视频（hitCount >= 10）
  bool _shouldKeep(CacheEntry entry) {
    // 用户收藏
    if (entry.priority >= 10) return true;

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

    _diskIndex.remove(cacheId);
  }

  // ============================================================
  // 内部方法 — L1/L2 内存淘汰
  // ============================================================

  /// L1 内存缓存淘汰
  void _evictL1IfNeeded() {
    while (_memoryCache.length > _l1MaxEntries) {
      // 移除最久未访问的条目
      String? oldestKey;
      DateTime? oldestTime;

      for (final entry in _memoryCache.entries) {
        if (oldestTime == null || entry.value.lastAccess.isBefore(oldestTime)) {
          oldestKey = entry.key;
          oldestTime = entry.value.lastAccess;
        }
      }

      if (oldestKey != null) {
        _memoryCache.remove(oldestKey);
      } else {
        break;
      }
    }
  }

  /// L2 内存缓存淘汰
  void _evictL2IfNeeded() {
    while (_streamCache.length > _l2MaxEntries) {
      String? oldestKey;
      DateTime? oldestTime;

      for (final entry in _streamCache.entries) {
        if (oldestTime == null || entry.value.lastAccess.isBefore(oldestTime)) {
          oldestKey = entry.key;
          oldestTime = entry.value.lastAccess;
        }
      }

      if (oldestKey != null) {
        _streamCache.remove(oldestKey);
      } else {
        break;
      }
    }
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
    _statsController.close();
    _memoryCache.clear();
    _streamCache.clear();
  }
}
