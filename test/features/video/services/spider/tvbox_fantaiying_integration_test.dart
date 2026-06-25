import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/tvbox_image_decoder.dart';

void main() {
  group('TvBoxImageDecoder 饭太硬真实数据测试', () {
    test('解码 test_fantaiying.bin', () {
      final file = File('test_fantaiying.bin');
      expect(file.existsSync(), isTrue,
          reason: '需要把 test_fantaiying.bin 放在项目根目录');

      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(1000));

      final result = TvBoxImageDecoder.decode(bytes);
      expect(result, isNotNull,
          reason: 'TvBoxImageDecoder 应该能解码饭太硬数据');

      expect(result!['sites'], isA<List>());
      final sites = result['sites'] as List;
      expect(sites.length, greaterThan(0));

      // 验证第一个站点字段
      final first = sites.first as Map<String, dynamic>;
      expect(first['key'], isNotNull);
      expect(first['name'], isNotNull);
      expect(first['api'], isNotNull);

      // 验证 spider 字段
      expect(result['spider'], isA<String>());
    });
  });
}
