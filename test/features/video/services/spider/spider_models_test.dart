import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/services/spider/spider_models.dart';

void main() {
  group('SpiderPlayResult', () {
    test('needsParse returns true when parse is "1"', () {
      const result = SpiderPlayResult(url: 'https://example.com', parse: '1');
      expect(result.needsParse, true);
    });

    test('needsParse returns false when parse is "0"', () {
      const result = SpiderPlayResult(url: 'https://example.com', parse: '0');
      expect(result.needsParse, false);
    });

    test('needsParse returns false when parse is null', () {
      const result = SpiderPlayResult(url: 'https://example.com');
      expect(result.needsParse, false);
    });
  });

  group('SpiderHomeResult', () {
    test('defaults are empty', () {
      const result = SpiderHomeResult();
      expect(result.categories, isEmpty);
      expect(result.recommend, isEmpty);
      expect(result.classList, isNull);
    });
  });

  group('SpiderListResult', () {
    test('defaults are correct', () {
      const result = SpiderListResult();
      expect(result.list, isEmpty);
      expect(result.page, 1);
      expect(result.pageCount, 1);
      expect(result.total, 0);
    });
  });
}
