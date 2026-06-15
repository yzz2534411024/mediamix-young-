import 'dart:collection';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../../../core/network/proxy_config_service.dart';

/// 字幕条目
class SubtitleEntry {
  /// 开始时间
  final Duration start;

  /// 结束时间
  final Duration end;

  /// 字幕文本（可能包含多行）
  final String text;

  const SubtitleEntry({
    required this.start,
    required this.end,
    required this.text,
  });

  @override
  String toString() => 'SubtitleEntry($start -> $end: $text)';
}

/// 字幕轨道 — 支持多字幕轨道
class SubtitleTrack {
  /// 轨道标签（如"简体中文"）
  final String label;

  /// 语言代码（如"zh-CN"、"en-US"）
  final String language;

  /// 该轨道的字幕条目列表
  final List<SubtitleEntry> entries;

  const SubtitleTrack({
    required this.label,
    required this.language,
    required this.entries,
  });

  @override
  String toString() => 'SubtitleTrack($label, $language, ${entries.length}条)';
}

/// LRU 字幕缓存 — 最大容量 20 条，避免重复解析
class _SubtitleLRUCache {
  /// 最大缓存条目数
  final int maxEntries;

  /// 有序 Map，按访问顺序排列（最新访问在末尾）
  final LinkedHashMap<String, List<SubtitleEntry>> _cache = LinkedHashMap();

  _SubtitleLRUCache({this.maxEntries = 20});

  /// 获取缓存，命中时将条目移到末尾（标记为最近使用）
  List<SubtitleEntry>? get(String key) {
    if (!_cache.containsKey(key)) return null;
    // 移到末尾，标记为最近使用
    final value = _cache.remove(key)!;
    _cache[key] = value;
    return value;
  }

  /// 写入缓存，超容量时淘汰最久未使用的条目
  void put(String key, List<SubtitleEntry> entries) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxEntries) {
      // 淘汰最久未使用（即第一个）
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = entries;
  }

  /// 是否包含指定 key
  bool containsKey(String key) => _cache.containsKey(key);

  /// 当前缓存大小
  int get length => _cache.length;

  /// 清空缓存
  void clear() => _cache.clear();
}

/// 字幕服务 — 负责加载和解析 SRT 字幕
class SubtitleService {
  final Dio _dio;
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  /// LRU 字幕缓存，最大 20 条
  final _SubtitleLRUCache _subtitleCache = _SubtitleLRUCache(maxEntries: 20);

  /// 全局时间同步偏移量
  Duration _syncOffset = Duration.zero;

  /// 获取当前同步偏移量
  Duration get syncOffset => _syncOffset;

  SubtitleService({Dio? dio})
      : _dio = dio ?? _createDefaultDio();

  static Dio _createDefaultDio() {
    final d = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    (d.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      try { ProxyConfigService.instance.configureHttpClient(client); } catch (_) {}
      return client;
    };
    return d;
  }

  /// 从 URL 下载 SRT 文件并解析（带缓存）
  Future<List<SubtitleEntry>> loadFromUrl(String url) async {
    // 先查缓存
    final cached = _subtitleCache.get(url);
    if (cached != null) {
      _logger.d('命中字幕缓存: $url');
      return cached;
    }
    try {
      _logger.d('开始下载字幕: $url');
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final content = response.data;
      if (content == null || content.isEmpty) {
        _logger.w('字幕内容为空: $url');
        return [];
      }
      final entries = parseSrt(content);
      _logger.d('字幕解析完成，共 ${entries.length} 条: $url');
      // 写入缓存
      _subtitleCache.put(url, entries);
      return entries;
    } catch (e) {
      _logger.e('下载字幕失败: $url, 错误: $e');
      rethrow;
    }
  }

  /// 从本地文件读取 SRT 并解析
  Future<List<SubtitleEntry>> loadFromFile(String filePath) async {
    try {
      _logger.d('开始读取本地字幕: $filePath');
      final file = File(filePath);
      if (!await file.exists()) {
        _logger.w('字幕文件不存在: $filePath');
        return [];
      }
      final content = await file.readAsString();
      if (content.isEmpty) {
        _logger.w('字幕文件内容为空: $filePath');
        return [];
      }
      final entries = parseSrt(content);
      _logger.d('本地字幕解析完成，共 ${entries.length} 条: $filePath');
      return entries;
    } catch (e) {
      _logger.e('读取本地字幕失败: $filePath, 错误: $e');
      rethrow;
    }
  }

