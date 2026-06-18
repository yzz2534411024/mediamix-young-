import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/core/utils/hash_utils.dart';

void main() {
  group('hashKey', () {
    test('空字符串返回 "0"', () {
      expect(hashKey(''), equals('0'));
    });

    test('相同输入产生相同输出', () {
      expect(hashKey('hello'), equals(hashKey('hello')));
    });

    test('不同输入产生不同输出', () {
      expect(hashKey('hello'), isNot(equals(hashKey('world'))));
    });

    test('返回值为合法的36进制字符串', () {
      final result = hashKey('test_key_123');
      expect(int.tryParse(result, radix: 36), isNotNull);
    });

    test('返回值为非负', () {
      final result = hashKey('anything');
      expect(int.parse(result, radix: 36), greaterThanOrEqualTo(0));
    });

    test('长字符串不会溢出', () {
      final longKey = 'a' * 10000;
      final result = hashKey(longKey);
      expect(int.tryParse(result, radix: 36), isNotNull);
    });

    test('中文输入正常处理', () {
      final result = hashKey('视频缓存key_测试');
      expect(int.tryParse(result, radix: 36), isNotNull);
    });

    test('特殊字符输入正常处理', () {
      final result = hashKey('!@#\$%^&*()_+-=[]{}|;:\'",.<>?/~`');
      expect(int.tryParse(result, radix: 36), isNotNull);
    });

    test('单字符输入产生合法结果', () {
      final result = hashKey('a');
      expect(int.tryParse(result, radix: 36), isNotNull);
      expect(result.length, greaterThan(0));
    });

    test('仅数字输入', () {
      final result = hashKey('12345');
      expect(int.tryParse(result, radix: 36), isNotNull);
    });
  });
}
