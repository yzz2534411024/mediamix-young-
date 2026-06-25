import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/tvbox_image_decoder.dart';

void main() {
  group('TvBoxImageDecoder', () {
    test('解码 JPEG 伪装格式（饭太硬格式）', () {
      // 构造模拟的 JPEG 伪装数据
      // 格式: [JPEG头 FF D8 ... FF D9] [标识]**[Base64 JSON]
      final jpegHeader = <int>[0xFF, 0xD8, 0xFF, 0xE0]; // JPEG 魔数
      final jpegBody = List<int>.filled(100, 0x00); // 模拟 JPEG 数据
      final jpegEnd = <int>[0xFF, 0xD9]; // JPEG 结束标记
      final marker = utf8.encode('htviBdCp'); // 8字符标识
      final separator = utf8.encode('**'); // 分隔符
      final json = '{"spider":"http://example.com/spider.jar","sites":[{"key":"test","name":"测试","type":3,"api":"csp_Test"}]}';
      final b64 = base64Encode(utf8.encode(json));

      final bytes = <int>[
        ...jpegHeader,
        ...jpegBody,
        ...jpegEnd,
        ...marker,
        ...separator,
        ...utf8.encode(b64),
      ];

      final result = TvBoxImageDecoder.decode(bytes);
      expect(result, isNotNull);
      expect(result!['spider'], 'http://example.com/spider.jar');
      expect(result['sites'], isA<List>());
      expect((result['sites'] as List).length, 1);
    });

    test('检测 JPEG 伪装格式', () {
      final jpegBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
      expect(TvBoxImageDecoder.isJpegDisguise(jpegBytes), isTrue);

      final nonJpegBytes = <int>[0x7B, 0x22, 0x6B]; // {"k...
      expect(TvBoxImageDecoder.isJpegDisguise(nonJpegBytes), isFalse);
    });

    test('解码纯 JSON 文本', () {
      final json = '{"sites":[{"key":"test","name":"测试","type":0,"api":"http://api.com"}]}';
      final bytes = utf8.encode(json);

      final result = TvBoxImageDecoder.decode(bytes);
      expect(result, isNotNull);
      expect(result!['sites'], isA<List>());
    });

    test('解码纯 Base64 编码的 JSON', () {
      final json = '{"sites":[{"key":"test"}]}';
      final b64 = base64Encode(utf8.encode(json));
      final bytes = utf8.encode(b64);

      final result = TvBoxImageDecoder.decode(bytes);
      expect(result, isNotNull);
      expect(result!['sites'], isA<List>());
    });

    test('空数据返回 null', () {
      expect(TvBoxImageDecoder.decode([]), isNull);
    });

    test('无效数据返回 null', () {
      final bytes = utf8.encode('这不是有效的数据');
      expect(TvBoxImageDecoder.decode(bytes), isNull);
    });

    test('解码含 JavaScript 注释的 JSON', () {
      final json = '{\n'
          '"spider":"http://example.com/spider.jar",\n'
          '"sites":[{"key":"test","name":"测试","type":3,"api":"csp_Test"}],\n'
          '// 这是一条注释\n'
          '"lives":[]\n'
          '}';
      final bytes = utf8.encode(json);

      final result = TvBoxImageDecoder.decode(bytes);
      expect(result, isNotNull);
      expect(result!['spider'], 'http://example.com/spider.jar');
      expect(result['sites'], isA<List>());
      expect(result['lives'], isA<List>());
    });
  });
}
