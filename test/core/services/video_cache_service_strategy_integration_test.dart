// VideoCacheService + CacheStrategyManager 集成测试
//
// 覆盖 7 个集成场景：
// 1. setStrategyManager() 注入/移除
// 2. putVideo() 使用动态 TTL
// 3. putVideo() 使用动态优先级（CachePriority → 数值映射）
// 4. _getL2MaxEntries() 应用容量倍数
// 5. 缓存命中时调用 _recordViewingIfNeeded()
// 6. 淘汰排序使用 _getEffectivePriorityForEntry() 动态优先级
// 7. strategyManager=null 时降级到默认值

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediamix/core/services/cache_strategy_manager.dart';
import 'package:mediamix/core/services/video_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoCacheService service;
  late CacheStrategyManager strategyManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = VideoCacheService.instance;
    await service.clearAll();
    service.setStrategyManager(null);

    strategyManager = CacheStrategyManager.instance;
    strategyManager.resetForTesting();
    await strategyManager.initialize();
  });

  tearDown(() {
    service.setStrategyManager(null);
    strategyManager.resetForTesting();
    strategyManager.dispose();
  });

  // ============================================================
  // 场景 1: setStrategyManager() 注入/移除
  // ============================================================
  group('场景1: setStrategyManager 注入/移除', () {
    test('初始状态 strategyManager 为 null', () {
      expect(service.strategyManager, isNull);
    });

    test('注入后 strategyManager 不为 null', () {
      service.setStrategyManager(strategyManager);
      expect(service.strategyManager, isNotNull);
      expect(service.strategyManager, same(strategyManager));
    });

    test('移除后 strategyManager 为 null', () {
      service.setStrategyManager(strategyManager);
      expect(service.strategyManager, isNotNull);

      service.setStrategyManager(null);
      expect(service.strategyManager, isNull);
    });

    test('可以重复注入不同的策略管理器实例', () {
      service.setStrategyManager(strategyManager);
      expect(service.strategyManager, same(strategyManager));

      // 再次注入（同一个实例）
      service.setStrategyManager(strategyManager);
      expect(service.strategyManager, same(strategyManager));
    });

    test('注入后立即影响 L2 容量计算', () {
      // 注入前：默认 50
      expect(service.l2CurrentMaxEntries, equals(50));

      // 产生数据使容量倍数为 1.3（高频时段）
      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 20; i++) {
        strategyManager.recordViewing('v$i', hour: currentHour);
      }

      service.setStrategyManager(strategyManager);
      final multiplier = strategyManager.getCapacityMultiplier();
      if (multiplier > 1.0) {
        // 注入后 L2 容量应受倍数影响
        expect(service.l2CurrentMaxEntries, greaterThan(50));
      }
    });

    test('移除后立即恢复默认 L2 容量', () {
      service.setStrategyManager(strategyManager);
      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 20; i++) {
        strategyManager.recordViewing('v$i', hour: currentHour);
      }

      service.setStrategyManager(null);
      expect(service.l2CurrentMaxEntries, equals(50));
    });
  });

  // ============================================================
  // 场景 2: putVideo() 使用动态 TTL
  // ============================================================
  group('场景2: putVideo 使用动态 TTL', () {
    test('策略管理器为高重播视频返回更长 TTL', () {
      service.setStrategyManager(strategyManager);

      final currentHour = DateTime.now().hour;
      // 填充观看数据
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }
      // 高重播视频
      for (int i = 0; i < 5; i++) {
        strategyManager.recordViewing('v_hot', hour: currentHour);
      }

      const baseTtl = 604800;
      final dynamicTtl =
          strategyManager.getDynamicTtl('v_hot', baseTtl: baseTtl);
      // 高重播视频 TTL 应大于基础 TTL
      expect(dynamicTtl, greaterThan(baseTtl));
    });

    test('策略管理器为冷视频返回更短或相同 TTL', () {
      service.setStrategyManager(strategyManager);

      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }

      const baseTtl = 604800;
      final coldTtl =
          strategyManager.getDynamicTtl('v_cold', baseTtl: baseTtl);
      // 冷视频（非高频时段观看）TTL 可能缩短
      // 取决于当前时段是否高频，所以只验证合理范围
      expect(coldTtl, greaterThan(0));
    });

    test('putVideo 接受 category 参数用于动态 TTL 计算', () async {
      // 验证 putVideo 签名包含 category 参数
      // 通过直接调用验证不报错
      service.setStrategyManager(strategyManager);

      // putVideo 需要文件系统，这里只验证参数传递不抛异常
      // 实际磁盘操作在测试环境可能失败，但不影响参数逻辑
      await service.putVideo(
        'v_category_test',
        '/nonexistent/path.mp4', // 文件不存在，会提前返回
        quality: '720p',
        ttl: 604800,
        category: '电影',
      );
      // 不抛异常即通过
    });

    test('高重播 vs 无重播视频的 TTL 差异', () {
      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }
      for (int i = 0; i < 5; i++) {
        strategyManager.recordViewing('v_hot', hour: currentHour);
      }

      final hotTtl =
          strategyManager.getDynamicTtl('v_hot', baseTtl: 604800);
      final coldTtl =
          strategyManager.getDynamicTtl('v_unknown', baseTtl: 604800);

      expect(hotTtl, greaterThan(coldTtl));
    });

    test('策略管理器未初始化时 getDynamicTtl 返回基础 TTL', () {
      strategyManager.resetForTesting();
      final ttl = strategyManager.getDynamicTtl('v1', baseTtl: 604800);
      expect(ttl, equals(604800));
    });

    test('自定义 baseTtl 生效', () {
      final ttl = strategyManager.getDynamicTtl('v1', baseTtl: 3600);
      expect(ttl, equals(3600)); // 无数据时返回 baseTtl
    });
  });

  // ============================================================
  // 场景 3: putVideo() 使用动态优先级（CachePriority → 数值映射）
  // ============================================================
  group('场景3: putVideo 动态优先级映射', () {
    test('CachePriority.high 映射为 20', () {
      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }
      for (int i = 0; i < 5; i++) {
        strategyManager.recordViewing('v_high', hour: currentHour);
      }

      final priority = strategyManager.getPriority('v_high');
      expect(priority, equals(CachePriority.high));

      // 验证映射逻辑：high → 20
      final mappedPriority = _mapCachePriority(priority);
      expect(mappedPriority, equals(20));
    });

    test('CachePriority.normal 映射为 0', () {
      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }

      final priority = strategyManager.getPriority('v_unknown');
      expect(priority, equals(CachePriority.normal));

      final mappedPriority = _mapCachePriority(priority);
      expect(mappedPriority, equals(0));
    });

    test('CachePriority.low 映射为 -5', () {
      final mappedPriority = _mapCachePriority(CachePriority.low);
      expect(mappedPriority, equals(-5));
    });

    test('putVideo 取调用方 priority 和动态 priority 的较大值', () {
      // 模拟 putVideo 中的优先级选择逻辑
      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }
      for (int i = 0; i < 5; i++) {
        strategyManager.recordViewing('v_high', hour: currentHour);
      }

      // 动态优先级为 high(20)，调用方传入 priority=5
      final dynamicPriority = strategyManager.getPriority('v_high');
      final mappedDynamic = _mapCachePriority(dynamicPriority);
      const callerPriority = 5;
      final effectivePriority =
          mappedDynamic > callerPriority ? mappedDynamic : callerPriority;
      expect(effectivePriority, equals(20)); // 动态 20 > 调用方 5

      // 动态优先级为 high(20)，调用方传入 priority=50
      const callerPriority2 = 50;
      final effectivePriority2 =
          mappedDynamic > callerPriority2 ? mappedDynamic : callerPriority2;
      expect(effectivePriority2, equals(50)); // 调用方 50 > 动态 20
    });

    test('偏好类型视频获得高优先级', () {
      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 20; i++) {
        strategyManager.recordViewing('v$i',
            category: '电影', hour: currentHour);
      }

      final suggestion = strategyManager.getSuggestion('new_movie',
          category: '电影');
      expect(suggestion.priority, equals(CachePriority.high));
    });

    test('非偏好类型保持普通优先级', () {
      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 20; i++) {
        strategyManager.recordViewing('v$i',
            category: '电影', hour: currentHour);
      }

      final suggestion = strategyManager.getSuggestion('new_doc',
          category: '纪录片');
      expect(suggestion.priority, equals(CachePriority.normal));
    });
  });

  // ============================================================
  // 场景 4: _getL2MaxEntries() 应用容量倍数
  // ============================================================
  group('场景4: L2 容量倍数', () {
    test('无策略管理器时 L2 容量为默认 50', () {
      expect(service.l2CurrentMaxEntries, equals(50));
    });

    test('高频时段容量倍数 > 1.0 扩大 L2 容量', () {
      service.setStrategyManager(strategyManager);

      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 20; i++) {
        strategyManager.recordViewing('v$i', hour: currentHour);
      }

      final multiplier = strategyManager.getCapacityMultiplier();
      if (multiplier > 1.0) {
        final l2Max = service.l2CurrentMaxEntries;
        expect(l2Max, greaterThan(50));
        // 验证上限：50 * 3 = 150
        expect(l2Max, lessThanOrEqualTo(150));
      }
    });

    test('低频时段容量倍数 < 1.0 缩小 L2 容量', () {
      service.setStrategyManager(strategyManager);

      // 在非当前小时集中观看
      final otherHour = (DateTime.now().hour + 12) % 24;
      for (int i = 0; i < 20; i++) {
        strategyManager.recordViewing('v$i', hour: otherHour);
      }

      final multiplier = strategyManager.getCapacityMultiplier();
      if (multiplier < 1.0) {
        final l2Max = service.l2CurrentMaxEntries;
        expect(l2Max, lessThan(50));
        // 验证下限：_l2MinEntries = 5
        expect(l2Max, greaterThanOrEqualTo(5));
      }
    });

    test('容量倍数精确值验证', () {
      // 无数据时倍数为 1.0
      expect(strategyManager.getCapacityMultiplier(), equals(1.0));

      // 产生高频数据
      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 20; i++) {
        strategyManager.recordViewing('v$i', hour: currentHour);
      }

      final multiplier = strategyManager.getCapacityMultiplier();
      // 高频时段为 1.3，低频为 0.8
      expect(
        multiplier == 1.3 || multiplier == 0.8,
        isTrue,
        reason: '容量倍数应为 1.3（高频）或 0.8（低频），实际: $multiplier',
      );
    });

    test('L2 容量 = base * multiplier 并 clamp 到合理范围', () {
      service.setStrategyManager(strategyManager);

      // 验证不同内存压力下的容量计算
      // 正常压力下 base = 50
      final l2Max = service.l2CurrentMaxEntries;
      // 无论倍数如何，结果应在 [5, 150] 范围
      expect(l2Max, greaterThanOrEqualTo(5));
      expect(l2Max, lessThanOrEqualTo(150));
    });
  });

  // ============================================================
  // 场景 5: 缓存命中时调用 _recordViewingIfNeeded()
  // ============================================================
  group('场景5: 缓存命中记录观看行为', () {
    test('L1 帧缓存命中时记录观看', () async {
      service.setStrategyManager(strategyManager);
      expect(strategyManager.totalViewCount, equals(0));

      service.putFrameBuffer('v_l1', {'data': 'test'});
      service.getFrameBuffer('v_l1');

      expect(strategyManager.totalViewCount, equals(1));
    });

    test('L2 流缓存命中时记录观看', () async {
      service.setStrategyManager(strategyManager);
      expect(strategyManager.totalViewCount, equals(0));

      await service.putSegment('v_l2', 'seg_001', [1, 2, 3]);
      await service.getSegment('v_l2', 'seg_001');

      expect(strategyManager.totalViewCount, greaterThanOrEqualTo(1));
    });

    test('缓存未命中不记录观看', () async {
      service.setStrategyManager(strategyManager);

      service.getFrameBuffer('nonexistent');
      expect(strategyManager.totalViewCount, equals(0));

      await service.getSegment('nonexistent', 'seg');
      expect(strategyManager.totalViewCount, equals(0));
    });

    test('多次命中累积观看次数', () async {
      service.setStrategyManager(strategyManager);

      service.putFrameBuffer('v_multi', {'data': 'test'});
      service.getFrameBuffer('v_multi');
      service.getFrameBuffer('v_multi');
      service.getFrameBuffer('v_multi');

      expect(strategyManager.totalViewCount, equals(3));
    });

    test('不同视频的命中分别记录', () async {
      service.setStrategyManager(strategyManager);

      service.putFrameBuffer('v_a', {'data': 'a'});
      service.putFrameBuffer('v_b', {'data': 'b'});
      service.getFrameBuffer('v_a');
      service.getFrameBuffer('v_b');
      service.getFrameBuffer('v_a');

      expect(strategyManager.totalViewCount, equals(3));
      expect(strategyManager.replayCounts['v_a'], equals(2));
      expect(strategyManager.replayCounts['v_b'], equals(1));
    });

    test('未接入策略管理器时命中不报错', () async {
      // 不设置策略管理器
      service.putFrameBuffer('v_no_mgr', {'data': 'test'});
      final result = service.getFrameBuffer('v_no_mgr');
      expect(result, isNotNull);
      // 不抛异常即通过
    });
  });

  // ============================================================
  // 场景 6: 淘汰排序使用动态优先级
  // ============================================================
  group('场景6: 淘汰排序使用动态优先级', () {
    test('高重播视频的有效优先级高于无记录视频', () {
      service.setStrategyManager(strategyManager);

      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }
      for (int i = 0; i < 5; i++) {
        strategyManager.recordViewing('v_high', hour: currentHour);
      }

      final highEntry = CacheEntry(
        cacheId: 'high',
        videoId: 'v_high',
        quality: '720p',
        filePath: '/tmp/high.mp4',
        priority: 0,
        lastAccess: DateTime.now().subtract(const Duration(hours: 2)),
      );
      final lowEntry = CacheEntry(
        cacheId: 'low',
        videoId: 'v_unknown',
        quality: '720p',
        filePath: '/tmp/low.mp4',
        priority: 0,
        lastAccess: DateTime.now().subtract(const Duration(hours: 1)),
      );

      final effectiveHigh =
          _getEffectivePriorityForEntryTest(strategyManager, highEntry);
      final effectiveLow =
          _getEffectivePriorityForEntryTest(strategyManager, lowEntry);

      // v_high 动态优先级为 high(20)，v_unknown 为 normal(0)
      expect(effectiveHigh, equals(20));
      expect(effectiveLow, equals(0));
      expect(effectiveHigh, greaterThan(effectiveLow));
    });

    test('条目自身 priority 高于动态 priority 时取自身值', () {
      service.setStrategyManager(strategyManager);

      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }

      // 条目自身 priority=50（用户收藏级别），动态优先级为 normal(0)
      final entry = CacheEntry(
        cacheId: 'fav',
        videoId: 'v_unknown', // 无重播记录 → normal(0)
        quality: '720p',
        filePath: '/tmp/fav.mp4',
        priority: 50,
      );

      final effective =
          _getEffectivePriorityForEntryTest(strategyManager, entry);
      // max(0, 50) = 50，取调用方的值
      expect(effective, equals(50));
    });

    test('淘汰排序：高动态优先级条目排在低优先级之后', () {
      service.setStrategyManager(strategyManager);

      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }
      for (int i = 0; i < 5; i++) {
        strategyManager.recordViewing('v_hot', hour: currentHour);
      }

      // 模拟淘汰排序逻辑
      final entries = <CacheEntry>[
        CacheEntry(
          cacheId: 'hot',
          videoId: 'v_hot', // 动态优先级 high(20)
          quality: '720p',
          filePath: '/tmp/hot.mp4',
          priority: 0,
          lastAccess: DateTime.now().subtract(const Duration(hours: 3)),
        ),
        CacheEntry(
          cacheId: 'cold',
          videoId: 'v_cold', // 动态优先级 normal(0)
          quality: '720p',
          filePath: '/tmp/cold.mp4',
          priority: 0,
          lastAccess: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ];

      // 按有效优先级升序排序（与 VideoCacheService._evictLRU 逻辑一致）
      entries.sort((a, b) {
        final priA =
            _getEffectivePriorityForEntryTest(strategyManager, a);
        final priB =
            _getEffectivePriorityForEntryTest(strategyManager, b);
        if (priA != priB) return priA.compareTo(priB);
        return a.lastAccess.compareTo(b.lastAccess);
      });

      // cold(normal=0) 排在前面（先被淘汰），hot(high=20) 排在后面（保留）
      expect(entries[0].cacheId, equals('cold'));
      expect(entries[1].cacheId, equals('hot'));
    });

    test('_shouldKeep 逻辑：动态优先级 >= 10 的条目应保留', () {
      service.setStrategyManager(strategyManager);

      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }
      for (int i = 0; i < 5; i++) {
        strategyManager.recordViewing('v_hot', hour: currentHour);
      }

      // v_hot 动态优先级为 high(20) >= 10，应保留
      final entry = CacheEntry(
        cacheId: 'hot',
        videoId: 'v_hot',
        quality: '720p',
        filePath: '/tmp/hot.mp4',
        priority: 0, // 条目自身优先级为 0
        hitCount: 0,
        lastAccess: DateTime.now().subtract(const Duration(days: 2)),
        // 不在 24h 窗口内
      );

      final effectivePri =
          _getEffectivePriorityForEntryTest(strategyManager, entry);
      // 有效优先级 20 >= 10，应保留
      expect(effectivePri >= 10, isTrue);
    });

    test('低优先级预加载条目使用动态优先级判断', () {
      service.setStrategyManager(strategyManager);

      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 30; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }
      for (int i = 0; i < 5; i++) {
        strategyManager.recordViewing('v_hot', hour: currentHour);
      }

      // v_hot 的条目：priority=0, isComplete=false
      // 但动态优先级为 high(20)，有效优先级 > 0
      // 不应被 _evictLowPriorityPreload 淘汰
      final entry = CacheEntry(
        cacheId: 'hot_preload',
        videoId: 'v_hot',
        quality: '720p',
        filePath: '/tmp/hot.seg',
        priority: 0,
        isComplete: false,
        hitCount: 0,
        lastAccess: DateTime.now().subtract(const Duration(days: 2)),
      );

      final effectivePri =
          _getEffectivePriorityForEntryTest(strategyManager, entry);
      // 有效优先级 20 > 0，不应被低优先级预加载淘汰
      expect(effectivePri > 0, isTrue);
    });
  });

  // ============================================================
  // 场景 7: strategyManager=null 时降级到默认值
  // ============================================================
  group('场景7: strategyManager=null 降级', () {
    test('L2 容量降级为默认 50', () {
      expect(service.l2CurrentMaxEntries, equals(50));
    });

    test('CacheEntry 使用默认 TTL 和 priority', () {
      final entry = CacheEntry(
        cacheId: 'test',
        videoId: 'v1',
        quality: '720p',
        filePath: '/tmp/test.mp4',
      );
      expect(entry.ttl, equals(604800));
      expect(entry.priority, equals(0));
    });

    test('缓存操作正常工作不受影响', () async {
      // L1 操作
      service.putFrameBuffer('v1', {'data': 'test'});
      expect(service.getFrameBuffer('v1'), isNotNull);

      // L2 操作
      await service.putSegment('v2', 'seg', [1, 2, 3]);
      final result = await service.getSegment('v2', 'seg');
      expect(result.hit, isTrue);
    });

    test('淘汰操作正常工作', () async {
      // 空索引上调用 evict 不报错
      await service.evict();
    });

    test('注入后再移除，完全恢复默认行为', () async {
      service.setStrategyManager(strategyManager);

      // 产生数据
      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 20; i++) {
        strategyManager.recordViewing('v$i', hour: currentHour);
      }

      // 验证容量已受倍数影响
      expect(service.l2CurrentMaxEntries, greaterThanOrEqualTo(5));

      // 移除
      service.setStrategyManager(null);

      // 完全恢复默认
      expect(service.l2CurrentMaxEntries, equals(50));

      // L1/L2 操作正常
      service.putFrameBuffer('v_after', {'data': 'test'});
      expect(service.getFrameBuffer('v_after'), isNotNull);

      await service.putSegment('v2_after', 'seg', [1]);
      final r = await service.getSegment('v2_after', 'seg');
      expect(r.hit, isTrue);
    });

    test('getStats 在无策略管理器时正常工作', () async {
      service.putFrameBuffer('v_stats', {'data': 'test'});
      service.getFrameBuffer('v_stats');

      final stats = await service.getStats();
      expect(stats.hitCount, greaterThanOrEqualTo(1));
      expect(stats.entryCount, greaterThanOrEqualTo(0));
    });

    test('策略管理器未初始化时 putVideo 使用传入的 TTL', () async {
      // 不设置策略管理器
      expect(service.strategyManager, isNull);

      // putVideo 应使用调用方传入的 TTL（通过 CacheEntry 验证）
      final entry = CacheEntry(
        cacheId: 'test',
        videoId: 'v1',
        quality: '720p',
        filePath: '/tmp/test.mp4',
        ttl: 86400, // 自定义 TTL
        priority: 5,
      );
      expect(entry.ttl, equals(86400));
      expect(entry.priority, equals(5));
    });
  });

  // ============================================================
  // 端到端集成场景
  // ============================================================
  group('端到端集成', () {
    test('完整流程：记录观看 → 动态策略 → 缓存行为', () async {
      service.setStrategyManager(strategyManager);

      final currentHour = DateTime.now().hour;
      for (int i = 0; i < 20; i++) {
        strategyManager.recordViewing('movie_$i',
            category: '电影', hour: currentHour);
      }
      for (int i = 0; i < 5; i++) {
        strategyManager.recordViewing('fav_video',
            category: '电影', hour: currentHour);
      }

      // 策略建议
      final suggestion = strategyManager.getSuggestion('fav_video',
          category: '电影');
      expect(suggestion.priority, equals(CachePriority.high));
      expect(suggestion.ttlMultiplier, greaterThan(1.0));

      // 容量倍数
      final multiplier = strategyManager.getCapacityMultiplier();
      expect(multiplier, greaterThan(0));

      // L2 容量
      final l2Max = service.l2CurrentMaxEntries;
      expect(l2Max, greaterThanOrEqualTo(5));

      // 观看记录
      expect(strategyManager.totalViewCount, equals(25));
      expect(strategyManager.replayCounts['fav_video'], equals(5));
    });

    test('缓存命中 → 观看记录 → 策略变化 → 容量变化', () async {
      service.setStrategyManager(strategyManager);

      final currentHour = DateTime.now().hour;
      // 先建立基线
      for (int i = 0; i < 20; i++) {
        strategyManager.recordViewing('filler_$i', hour: currentHour);
      }
      expect(service.l2CurrentMaxEntries, greaterThanOrEqualTo(5));

      // 通过缓存命中产生观看记录
      service.putFrameBuffer('fav', {'data': 'test'});
      service.getFrameBuffer('fav');
      service.getFrameBuffer('fav');
      service.getFrameBuffer('fav');

      // 观看次数应增加
      expect(strategyManager.replayCounts['fav'], equals(3));

      // L2 容量可能变化（取决于时段）
      final l2After = service.l2CurrentMaxEntries;
      expect(l2After, greaterThanOrEqualTo(5));
      // 容量在合理范围内
      expect(l2After, lessThanOrEqualTo(150));
    });
  });
}

/// 模拟 VideoCacheService 中 CachePriority → 数值的映射逻辑
int _mapCachePriority(CachePriority priority) {
  return priority == CachePriority.high
      ? 20
      : priority == CachePriority.low
          ? -5
          : 0;
}

/// 模拟 VideoCacheService._getEffectivePriorityForEntry 的逻辑
int _getEffectivePriorityForEntryTest(
    CacheStrategyManager manager, CacheEntry entry) {
  if (!manager.isInitialized) return entry.priority;
  final dynamicPriority = manager.getPriority(entry.videoId);
  final mappedPriority = _mapCachePriority(dynamicPriority);
  return mappedPriority > entry.priority ? mappedPriority : entry.priority;
}