  /// 预加载多个字幕文件 — 并行下载并解析，结果写入缓存
  Future<void> preloadSubtitles(List<String> urls) async {
    _logger.d('开始预加载 ${urls.length} 个字幕文件');
    await Future.wait(
      urls.map((url) async {
        try {
          await loadFromUrl(url);
        } catch (e) {
          _logger.w('预加载字幕失败: $url, 错误: $e');
          // 预加载失败不中断其他任务
        }
      }),
    );
    _logger.d('预加载完成，缓存大小: ${_subtitleCache.length}');
  }

  /// 加载多轨道字幕 — 根据 URL 和轨道信息加载，支持零延迟切换
  Future<List<SubtitleTrack>> loadMultiTrackFromUrl(
    List<({String url, String label, String language})> trackInfos,
  ) async {
    _logger.d('开始加载 ${trackInfos.length} 条字幕轨道');
    final results = await Future.wait(
      trackInfos.map((info) async {
        try {
          final entries = await loadFromUrl(info.url);
          return SubtitleTrack(
            label: info.label,
            language: info.language,
            entries: entries,
          );
        } catch (e) {
          _logger.e('加载轨道失败: ${info.label}(${info.language}), 错误: $e');
          return SubtitleTrack(
            label: info.label,
            language: info.language,
            entries: [],
          );
        }
      }),
    );
    _logger.d('多轨道加载完成，共 ${results.length} 条轨道');
    return results;
  }

  /// 解析 SRT 格式文本
  /// SRT 格式：序号 → 时间轴(00:00:01,000 --> 00:00:04,000) → 字幕文本(可多行) → 空行
  List<SubtitleEntry> parseSrt(String content) {
    final entries = <SubtitleEntry>[];

    // 按空行分割字幕块
    final blocks = content.split(RegExp(r'\r?\n\s*\r?\n'));

    for (final block in blocks) {
      final lines = block.trim().split(RegExp(r'\r?\n'));
      if (lines.length < 2) continue;

      // 查找时间轴行（包含 --> 的行）
      int timelineIndex = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timelineIndex = i;
          break;
        }
      }

      if (timelineIndex < 0) continue;

      // 解析时间轴
      final timelineLine = lines[timelineIndex];
      final timeParts = timelineLine.split('-->');
      if (timeParts.length != 2) continue;

      final start = _parseTimestamp(timeParts[0].trim());
      final end = _parseTimestamp(timeParts[1].trim());

      if (start == null || end == null) continue;

      // 时间轴之后的所有行作为字幕文本
      final textLines = lines.sublist(timelineIndex + 1);
      final text = textLines.join('\n').trim();

      if (text.isEmpty) continue;

