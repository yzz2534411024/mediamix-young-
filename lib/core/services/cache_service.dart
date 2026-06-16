import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:logger/logger.dart';
import '../utils/hash_utils.dart';

/// 缓存条目
class _CacheEntry {
  /// 缓存数据
  final Map<String, dynamic> data;

  /// 缓存时间戳
  final DateTime timestamp;

  _CacheEntry({required this.data, required this.timestamp});
}

/// 缓存服务（单例）— 提供接口数据的内存和本地文件缓存
class CacheService {
  static CacheService? _instance;

  static CacheService get instance => _instance ??= CacheService._();

  CacheService._();

  /// 内存缓存
  final Map<String, _CacheEntry> _memoryCache = {};

  final Logger _logger = Logger(printer: const SimplePrinter());

  /// 保存缓存到内存和本地文件
  Future<void> saveCache(String key, Map<String, dynamic> data) async {
    final cacheKey = hashKey(key);
    final entry = _CacheEntry(data: data, timestamp: DateTime.now());

    // 保存到内存
    _memoryCache[cacheKey] = entry;

    // 保存到本地文件
    try {
      final dir = await _getCacheDirectory();
      final file = File(p.join(dir, '$cacheKey.json'));
      final jsonStr = jsonEncode({
        'data': data,
        'timestamp': entry.timestamp.toIso8601String(),
      });
      await file.writeAsString(jsonStr);
      _logger.d('缓存已保存: $cacheKey');
    } catch (e) {
      _logger.w('本地缓存保存失败: $cacheKey, 错误: $e');
    }
  }

  /// 获取缓存，过期返回 null
  /// [key] 缓存键，[maxAge] 最大缓存时长，默认 30 分钟
  Future<Map<String, dynamic>?> getCache(
    String key, {
    Duration maxAge = const Duration(minutes: 30),
  }) async {
    final cacheKey = hashKey(key);

    // 先从内存缓存获取
    final memEntry = _memoryCache[cacheKey];
    if (memEntry != null) {
      if (DateTime.now().difference(memEntry.timestamp) < maxAge) {
        _logger.d('命中内存缓存: $cacheKey');
        return memEntry.data;
      } else {
        // 内存缓存过期，移除
        _memoryCache.remove(cacheKey);
      }
    }

    // 从本地文件获取
    try {
      final dir = await _getCacheDirectory();
      final file = File(p.join(dir, '$cacheKey.json'));
      if (!await file.exists()) {
        return null;
      }

      final jsonStr = await file.readAsString();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final timestamp = DateTime.parse(decoded['timestamp'] as String);
      final data = decoded['data'] as Map<String, dynamic>;

      if (DateTime.now().difference(timestamp) < maxAge) {
        // 本地缓存有效，回填内存缓存
        _memoryCache[cacheKey] = _CacheEntry(data: data, timestamp: timestamp);
        _logger.d('命中本地缓存: $cacheKey');
        return data;
      } else {
        // 本地缓存过期，删除文件
        await file.delete();
      }
    } catch (e) {
      _logger.w('读取本地缓存失败: $cacheKey, 错误: $e');
    }

    return null;
  }

  /// 清除指定缓存
  Future<void> clearCache(String key) async {
    final cacheKey = hashKey(key);

    // 清除内存缓存
    _memoryCache.remove(cacheKey);

    // 清除本地文件
    try {
      final dir = await _getCacheDirectory();
      final file = File(p.join(dir, '$cacheKey.json'));
      if (await file.exists()) {
        await file.delete();
      }
      _logger.d('缓存已清除: $cacheKey');
    } catch (e) {
      _logger.w('清除本地缓存失败: $cacheKey, 错误: $e');
    }
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    // 清除内存缓存
    _memoryCache.clear();

    // 清除本地缓存目录下的所有 JSON 文件
    try {
      final dir = await _getCacheDirectory();
      final cacheDir = Directory(dir);
      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            await entity.delete();
          }
        }
      }
      _logger.d('所有缓存已清除');
    } catch (e) {
      _logger.w('清除本地缓存失败: $e');
    }
  }

  /// 获取缓存目录路径
  Future<String> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = p.join(appDir.path, 'api_cache');
    // 确保目录存在
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return cacheDir;
  }

}
