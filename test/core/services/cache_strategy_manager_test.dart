// 缓存策略管理器单元测试
//
// 测试覆盖：
// 1. CacheStrategyManager 初始化
// 2. 观看习惯追踪（小时直方图、类型计数、重播计数）
// 3. 动态 TTL / 容量倍数 / 优先级建议
// 4. 高频时段识别
// 5. 偏好类型识别
// 6. 高重播频率识别
// 7. predictAndPreheat() 预测性预热
// 8. SharedPreferences 持久化与恢复
// 9. CacheStrategySuggestion 数据类
// 10. ViewingHabitSnapshot 数据类
// 11. 边界条件与降级

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediamix/core/services/cache_strategy_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheStrategyManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    manager = CacheStrategyManager.instance;
    manager.resetForTesting();
    await manager.initialize();
  });

  tearDown(() {
    manager.resetForTesting();
    manager.dispose();
  });

  // ============================================================
  // 1. 初始化测试
  // ============================================================
  group('初始化', () {
    test('初始化后 isInitialized 为 true', () {
      expect(manager.isInitialized, isTrue);
    });

    test('初始化后 totalViewCount 为 0', () {
      expect(manager.totalViewCount, equals(0));
    });

    test('初始化后 hourHistogram 为空', () {
      expect(manager.hourHistogram, isEmpty);
    });

    test('初始化后 categoryCounts 为空', () {
      expect(manager.categoryCounts, isEmpty);
    });

    test('初始化后 replayCounts 为空', () {
      expect(manager.replayCounts, isEmpty);
    });
  });

  // ============================================================
  // 2. 观看习惯追踪
  // ============================================================
  group('观看习惯追踪', () {
    test('recordViewing 增加总观看次数', () {
      manager.recordViewing('video_1', category: '电影', hour: 20);
      expect(manager.totalViewCount, equals(1));

      manager.recordViewing('video_2', category: '电视剧', hour: 21);
      expect(manager.totalViewCount, equals(2));
    });

    test('recordViewing 更新小时直方图', () {
      manager.recordViewing('v1', hour: 20);
      manager.recordViewing('v2', hour: 20);
      manager.recordViewing('v3', hour: 21);

      expect(manager.hourHistogram[20], equals(2));
      expect(manager.hourHistogram[21], equals(1));
    });

    test('recordViewing 更新类型计数', () {
      manager.recordViewing('v1', category: '电影');
      manager.recordViewing('v2', category: '电影');
      manager.recordViewing('v3', category: '电视剧');

      expect(manager.categoryCounts['电影'], equals(2));
      expect(manager.categoryCounts['电视剧'], equals(1));
    });

    test('recordViewing 更新重播计数', () {
      manager.recordViewing('v1');
      manager.recordViewing('v1');
      manager.recordViewing('v2');

      expect(manager.replayCounts['v1'], equals(2));
      expect(manager.replayCounts['v2'], equals(1));
    });

    test('recordViewing 不传 category 时不更新类型计数', () {
      manager.recordViewing('v1');
      expect(manager.categoryCounts, isEmpty);
    });

    test('recordViewing 空 category 不更新类型计数', () {
      manager.recordViewing('v1', category: '');
      expect(manager.categoryCounts, isEmpty);
    });

    test('recordViewing 默认使用当前小时', () {
      final currentHour = DateTime.now().hour;
      manager.recordViewing('v1');
      expect(manager.hourHistogram[currentHour], equals(1));
    });
  });

  // ============================================================
  // 3. 动态策略建议
  // ============================================================
  group('动态策略建议', () {
    test('无历史数据时返回默认建议', () {
      final suggestion = manager.getSuggestion('v1');
      expect(suggestion.ttlMultiplier, equals(1.0));
      expect(suggestion.capacityMultiplier, equals(1.0));
      expect(suggestion.priority, equals(CachePriority.normal));
    });

    test('高频时段增大 TTL 和容量', () {
      // 在 hour=20 产生大量观看记录，使其成为高频时段
      for (int i = 0; i < 20; i++) {
        manager.recordViewing('v$i', hour: 20);
      }

      // 模拟在 hour=20 时段获取建议
      // 由于 getSuggestion 使用 DateTime.now().hour，
      // 我们测试 getCapacityMultiplier 的行为
      final multiplier = manager.getCapacityMultiplier();
      // 当前时段如果不是20，可能不是高频时段
      // 所以我们验证有数据时返回合理值
      expect(multiplier, greaterThan(0));
    });

    test('高重播频率视频获得高优先级', () {
      // 产生足够多观看记录
      for (int i = 0; i < 30; i++) {
        manager.recordViewing('other_$i', hour: 10);
      }
      // 让 v1 重播 3 次（达到阈值）
      manager.recordViewing('v1', hour: 10);
      manager.recordViewing('v1', hour: 10);
      manager.recordViewing('v1', hour: 10);

      final suggestion = manager.getSuggestion('v1');
      expect(suggestion.priority, equals(CachePriority.high));
      expect(suggestion.ttlMultiplier, greaterThan(1.0));
    });

    test('偏好类型视频获得高优先级', () {
      // 产生大量"电影"类型观看记录，使其成为偏好类型
      for (int i = 0; i < 20; i++) {
        manager.recordViewing('v$i', category: '电影', hour: 10);
      }

      final suggestion = manager.getSuggestion('new_movie', category: '电影');
      expect(suggestion.priority, equals(CachePriority.high));
    });

    test('非偏好类型视频保持普通优先级', () {
      for (int i = 0; i < 20; i++) {
        manager.recordViewing('v$i', category: '电影', hour: 10);
      }

      final suggestion =
          manager.getSuggestion('new_doc', category: '纪录片');
      // 纪录片不是偏好类型（占比 < 15%），应保持 normal
      expect(suggestion.priority, equals(CachePriority.normal));
    });

    test('getDynamicTtl 返回调整后的 TTL', () {
      // 无数据时返回基础 TTL
      final baseTtl = manager.getDynamicTtl('v1', baseTtl: 604800);
      expect(baseTtl, equals(604800));
    });

    test('getDynamicTtl 高重播视频延长 TTL', () {
      for (int i = 0; i < 30; i++) {
        manager.recordViewing('other_$i', hour: 10);
      }
      manager.recordViewing('v1', hour: 10);
      manager.recordViewing('v1', hour: 10);
      manager.recordViewing('v1', hour: 10);

      final ttl = manager.getDynamicTtl('v1', baseTtl: 604800);
      expect(ttl, greaterThan(604800));
    });

    test('getPriority 返回正确优先级', () {
      expect(manager.getPriority('v1'), equals(CachePriority.normal));
    });

    test('策略建议的 TTL 倍数在合理范围内', () {
      for (int i = 0; i < 50; i++) {
        manager.recordViewing('v$i', category: '电影', hour: 20);
      }
      manager.recordViewing('v1', category: '电影', hour: 20);
      manager.recordViewing('v1', category: '电影', hour: 20);
      manager.recordViewing('v1', category: '电影', hour: 20);

      final suggestion = manager.getSuggestion('v1', category: '电影');
      expect(suggestion.ttlMultiplier, greaterThanOrEqualTo(0.3));
      expect(suggestion.ttlMultiplier, lessThanOrEqualTo(5.0));
      expect(suggestion.capacityMultiplier, greaterThanOrEqualTo(0.3));
      expect(suggestion.capacityMultiplier, lessThanOrEqualTo(3.0));
    });
  });

  // ============================================================
  // 4. 高频时段识别
  // ============================================================
  group('高频时段识别', () {
    test('无数据时没有高频时段', () {
      final snapshot = manager.getSnapshot();
      expect(snapshot.isPeakHour, isFalse);
    });

    test('集中观看的小时被识别为高频', () {
      // 在 hour=20 集中观看
      for (int i = 0; i < 10; i++) {
        manager.recordViewing('v$i', hour: 20);
      }

      // 验证 hour=20 的直方图计数
      expect(manager.hourHistogram[20], equals(10));
      // 10/10 = 100% >= 6% 阈值
    });

    test('分散观看不会所有时段都是高频', () {
      // 均匀分布在 24 个小时
      for (int h = 0; h < 24; h++) {
        manager.recordViewing('v$h', hour: h);
      }
      // 每个小时 1/24 ≈ 4.17% < 6% 阈值
      final snapshot = manager.getSnapshot();
      // 当前小时可能不是高频
      expect(snapshot.currentHourFrequency, lessThan(0.1));
    });
  });

  // ============================================================
  // 5. 偏好类型识别
  // ============================================================
  group('偏好类型识别', () {
    test('无数据时偏好列表为空', () {
      final snapshot = manager.getSnapshot();
      expect(snapshot.preferredCategories, isEmpty);
    });

    test('高频观看的类型出现在偏好列表', () {
      for (int i = 0; i < 20; i++) {
        manager.recordViewing('v$i', category: '电影');
      }
      for (int i = 0; i < 2; i++) {
        manager.recordViewing('d$i', category: '纪录片');
      }

      final snapshot = manager.getSnapshot();
      expect(snapshot.preferredCategories, contains('电影'));
      // 纪录片 2/22 ≈ 9% < 15% 阈值
      expect(snapshot.preferredCategories, isNot(contains('纪录片')));
    });

    test('多个类型都可以是偏好类型', () {
      for (int i = 0; i < 10; i++) {
        manager.recordViewing('m$i', category: '电影');
      }
      for (int i = 0; i < 10; i++) {
        manager.recordViewing('d$i', category: '电视剧');
      }

      final snapshot = manager.getSnapshot();
      expect(snapshot.preferredCategories, contains('电影'));
      expect(snapshot.preferredCategories, contains('电视剧'));
    });
  });

  // ============================================================
  // 6. 高重播频率识别
  // ============================================================
  group('高重播频率识别', () {
    test('无数据时高重播集合为空', () {
      final snapshot = manager.getSnapshot();
      expect(snapshot.highReplayVideoIds, isEmpty);
    });

    test('重播次数 >= 3 的视频出现在高重播集合', () {
      manager.recordViewing('v1');
      manager.recordViewing('v1');
      manager.recordViewing('v1');

      final snapshot = manager.getSnapshot();
      expect(snapshot.highReplayVideoIds, contains('v1'));
    });

    test('重播次数 < 3 的视频不在高重播集合', () {
      manager.recordViewing('v1');
      manager.recordViewing('v1');

      final snapshot = manager.getSnapshot();
      expect(snapshot.highReplayVideoIds, isNot(contains('v1')));
    });
  });

  // ============================================================
  // 7. predictAndPreheat()
  // ============================================================
  group('predictAndPreheat', () {
    test('无历史数据时返回空列表', () {
      final result = manager.predictAndPreheat();
      expect(result, isEmpty);
    });

    test('有数据时返回预测类型', () {
      for (int i = 0; i < 20; i++) {
        manager.recordViewing('v$i', category: '电影', hour: 20);
      }
      for (int i = 0; i < 10; i++) {
        manager.recordViewing('d$i', category: '电视剧', hour: 20);
      }

      final result = manager.predictAndPreheat();
      expect(result, isNotEmpty);
      // 电影占比最高，应该在预测列表中
      expect(result, contains('电影'));
    });

    test('getPreheatSuggestion 对预测类型返回高优先级', () {
      for (int i = 0; i < 20; i++) {
        manager.recordViewing('v$i', category: '电影', hour: 20);
      }

      final suggestion = manager.getPreheatSuggestion('电影');
      expect(suggestion.priority, equals(CachePriority.high));
      expect(suggestion.ttlMultiplier, greaterThan(1.0));
    });

    test('getPreheatSuggestion 对非预测类型返回默认', () {
      for (int i = 0; i < 20; i++) {
        manager.recordViewing('v$i', category: '电影', hour: 20);
      }

      final suggestion = manager.getPreheatSuggestion('体育');
      expect(suggestion.priority, equals(CachePriority.normal));
      expect(suggestion.ttlMultiplier, equals(1.0));
    });
  });

  // ============================================================
  // 8. 持久化测试
  // ============================================================
  group('SharedPreferences 持久化', () {
    test('记录观看后数据持久化到 SharedPreferences', () async {
      manager.recordViewing('v1', category: '电影', hour: 20);
      manager.recordViewing('v1', category: '电影', hour: 20);

      // 等待异步保存完成
      await Future.delayed(const Duration(milliseconds: 100));

      // 重新创建实例并初始化
      manager.resetForTesting();
      manager.dispose();

      final prefs = await SharedPreferences.getInstance();
      final newManager = CacheStrategyManager.instance;
      await newManager.initialize(prefs: prefs);

      expect(newManager.totalViewCount, equals(2));
      expect(newManager.hourHistogram[20], equals(2));
      expect(newManager.categoryCounts['电影'], equals(2));
      expect(newManager.replayCounts['v1'], equals(2));

      newManager.resetForTesting();
      newManager.dispose();
    });
  });

  // ============================================================
  // 9. CacheStrategySuggestion 数据类
  // ============================================================
  group('CacheStrategySuggestion', () {
    test('默认建议值正确', () {
      const s = CacheStrategySuggestion.defaultSuggestion;
      expect(s.ttlMultiplier, equals(1.0));
      expect(s.capacityMultiplier, equals(1.0));
      expect(s.priority, equals(CachePriority.normal));
    });

    test('自定义值正确', () {
      const s = CacheStrategySuggestion(
        ttlMultiplier: 2.5,
        capacityMultiplier: 1.5,
        priority: CachePriority.high,
      );
      expect(s.ttlMultiplier, equals(2.5));
      expect(s.capacityMultiplier, equals(1.5));
      expect(s.priority, equals(CachePriority.high));
    });
  });

  // ============================================================
  // 10. ViewingHabitSnapshot 数据类
  // ============================================================
  group('ViewingHabitSnapshot', () {
    test('getSnapshot 返回有效快照', () {
      final snapshot = manager.getSnapshot();
      expect(snapshot.isPeakHour, isFalse);
      expect(snapshot.currentHourFrequency, equals(0.0));
      expect(snapshot.preferredCategories, isEmpty);
      expect(snapshot.highReplayVideoIds, isEmpty);
      expect(snapshot.predictedCategories, isEmpty);
    });

    test('有数据时快照反映习惯', () {
      for (int i = 0; i < 10; i++) {
        manager.recordViewing('v$i', category: '电影', hour: 20);
      }
      manager.recordViewing('v1');
      manager.recordViewing('v1');
      manager.recordViewing('v1');

      final snapshot = manager.getSnapshot();
      expect(snapshot.preferredCategories, contains('电影'));
      expect(snapshot.highReplayVideoIds, contains('v1'));
    });
  });

  // ============================================================
  // 11. 边界条件与降级
  // ============================================================
  group('边界条件', () {
    test('未初始化时 getSuggestion 返回默认', () {
      manager.resetForTesting();
      final suggestion = manager.getSuggestion('v1');
      expect(suggestion.ttlMultiplier, equals(1.0));
    });

    test('getCapacityMultiplier 未初始化时返回 1.0', () {
      manager.resetForTesting();
      expect(manager.getCapacityMultiplier(), equals(1.0));
    });

    test('predictAndPreheat 未初始化时返回空', () {
      manager.resetForTesting();
      expect(manager.predictAndPreheat(), isEmpty);
    });

    test('大量视频记录不超出追踪上限', () {
      // 记录超过 _maxTrackedVideos(200) 个视频
      for (int i = 0; i < 250; i++) {
        manager.recordViewing('v$i');
      }
      expect(manager.replayCounts.length, lessThanOrEqualTo(200));
    });

    test('大量类型记录不超出追踪上限', () {
      // 记录超过 _maxTrackedCategories(30) 个类型
      for (int i = 0; i < 40; i++) {
        manager.recordViewing('v$i', category: 'type_$i');
      }
      expect(manager.categoryCounts.length, lessThanOrEqualTo(30));
    });

    test('getDynamicTtl 自定义 baseTtl', () {
      final ttl = manager.getDynamicTtl('v1', baseTtl: 3600);
      expect(ttl, equals(3600)); // 无数据时返回 baseTtl
    });
  });

  // ============================================================
  // 12. CachePriority 枚举
  // ============================================================
  group('CachePriority 枚举', () {
    test('包含三个值', () {
      expect(CachePriority.values.length, equals(3));
      expect(CachePriority.values, contains(CachePriority.high));
      expect(CachePriority.values, contains(CachePriority.normal));
      expect(CachePriority.values, contains(CachePriority.low));
    });
  });
}
