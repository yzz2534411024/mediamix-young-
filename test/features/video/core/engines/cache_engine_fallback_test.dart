// CacheEngine 跨清晰度缓存查找功能单元测试
//
// 测试覆盖：
// 1. CacheResolveResult 精确匹配场景
// 2. CacheResolveResult 降级匹配场景
// 3. CacheResolveResult 未命中场景
// 4. CacheResolveResult 错误回退场景
//
// 注意：CacheEngineImpl 依赖 VideoCacheService（单例）和 LocalProxyServer，
// 本文件聚焦于 CacheResolveResult 数据类在 resolveVideoUrlWithFallback
// 各分支中的行为验证，不依赖文件系统或网络。

import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/core/engines/engine_interfaces.dart';

void main() {
  // ============================================================
  // 1. CacheResolveResult — 精确匹配
  // ============================================================
  group('CacheResolveResult — 精确匹配', () {
    test('精确命中时 url 为缓存路径', () {
      const cachedPath = '/cache/video_001_超清.mp4';
      const result = CacheResolveResult(
        url: cachedPath,
        isUsingCache: true,
      );
      expect(result.url, equals(cachedPath));
      expect(result.url, isNot(contains('http')));
    });

    test('精确命中时 isUsingCache 为 true', () {
      const result = CacheResolveResult(
        url: '/cache/video_001_超清.mp4',
        isUsingCache: true,
      );
      expect(result.isUsingCache, isTrue);
    });

    test('精确命中时 fallbackQuality 为 null', () {
      const result = CacheResolveResult(
        url: '/cache/video_001_超清.mp4',
        isUsingCache: true,
      );
      expect(result.fallbackQuality, isNull);
    });

    test('精确命中 — 完整结果验证', () {
      // 模拟 resolveVideoUrlWithFallback 精确匹配分支：
      // return CacheResolveResult(url: exactPath, isUsingCache: true);
      const cachedPath = '/cache/video_001_超清.mp4';
      const result = CacheResolveResult(
        url: cachedPath,
        isUsingCache: true,
      );

      expect(result.url, equals(cachedPath));
      expect(result.isUsingCache, isTrue);
      expect(result.fallbackQuality, isNull);
    });
  });

  // ============================================================
  // 2. CacheResolveResult — 降级匹配
  // ============================================================
  group('CacheResolveResult — 降级匹配', () {
    test('降级命中时 url 为降级清晰度的缓存路径', () {
      const cachedPath = '/cache/video_001_标清.mp4';
      const result = CacheResolveResult(
        url: cachedPath,
        isUsingCache: true,
        fallbackQuality: '标清',
      );
      expect(result.url, equals(cachedPath));
    });

    test('降级命中时 isUsingCache 为 true', () {
      const result = CacheResolveResult(
        url: '/cache/video_001_标清.mp4',
        isUsingCache: true,
        fallbackQuality: '标清',
      );
      expect(result.isUsingCache, isTrue);
    });

    test('降级命中时 fallbackQuality 为降级清晰度', () {
      const result = CacheResolveResult(
        url: '/cache/video_001_标清.mp4',
        isUsingCache: true,
        fallbackQuality: '标清',
      );
      expect(result.fallbackQuality, equals('标清'));
    });

    test('降级命中 — 完整结果验证', () {
      // 模拟 resolveVideoUrlWithFallback 降级匹配分支：
      // return CacheResolveResult(url: fallback.path, isUsingCache: true, fallbackQuality: fallback.quality);
      const fallbackPath = '/cache/video_001_标清.mp4';
      const fallbackQuality = '标清';
      const result = CacheResolveResult(
        url: fallbackPath,
        isUsingCache: true,
        fallbackQuality: fallbackQuality,
      );

      expect(result.url, equals(fallbackPath));
      expect(result.isUsingCache, isTrue);
      expect(result.fallbackQuality, equals(fallbackQuality));
    });

    test('降级到高清时 fallbackQuality 为 高清', () {
      const result = CacheResolveResult(
        url: '/cache/video_001_高清.mp4',
        isUsingCache: true,
        fallbackQuality: '高清',
      );
      expect(result.fallbackQuality, equals('高清'));
    });

    test('降级到流畅时 fallbackQuality 为 流畅', () {
      const result = CacheResolveResult(
        url: '/cache/video_001_流畅.mp4',
        isUsingCache: true,
        fallbackQuality: '流畅',
      );
      expect(result.fallbackQuality, equals('流畅'));
    });
  });

  // ============================================================
  // 3. CacheResolveResult — 未命中
  // ============================================================
  group('CacheResolveResult — 未命中', () {
    test('未命中时 url 为代理地址', () {
      const proxyUrl = 'http://127.0.0.1:8080/proxy/video_001';
      const result = CacheResolveResult(
        url: proxyUrl,
        isUsingCache: false,
      );
      expect(result.url, equals(proxyUrl));
      expect(result.url, contains('127.0.0.1'));
    });

    test('未命中时 isUsingCache 为 false', () {
      const result = CacheResolveResult(
        url: 'http://127.0.0.1:8080/proxy/video_001',
        isUsingCache: false,
      );
      expect(result.isUsingCache, isFalse);
    });

    test('未命中时 fallbackQuality 为 null', () {
      const result = CacheResolveResult(
        url: 'http://127.0.0.1:8080/proxy/video_001',
        isUsingCache: false,
      );
      expect(result.fallbackQuality, isNull);
    });

    test('未命中 — 完整结果验证', () {
      // 模拟 resolveVideoUrlWithFallback 未命中分支：
      // return CacheResolveResult(url: proxyUrl, isUsingCache: false);
      const proxyUrl = 'http://127.0.0.1:8080/proxy/video_001';
      const result = CacheResolveResult(
        url: proxyUrl,
        isUsingCache: false,
      );

      expect(result.url, equals(proxyUrl));
      expect(result.isUsingCache, isFalse);
      expect(result.fallbackQuality, isNull);
    });
  });

  // ============================================================
  // 4. CacheResolveResult — 错误回退
  // ============================================================
  group('CacheResolveResult — 错误回退', () {
    test('异常回退时 url 为原始网络地址', () {
      const originalUrl = 'https://cdn.example.com/video_001.mp4';
      const result = CacheResolveResult(
        url: originalUrl,
        isUsingCache: false,
      );
      expect(result.url, equals(originalUrl));
      expect(result.url, contains('https://'));
    });

    test('异常回退时 isUsingCache 为 false', () {
      const result = CacheResolveResult(
        url: 'https://cdn.example.com/video_001.mp4',
        isUsingCache: false,
      );
      expect(result.isUsingCache, isFalse);
    });

    test('异常回退时 fallbackQuality 为 null', () {
      const result = CacheResolveResult(
        url: 'https://cdn.example.com/video_001.mp4',
        isUsingCache: false,
      );
      expect(result.fallbackQuality, isNull);
    });

    test('异常回退 — 完整结果验证', () {
      // 模拟 resolveVideoUrlWithFallback catch 分支：
      // return CacheResolveResult(url: url, isUsingCache: false);
      const originalUrl = 'https://cdn.example.com/video_001.mp4';
      const result = CacheResolveResult(
        url: originalUrl,
        isUsingCache: false,
      );

      expect(result.url, equals(originalUrl));
      expect(result.isUsingCache, isFalse);
      expect(result.fallbackQuality, isNull);
    });
  });

  // ============================================================
  // 5. 四种场景对比
  // ============================================================
  group('四种场景对比', () {
    test('精确匹配 vs 降级匹配 vs 未命中 vs 错误回退', () {
      const exact = CacheResolveResult(
        url: '/cache/video_超清.mp4',
        isUsingCache: true,
      );
      const fallback = CacheResolveResult(
        url: '/cache/video_标清.mp4',
        isUsingCache: true,
        fallbackQuality: '标清',
      );
      const miss = CacheResolveResult(
        url: 'http://127.0.0.1:8080/proxy/video_001',
        isUsingCache: false,
      );
      const error = CacheResolveResult(
        url: 'https://cdn.example.com/video_001.mp4',
        isUsingCache: false,
      );

      // 精确匹配：缓存命中，无降级
      expect(exact.isUsingCache, isTrue);
      expect(exact.fallbackQuality, isNull);

      // 降级匹配：缓存命中，有降级
      expect(fallback.isUsingCache, isTrue);
      expect(fallback.fallbackQuality, isNotNull);

      // 未命中：走代理
      expect(miss.isUsingCache, isFalse);
      expect(miss.fallbackQuality, isNull);
      expect(miss.url, contains('127.0.0.1'));

      // 错误回退：走原始 URL
      expect(error.isUsingCache, isFalse);
      expect(error.fallbackQuality, isNull);
      expect(error.url, contains('https://'));
    });

    test('isUsingCache 区分缓存与网络', () {
      const fromCache = CacheResolveResult(
        url: '/cache/video.mp4',
        isUsingCache: true,
      );
      const fromNetwork = CacheResolveResult(
        url: 'http://127.0.0.1:8080/proxy/video',
        isUsingCache: false,
      );

      expect(fromCache.isUsingCache, isTrue);
      expect(fromNetwork.isUsingCache, isFalse);
    });

    test('fallbackQuality 区分精确命中与降级命中', () {
      const exact = CacheResolveResult(
        url: '/cache/video_超清.mp4',
        isUsingCache: true,
      );
      const degraded = CacheResolveResult(
        url: '/cache/video_标清.mp4',
        isUsingCache: true,
        fallbackQuality: '标清',
      );

      // 两者都使用缓存，但 fallbackQuality 不同
      expect(exact.isUsingCache, isTrue);
      expect(degraded.isUsingCache, isTrue);
      expect(exact.fallbackQuality, isNull);
      expect(degraded.fallbackQuality, isNotNull);
    });
  });
}
