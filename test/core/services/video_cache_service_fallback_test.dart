// 跨清晰度缓存查找功能单元测试
//
// 测试覆盖：
// 1. CacheResolveResult 数据类构造与字段
// 2. 清晰度优先级逻辑（超清 > 高清 > 标清 > 流畅）
// 3. 跨清晰度查找概念验证
//
// 注意：VideoCacheService 是单例且依赖文件系统，
// 本文件聚焦于数据类和逻辑概念的测试，不涉及磁盘 I/O。

import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/core/engines/engine_interfaces.dart';

void main() {
  // ============================================================
  // 1. CacheResolveResult 数据类测试
  // ============================================================
  group('CacheResolveResult 数据类', () {
    test('构造 — 所有字段赋值', () {
      const result = CacheResolveResult(
        url: '/cache/video_001_超清.mp4',
        isUsingCache: true,
        fallbackQuality: '高清',
      );
      expect(result.url, equals('/cache/video_001_超清.mp4'));
      expect(result.isUsingCache, isTrue);
      expect(result.fallbackQuality, equals('高清'));
    });

    test('构造 — fallbackQuality 为 null（精确命中）', () {
      const result = CacheResolveResult(
        url: '/cache/video_001_超清.mp4',
        isUsingCache: true,
      );
      expect(result.url, equals('/cache/video_001_超清.mp4'));
      expect(result.isUsingCache, isTrue);
      expect(result.fallbackQuality, isNull);
    });

    test('构造 — 未命中场景', () {
      const result = CacheResolveResult(
        url: 'https://example.com/proxy/video_001',
        isUsingCache: false,
      );
      expect(result.url, equals('https://example.com/proxy/video_001'));
      expect(result.isUsingCache, isFalse);
      expect(result.fallbackQuality, isNull);
    });

    test('url 字段为非空字符串', () {
      const result = CacheResolveResult(
        url: '/cache/test.mp4',
        isUsingCache: true,
      );
      expect(result.url, isNotEmpty);
    });

    test('isUsingCache 为 true 时表示使用缓存', () {
      const cached = CacheResolveResult(
        url: '/cache/cached.mp4',
        isUsingCache: true,
      );
      const notCached = CacheResolveResult(
        url: 'https://example.com/video.mp4',
        isUsingCache: false,
      );
      expect(cached.isUsingCache, isTrue);
      expect(notCached.isUsingCache, isFalse);
    });

    test('fallbackQuality 可为任意字符串', () {
      const result = CacheResolveResult(
        url: '/cache/video.mp4',
        isUsingCache: true,
        fallbackQuality: '标清',
      );
      expect(result.fallbackQuality, equals('标清'));
    });

    test('const 构造函数允许编译期常量', () {
      // 验证 CacheResolveResult 可作为编译期常量使用
      const results = [
        CacheResolveResult(url: '/a.mp4', isUsingCache: true),
        CacheResolveResult(url: '/b.mp4', isUsingCache: false, fallbackQuality: '高清'),
      ];
      expect(results.length, equals(2));
      expect(results[0].isUsingCache, isTrue);
      expect(results[1].fallbackQuality, equals('高清'));
    });
  });

  // ============================================================
  // 2. 清晰度优先级逻辑测试
  // ============================================================
  group('清晰度优先级逻辑', () {
    /// 清晰度优先级顺序：超清 > 高清 > 标清 > 流畅
    /// 与 VideoCacheService.getAnyQualityCachePath 中的 qualityPriority 一致
    const qualityPriority = ['超清', '高清', '标清', '流畅'];

    test('优先级顺序正确 — 超清 > 高清 > 标清 > 流畅', () {
      expect(qualityPriority.indexOf('超清'), equals(0));
      expect(qualityPriority.indexOf('高清'), equals(1));
      expect(qualityPriority.indexOf('标清'), equals(2));
      expect(qualityPriority.indexOf('流畅'), equals(3));
    });

    test('超清优先级最高', () {
      for (final q in ['高清', '标清', '流畅']) {
        expect(
          qualityPriority.indexOf('超清') < qualityPriority.indexOf(q),
          isTrue,
          reason: '超清应优先于$q',
        );
      }
    });

    test('流畅优先级最低', () {
      for (final q in ['超清', '高清', '标清']) {
        expect(
          qualityPriority.indexOf('流畅') > qualityPriority.indexOf(q),
          isTrue,
          reason: '流畅应排在$q之后',
        );
      }
    });

    test('按优先级遍历时，先找到高优先级清晰度', () {
      // 模拟 getAnyQualityCachePath 的查找逻辑：
      // 跳过 preferredQuality，按优先级遍历
      const preferredQuality = '超清';
      final candidates = qualityPriority
          .where((q) => q != preferredQuality)
          .toList();

      expect(candidates, equals(['高清', '标清', '流畅']));
    });

    test('请求高清时降级查找顺序为 超清 > 标清 > 流畅', () {
      const preferredQuality = '高清';
      final candidates = qualityPriority
          .where((q) => q != preferredQuality)
          .toList();

      expect(candidates, equals(['超清', '标清', '流畅']));
    });

    test('请求标清时降级查找顺序为 超清 > 高清 > 流畅', () {
      const preferredQuality = '标清';
      final candidates = qualityPriority
          .where((q) => q != preferredQuality)
          .toList();

      expect(candidates, equals(['超清', '高清', '流畅']));
    });

    test('请求流畅时降级查找顺序为 超清 > 高清 > 标清', () {
      const preferredQuality = '流畅';
      final candidates = qualityPriority
          .where((q) => q != preferredQuality)
          .toList();

      expect(candidates, equals(['超清', '高清', '标清']));
    });

    test('模拟降级查找 — 第一个可用清晰度被选中', () {
      // 假设缓存中只有「标清」，请求「超清」
      const availableQualities = {'标清': '/cache/v_标清.mp4'};
      const preferredQuality = '超清';

      String? foundQuality;
      String? foundPath;

      // 先查精确匹配
      if (availableQualities.containsKey(preferredQuality)) {
        foundQuality = preferredQuality;
        foundPath = availableQualities[preferredQuality];
      }

      // 再按优先级降级查找
      if (foundQuality == null) {
        for (final q in qualityPriority) {
          if (q == preferredQuality) continue;
          if (availableQualities.containsKey(q)) {
            foundQuality = q;
            foundPath = availableQualities[q];
            break;
          }
        }
      }

      expect(foundQuality, equals('标清'));
      expect(foundPath, equals('/cache/v_标清.mp4'));
    });

    test('模拟降级查找 — 多个清晰度可用时选最高优先级', () {
      // 假设缓存中有「标清」和「高清」，请求「超清」
      const availableQualities = {
        '标清': '/cache/v_标清.mp4',
        '高清': '/cache/v_高清.mp4',
      };
      const preferredQuality = '超清';

      String? foundQuality;

      // 按优先级遍历
      for (final q in qualityPriority) {
        if (q == preferredQuality) continue;
        if (availableQualities.containsKey(q)) {
          foundQuality = q;
          break;
        }
      }

      // 高清优先级高于标清，应选中高清
      expect(foundQuality, equals('高清'));
    });

    test('模拟降级查找 — 精确命中时不走降级', () {
      const availableQualities = {
        '超清': '/cache/v_超清.mp4',
        '高清': '/cache/v_高清.mp4',
      };
      const preferredQuality = '超清';

      String? foundQuality;
      String? foundPath;
      bool isExactMatch = false;

      // 先查精确匹配
      if (availableQualities.containsKey(preferredQuality)) {
        foundQuality = preferredQuality;
        foundPath = availableQualities[preferredQuality];
        isExactMatch = true;
      }

      expect(isExactMatch, isTrue);
      expect(foundQuality, equals('超清'));
      expect(foundPath, equals('/cache/v_超清.mp4'));
    });
  });

  // ============================================================
  // 3. 跨清晰度查找概念测试
  // ============================================================
  group('跨清晰度查找概念', () {
    test('精确命中 — fallbackQuality 为 null', () {
      // 当请求的清晰度恰好有缓存时，fallbackQuality 应为 null
      const result = CacheResolveResult(
        url: '/cache/video_001_超清.mp4',
        isUsingCache: true,
      );
      expect(result.isUsingCache, isTrue);
      expect(result.fallbackQuality, isNull);
    });

    test('降级命中 — fallbackQuality 为降级清晰度', () {
      // 请求超清但只有标清缓存，fallbackQuality 应为 '标清'
      const result = CacheResolveResult(
        url: '/cache/video_001_标清.mp4',
        isUsingCache: true,
        fallbackQuality: '标清',
      );
      expect(result.isUsingCache, isTrue);
      expect(result.fallbackQuality, equals('标清'));
      expect(result.url, contains('标清'));
    });

    test('未命中 — isUsingCache 为 false 且 fallbackQuality 为 null', () {
      // 任何清晰度都没有缓存，走网络播放
      const result = CacheResolveResult(
        url: 'https://proxy.example.com/video_001',
        isUsingCache: false,
      );
      expect(result.isUsingCache, isFalse);
      expect(result.fallbackQuality, isNull);
    });

    test('降级命中时 url 应为降级清晰度的缓存路径', () {
      // fallbackQuality 和 url 应一致指向同一清晰度的缓存
      const fallbackQuality = '高清';
      const cachedPath = '/cache/video_002_高清.mp4';
      const result = CacheResolveResult(
        url: cachedPath,
        isUsingCache: true,
        fallbackQuality: fallbackQuality,
      );
      expect(result.url, equals(cachedPath));
      expect(result.fallbackQuality, equals(fallbackQuality));
    });

    test('精确命中与降级命中的区分', () {
      // 精确命中
      const exact = CacheResolveResult(
        url: '/cache/video_超清.mp4',
        isUsingCache: true,
      );
      // 降级命中
      const fallback = CacheResolveResult(
        url: '/cache/video_标清.mp4',
        isUsingCache: true,
        fallbackQuality: '标清',
      );

      // 精确命中：fallbackQuality 为 null
      expect(exact.fallbackQuality, isNull);
      // 降级命中：fallbackQuality 有值
      expect(fallback.fallbackQuality, isNotNull);
    });

    test('不同降级清晰度结果可区分', () {
      const fallbackHD = CacheResolveResult(
        url: '/cache/video_高清.mp4',
        isUsingCache: true,
        fallbackQuality: '高清',
      );
      const fallbackSD = CacheResolveResult(
        url: '/cache/video_标清.mp4',
        isUsingCache: true,
        fallbackQuality: '标清',
      );
      const fallbackLow = CacheResolveResult(
        url: '/cache/video_流畅.mp4',
        isUsingCache: true,
        fallbackQuality: '流畅',
      );

      // 三种降级结果应可区分
      expect(fallbackHD.fallbackQuality, equals('高清'));
      expect(fallbackSD.fallbackQuality, equals('标清'));
      expect(fallbackLow.fallbackQuality, equals('流畅'));
    });

    test('所有清晰度降级场景的 CacheResolveResult 构造', () {
      // 模拟请求超清时，各降级场景的结果构造
      const scenarios = [
        ('超清', null), // 精确命中
        ('高清', '高清'), // 降级到高清
        ('标清', '标清'), // 降级到标清
        ('流畅', '流畅'), // 降级到流畅
      ];

      for (final (quality, fallback) in scenarios) {
        final result = CacheResolveResult(
          url: '/cache/video_$quality.mp4',
          isUsingCache: true,
          fallbackQuality: fallback,
        );
        expect(result.isUsingCache, isTrue);
        expect(result.fallbackQuality, equals(fallback));
      }
    });

    test('CacheResolveResult 记录类型语义 — 路径与清晰度对应', () {
      // 验证 getAnyQualityCachePath 返回的记录类型语义
      // ({String path, String quality})? 中的 path 和 quality 应一致
      const quality = '高清';
      const path = '/cache/video_高清.mp4';

      // 模拟返回记录
      const record = (path: path, quality: quality);
      expect(record.$1, equals(path));
      expect(record.$2, equals(quality));
      expect(record.path, equals(path));
      expect(record.quality, equals(quality));
    });
  });
}
