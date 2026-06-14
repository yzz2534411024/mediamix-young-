import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

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

/// 字幕服务 — 负责加载和解析 SRT 字幕
class SubtitleService {
  final Dio _dio;
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  SubtitleService({Dio? dio}) : _dio = dio ?? Dio();

  /// 从 URL 下载 SRT 文件并解析
  Future<List<SubtitleEntry>> loadFromUrl(String url) async {
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

  /// 根据播放位置获取当前字幕
  /// [entries] 字幕列表，[position] 当前播放位置，[offset] 时间偏移（秒）
  SubtitleEntry? getSubtitleAt(
    List<SubtitleEntry> entries,
    Duration position, {
    double offset = 0,
  }) {
    final adjustedPosition = position + Duration(milliseconds: (offset * 1000).round());

    // 由于字幕列表已按开始时间排序，可以使用二分查找优化
    for (final entry in entries) {
      if (adjustedPosition >= entry.start && adjustedPosition <= entry.end) {
        return entry;
      }
      // 如果已经超过当前字幕的结束时间且还没到下一条，继续
      if (adjustedPosition < entry.start) {
        // 已经过去了空白区间
        return null;
      }
    }
    return null;
  }
}

/// 字幕叠加 Widget — 在视频播放器底部居中显示字幕
class SubtitleOverlay extends StatelessWidget {
  /// 当前字幕文本
  final String? text;

  /// 文字样式
  final TextStyle? style;

  /// 背景颜色
  final Color backgroundColor;

  /// 内边距
  final EdgeInsets padding;

  /// 圆角
  final BorderRadius borderRadius;

  const SubtitleOverlay({
    super.key,
    required this.text,
    this.style,
    this.backgroundColor = const Color(0xB3000000), // 70% 透明黑色
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    if (text == null || text!.isEmpty) {
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
            text!,
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
