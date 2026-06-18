import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/subtitle_service.dart';

void main() {
  group('SubtitleService', () {
    late SubtitleService service;

    setUp(() {
      service = SubtitleService();
    });

    group('parseSrt', () {
      test('解析单条字幕', () {
        const srt = '1\n00:00:01,000 --> 00:00:04,000\nHello World\n';
        final entries = service.parseSrt(srt);
        expect(entries.length, equals(1));
        expect(entries[0].start, equals(const Duration(seconds: 1)));
        expect(entries[0].end, equals(const Duration(seconds: 4)));
        expect(entries[0].text, equals('Hello World'));
      });

      test('解析多条字幕并按开始时间排序', () {
        const srt = '2\n00:00:04,000 --> 00:00:07,000\nSecond\n\n'
            '1\n00:00:01,000 --> 00:00:03,000\nFirst\n';
        final entries = service.parseSrt(srt);
        expect(entries.length, equals(2));
        expect(entries[0].text, equals('First'));
        expect(entries[1].text, equals('Second'));
      });

      test('支持点号作为毫秒分隔符', () {
        const srt = '1\n00:00:01.500 --> 00:00:04.750\nTest\n';
        final entries = service.parseSrt(srt);
        expect(entries[0].start, equals(const Duration(milliseconds: 1500)));
        expect(entries[0].end, equals(const Duration(milliseconds: 4750)));
      });

      test('字幕文本可包含多行', () {
        const srt = '1\n00:00:01,000 --> 00:00:05,000\nLine 1\nLine 2\n';
        final entries = service.parseSrt(srt);
        expect(entries[0].text, equals('Line 1\nLine 2'));
      });

      test('空内容返回空列表', () {
        expect(service.parseSrt(''), isEmpty);
      });

      test('无有效时间轴行返回空列表', () {
        const srt = '1\nNo timeline here\nSome text\n';
        expect(service.parseSrt(srt), isEmpty);
      });

      test('序号行可省略', () {
        // SRT 解析器查找 --> 来定位时间轴，序号不是必需的
        const srt = '00:00:02,000 --> 00:00:06,000\nNo index line\n';
        final entries = service.parseSrt(srt);
        expect(entries.length, equals(1));
        expect(entries[0].text, equals('No index line'));
      });

      test('空字幕文本被跳过', () {
        const srt = '1\n00:00:01,000 --> 00:00:04,000\n\n\n'  // empty text
            '2\n00:00:05,000 --> 00:00:08,000\nValid\n';
        final entries = service.parseSrt(srt);
        expect(entries.length, equals(1));
        expect(entries[0].text, equals('Valid'));
      });

      test('包含偏移量的时间戳', () {
        const srt = '1\n00:00:01,000 --> 00:00:04,000\nFirst\n\n'
            '2\n00:01:30,500 --> 00:02:00,000\nSecond\n\n'
            '3\n01:00:00,000 --> 01:30:00,000\nThird\n';
        final entries = service.parseSrt(srt);
        expect(entries.length, equals(3));
        expect(entries[1].start, equals(const Duration(minutes: 1, seconds: 30, milliseconds: 500)));
        expect(entries[2].start, equals(const Duration(hours: 1)));
      });

      test('\\r\\n 换行符兼容', () {
        const srt = '1\r\n00:00:01,000 --> 00:00:04,000\r\nWindows\r\n';
        final entries = service.parseSrt(srt);
        expect(entries.length, equals(1));
        expect(entries[0].text, equals('Windows'));
      });

      test('中文内容正常解析', () {
        const srt = '1\n00:00:01,000 --> 00:00:04,000\n你好世界\n\n'
            '2\n00:00:05,000 --> 00:00:10,000\n测试字幕\n';
        final entries = service.parseSrt(srt);
        expect(entries.length, equals(2));
        expect(entries[0].text, equals('你好世界'));
        expect(entries[1].text, equals('测试字幕'));
      });

      test('时间轴格式不正确时跳过该块', () {
        const srt = '1\n00:00:01,000 --> invalid\nBad time\n\n'
            '2\n00:00:05,000 --> 00:00:10,000\nGood\n';
        final entries = service.parseSrt(srt);
        expect(entries.length, equals(1));
        expect(entries[0].text, equals('Good'));
      });

      test('重复的 --> 分隔符', () {
        const srt = '1\n00:00:01,000 --> 00:00:03,000\ncontains --> arrow in text\n';
        final entries = service.parseSrt(srt);
        expect(entries.length, equals(1));
        expect(entries[0].text, equals('contains --> arrow in text'));
      });
    });

    group('getSubtitleAt — 二分查找', () {
      late List<SubtitleEntry> entries;

      setUp(() {
        entries = [
          const SubtitleEntry(
            start: Duration(seconds: 0),
            end: Duration(seconds: 2),
            text: 'First',
          ),
          const SubtitleEntry(
            start: Duration(seconds: 3),
            end: Duration(seconds: 6),
            text: 'Second',
          ),
          const SubtitleEntry(
            start: Duration(seconds: 7),
            end: Duration(seconds: 10),
            text: 'Third',
          ),
          const SubtitleEntry(
            start: Duration(seconds: 11),
            end: Duration(seconds: 15),
            text: 'Fourth',
          ),
        ];
      });

      test('返回当前位置对应的字幕', () {
        final result = service.getSubtitleAt(entries, const Duration(seconds: 4));
        expect(result?.text, equals('Second'));
      });

      test('返回边界位置的字幕', () {
        // Exactly at start
        final atStart = service.getSubtitleAt(entries, const Duration(seconds: 3));
        expect(atStart?.text, equals('Second'));

        // Exactly at end
        final atEnd = service.getSubtitleAt(entries, const Duration(seconds: 6));
        expect(atEnd?.text, equals('Second'));
      });

      test('不在任何字幕范围内返回 null', () {
        final result = service.getSubtitleAt(entries, const Duration(seconds: 2, milliseconds: 500));
        expect(result, isNull);
      });

      test('超出最后字幕返回 null', () {
        final result = service.getSubtitleAt(entries, const Duration(seconds: 20));
        expect(result, isNull);
      });

      test('第一条字幕之前返回 null', () {
        // First entry starts at 0, so position < 0 isn't possible.
        // But if first entry starts later:
        final lateEntries = [
          const SubtitleEntry(
            start: Duration(seconds: 5),
            end: Duration(seconds: 10),
            text: 'Late',
          ),
        ];
        final result = service.getSubtitleAt(lateEntries, const Duration(seconds: 1));
        expect(result, isNull);
      });

      test('空列表返回 null', () {
        final result = service.getSubtitleAt([], const Duration(seconds: 1));
        expect(result, isNull);
      });

      test('offset 偏移量正确作用', () {
        // offset = 2 means position is shifted forward by 2s
        final result = service.getSubtitleAt(
          entries,
          const Duration(seconds: 5),
          offset: 2,
        );
        // position 5 + offset 2 = 7, which is the start of "Third"
        expect(result?.text, equals('Third'));
      });

      test('负 offset 偏移量正确作用', () {
        final result = service.getSubtitleAt(
          entries,
          const Duration(seconds: 5),
          offset: -2,
        );
        // position 5 + offset (-2) = 3, which is the start of "Second"
        expect(result?.text, equals('Second'));
      });

      test('syncOffset 偏移量正确作用', () {
        final result = service.getSubtitleAt(
          entries,
          const Duration(seconds: 1),
          syncOffset: const Duration(seconds: 2),
        );
        // position 1 + syncOffset 2 = 3, "Second"
        expect(result?.text, equals('Second'));
      });
    });

    group('autoSyncOffset', () {
      test('返回音频时间戳与字幕起始时间差值的中位数', () {
        final entries = [
          const SubtitleEntry(
            start: Duration(seconds: 1, milliseconds: 100),
            end: Duration(seconds: 5),
            text: 'A',
          ),
          const SubtitleEntry(
            start: Duration(seconds: 5, milliseconds: 200),
            end: Duration(seconds: 10),
            text: 'B',
          ),
          const SubtitleEntry(
            start: Duration(seconds: 10, milliseconds: 300),
            end: Duration(seconds: 15),
            text: 'C',
          ),
        ];

        // Audio timestamps are slightly delayed relative to subtitles
        final audioTimestamps = [
          const Duration(seconds: 1, milliseconds: 0),
          const Duration(seconds: 5, milliseconds: 0),
          const Duration(seconds: 10, milliseconds: 0),
        ];

        final offset = service.autoSyncOffset(entries, audioTimestamps);
        // Offsets: 100ms, 200ms, 300ms → median = 200ms
        expect(offset, equals(const Duration(milliseconds: 200)));
      });

      test('空字幕条目返回当前偏移量', () {
        final original = service.syncOffset;
        final result = service.autoSyncOffset(
          [],
          [const Duration(seconds: 1)],
        );
        expect(result, equals(original));
      });

      test('空音频时间戳返回当前偏移量', () {
        final original = service.syncOffset;
        final result = service.autoSyncOffset(
          [const SubtitleEntry(
            start: Duration(seconds: 1),
            end: Duration(seconds: 5),
            text: 'A',
          )],
          [],
        );
        expect(result, equals(original));
      });

      test('计算结果更新全局 syncOffset', () {
        final entries = [
          const SubtitleEntry(
            start: Duration(seconds: 1),
            end: Duration(seconds: 5),
            text: 'A',
          ),
        ];
        final audioTimestamps = [const Duration(seconds: 1, milliseconds: 500)];

        service.autoSyncOffset(entries, audioTimestamps);
        // offset = 1s - 1.5s = -500ms
        expect(service.syncOffset, equals(const Duration(milliseconds: -500)));
      });

      test('setSyncOffset 手动设置偏移量', () {
        service.setSyncOffset(const Duration(milliseconds: 300));
        expect(service.syncOffset, equals(const Duration(milliseconds: 300)));
      });
    });
  });
}