      entries.add(SubtitleEntry(start: start, end: end, text: text));
    }

    // 按开始时间排序
    entries.sort((a, b) => a.start.compareTo(b.start));

    return entries;
  }

  /// 解析 SRT 时间戳，格式：00:00:01,000 或 00:00:01.000
  Duration? _parseTimestamp(String timestamp) {
    // 支持逗号和点号作为毫秒分隔符
    final normalized = timestamp.replaceAll(',', '.');
    final regex = RegExp(r'(\d{2}):(\d{2}):(\d{2})[.](\d{3})');
    final match = regex.firstMatch(normalized);

    if (match == null) return null;

    final hours = int.tryParse(match.group(1)!) ?? 0;
    final minutes = int.tryParse(match.group(2)!) ?? 0;
    final seconds = int.tryParse(match.group(3)!) ?? 0;
    final milliseconds = int.tryParse(match.group(4)!) ?? 0;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  /// 根据播放位置获取当前字幕（二分查找优化，O(logN)）
  /// [entries] 字幕列表（已按开始时间排序），[position] 当前播放位置
  /// [offset] 时间偏移（秒），[syncOffset] PTS 同步偏移
  SubtitleEntry? getSubtitleAt(
    List<SubtitleEntry> entries,
    Duration position, {
    double offset = 0,
    Duration? syncOffset,
  }) {
    if (entries.isEmpty) return null;

    // 应用时间偏移和 PTS 同步偏移
    final effectiveSyncOffset = syncOffset ?? _syncOffset;
    final adjustedPosition = position +
        Duration(milliseconds: (offset * 1000).round()) +
        effectiveSyncOffset;

    // 二分查找：找到最后一个 start <= adjustedPosition 的条目
    int left = 0;
    int right = entries.length - 1;
    int result = -1;

    while (left <= right) {
      final mid = left + (right - left) ~/ 2;
      if (entries[mid].start <= adjustedPosition) {
        result = mid;
        left = mid + 1; // 继续向右查找更晚的匹配
      } else {
        right = mid - 1;
      }
    }

    // 检查找到的条目是否覆盖当前时间
    if (result >= 0 && adjustedPosition <= entries[result].end) {
      return entries[result];
    }

    return null;
  }

  /// 自动计算 PTS 同步偏移量
  /// [entries] 字幕条目列表，[audioTimestamps] 音频时间戳列表（与字幕对应的参考点）
  /// 返回计算出的最佳偏移量，并自动应用到全局 syncOffset
  ///
  /// 算法：计算每个音频时间戳与最近字幕起始时间的差值，取中位数作为偏移量
  Duration autoSyncOffset(
    List<SubtitleEntry> entries,
    List<Duration> audioTimestamps,
  ) {
    if (entries.isEmpty || audioTimestamps.isEmpty) {
      _logger.w('字幕或音频时间戳为空，无法计算同步偏移');
      return _syncOffset;
    }

    final offsets = <Duration>[];

    for (final audioTs in audioTimestamps) {
      // 对每个音频时间戳，找到最近的字幕起始时间
      Duration? nearestStart;
      Duration? minDiff;

      for (final entry in entries) {
        final diff = (entry.start - audioTs).abs();
        if (minDiff == null || diff < minDiff) {
          minDiff = diff;
          nearestStart = entry.start;
        }
      }

      if (nearestStart != null) {
        // 偏移 = 字幕时间 - 音频时间
        offsets.add(nearestStart - audioTs);
      }
    }

    if (offsets.isEmpty) {
      _logger.w('未能计算有效偏移量');
      return _syncOffset;
    }

    // 取中位数作为最佳偏移量，避免极端值干扰
    offsets.sort((a, b) => a.compareTo(b));
    final medianOffset = offsets[offsets.length ~/ 2];

    _syncOffset = medianOffset;
    _logger.d('自动同步偏移计算完成: ${medianOffset.inMilliseconds}ms');
    return _syncOffset;
  }

  /// 设置全局 PTS 同步偏移量
  void setSyncOffset(Duration offset) {
    _syncOffset = offset;
    _logger.d('手动设置同步偏移: ${offset.inMilliseconds}ms');
  }

  /// 清空字幕缓存
  void clearCache() {
    _subtitleCache.clear();
    _logger.d('字幕缓存已清空');
  }
}

/// 字幕叠加 Widget — 在视频播放器底部居中显示字幕
class SubtitleOverlay extends StatelessWidget {
  /// 当前字幕文本（单轨道模式，向后兼容）
  final String? text;

  /// 文字样式
  final TextStyle? style;

  /// 背景颜色
  final Color backgroundColor;

  /// 内边距
  final EdgeInsets padding;

  /// 圆角
  final BorderRadius borderRadius;

  /// 多字幕轨道列表（多轨道模式）
  final List<SubtitleTrack>? tracks;

  /// 当前激活的轨道索引（多轨道模式下使用）
  final int currentTrackIndex;

  /// 当前播放位置（多轨道模式下使用，用于自动查找字幕）
  final Duration? position;

  /// PTS 同步偏移量（多轨道模式下使用）
  final Duration syncOffset;

  /// 时间偏移秒数（多轨道模式下使用）
  final double timeOffset;

  /// 字幕服务实例（多轨道模式下使用，用于二分查找）
  final SubtitleService? subtitleService;

  const SubtitleOverlay({
    super.key,
    required this.text,
    this.style,
    this.backgroundColor = const Color(0xB3000000), // 70% 透明黑色
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    // 多轨道参数，均有默认值，保持向后兼容
    this.tracks,
    this.currentTrackIndex = 0,
    this.position,
    this.syncOffset = Duration.zero,
    this.timeOffset = 0,
    this.subtitleService,
  });

  /// 获取当前应显示的字幕文本
  String? _getCurrentText() {
    // 多轨道模式：从轨道列表中查找
    if (tracks != null && tracks!.isNotEmpty && subtitleService != null && position != null) {
      final trackIndex = currentTrackIndex.clamp(0, tracks!.length - 1);
      final track = tracks![trackIndex];
      final entry = subtitleService!.getSubtitleAt(
        track.entries,
        position!,
        offset: timeOffset,
        syncOffset: syncOffset,
      );
      return entry?.text;
    }
    // 单轨道模式：直接使用 text
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _getCurrentText();

    if (displayText == null || displayText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 32,
      child: Center(
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
          ),
          child: Text(
            displayText,
            style: style ??
                const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 1.4,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
