import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/core/utils/hash_utils.dart';

void main() {
  group('hashKey', () {
    test('空字符串返回 SHA-256 前 16 位', () {
      // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb924...
      expect(hashKey(''), equals('e3b0c44298fc1c14'));
    });

    test('相同输入产生相同输出', () {
      expect(hashKey('hello'), equals(hashKey('hello')));
    });

    test('不同输入产生不同输出', () {
      expect(hashKey('hello'), isNot(equals(hashKey('world'))));
    });

    test('返回值为 16 位十六进制字符串', () {
      final result = hashKey('test_key_123');
      expect(result.length, equals(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(result), isTrue);
    });

    test('长字符串不会崩溃', () {
      final longKey = 'a' * 10000;
      final result = hashKey(longKey);
      expect(result.length, equals(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(result), isTrue);
    });

    test('中文输入正常处理', () {
      final result = hashKey('视频缓存key_测试');
      expect(result.length, equals(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(result), isTrue);
    });

    test('特殊字符输入正常处理', () {
      final result = hashKey('!@#\$%^&*()_+-=[]{}|;:\'",.<>?/~`');
      expect(result.length, equals(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(result), isTrue);
    });

    test('单字符输入产生合法结果', () {
      final result = hashKey('a');
      expect(result.length, equals(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(result), isTrue);
    });

    test('仅数字输入', () {
      final result = hashKey('12345');
      expect(result.length, equals(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(result), isTrue);
    });

    test('碰撞概率极低 — 1000 个不同输入无碰撞', () {
      final results = <String>{};
      for (var i = 0; i < 1000; i++) {
        results.add(hashKey('key_$i'));
      }
      expect(results.length, equals(1000));
    });
  });
}
