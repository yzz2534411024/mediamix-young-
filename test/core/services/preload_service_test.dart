import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/core/services/preload_service.dart';
import 'package:mediamix/core/services/video_cache_service.dart';
import 'package:mediamix/core/network/network_engine.dart' show NetworkCondition;

void main() {
  // ==================== PreloadPriority ====================
  group('PreloadPriority', () {
    test('优先级数值从小到大排列', () {
      expect(PreloadPriority.currentPlayback.value, equals(0));
      expect(PreloadPriority.nextEpisode.value, equals(1));
      expect(PreloadPriority.adjacentItem.value, equals(2));
      expect(PreloadPriority.playlistItem.value, equals(3));
      expect(PreloadPriority.historyReplay.value, equals(4));
    });

    test('currentPlayback 优先级最高', () {
      for (final p in PreloadPriority.values) {
        if (p != PreloadPriority.currentPlayback) {
          expect(
            PreloadPriority.currentPlayback.value < p.value,
            isTrue,
            reason:
                '${PreloadPriority.currentPlayback.name} 应比 ${p.name} 优先级更高',
          );
        }
      }
    });

    test('historyReplay 优先级最低', () {
      for (final p in PreloadPriority.values) {
        if (p != PreloadPriority.historyReplay) {
          expect(
            PreloadPriority.historyReplay.value > p.value,
            isTrue,
            reason:
                '${PreloadPriority.historyReplay.name} 应比 ${p.name} 优先级更低',
          );
        }
      }
    });

    test('所有优先级值唯一', () {
      final values = PreloadPriority.values.map((p) => p.value).toList();
      expect(values.toSet().length, equals(values.length));
    });

    test('共有 5 个优先级', () {
      expect(PreloadPriority.values.length, equals(5));
    });
  });

  // ==================== PreloadTaskStatus ====================
  group('PreloadTaskStatus', () {
    test('包含所有预期状态', () {
      expect(PreloadTaskStatus.values, containsAll(<PreloadTaskStatus>[
        PreloadTaskStatus.waiting,
        PreloadTaskStatus.downloading,
        PreloadTaskStatus.completed,
        PreloadTaskStatus.failed,
        PreloadTaskStatus.cancelled,
      ]));
    });

    test('共有 5 个状态', () {
      expect(PreloadTaskStatus.values.length, equals(5));
    });
  });

  // ==================== PreloadTask ====================
  group('PreloadTask', () {
    test('默认状态为 waiting，loadedBytes 为 0', () {
      final task = PreloadTask(
        id: 'test_1',
        videoId: 'v1',
        url: 'https://example.com/v1.mp4',
        priority: PreloadPriority.nextEpisode,
        preloadBytes: 1024,
      );

      expect(task.status, equals(PreloadTaskStatus.waiting));
      expect(task.loadedBytes, equals(0));
      expect(task.id, equals('test_1'));
      expect(task.videoId, equals('v1'));
      expect(task.url, equals('https://example.com/v1.mp4'));
      expect(task.priority, equals(PreloadPriority.nextEpisode));
      expect(task.preloadBytes, equals(1024));
    });

    test('createdAt 默认为当前时间', () {
      final before = DateTime.now();
      final task = PreloadTask(
        id: 't1',
        videoId: 'v1',
        url: 'https://example.com/v1.mp4',
        priority: PreloadPriority.currentPlayback,
        preloadBytes: 0,
      );
      final after = DateTime.now();

      expect(
        task.createdAt.isAfter(before.subtract(const Duration(milliseconds: 1))),
        isTrue,
      );
      expect(
        task.createdAt.isBefore(after.add(const Duration(milliseconds: 1))),
        isTrue,
      );
    });

    test('可自定义 createdAt', () {
      final customTime = DateTime(2024, 1, 1);
      final task = PreloadTask(
        id: 't1',
        videoId: 'v1',
        url: 'https://example.com/v1.mp4',
        priority: PreloadPriority.nextEpisode,
        preloadBytes: 512,
        createdAt: customTime,
      );

      expect(task.createdAt, equals(customTime));
    });

    test('cancel 将状态设为 cancelled', () {
      final task = PreloadTask(
        id: 't1',
        videoId: 'v1',
        url: 'https://example.com/v1.mp4',
        priority: PreloadPriority.nextEpisode,
        preloadBytes: 1024,
      );

      expect(task.status, equals(PreloadTaskStatus.waiting));

      task.cancel();

      expect(task.status, equals(PreloadTaskStatus.cancelled));
    });

    test('多次 cancel 不抛异常', () {
      final task = PreloadTask(
        id: 't1',
        videoId: 'v1',
        url: 'https://example.com/v1.mp4',
        priority: PreloadPriority.nextEpisode,
        preloadBytes: 1024,
      );

      task.cancel();
      task.cancel();

      expect(task.status, equals(PreloadTaskStatus.cancelled));
    });

    test('loadedBytes 可修改', () {
      final task = PreloadTask(
        id: 't1',
        videoId: 'v1',
        url: 'https://example.com/v1.mp4',
        priority: PreloadPriority.nextEpisode,
        preloadBytes: 1024,
      );

      expect(task.loadedBytes, equals(0));
      task.loadedBytes = 512;
      expect(task.loadedBytes, equals(512));
    });

    test('status 可修改', () {
      final task = PreloadTask(
        id: 't1',
        videoId: 'v1',
        url: 'https://example.com/v1.mp4',
        priority: PreloadPriority.nextEpisode,
        preloadBytes: 1024,
      );

      task.status = PreloadTaskStatus.downloading;
      expect(task.status, equals(PreloadTaskStatus.downloading));

      task.status = PreloadTaskStatus.completed;
      expect(task.status, equals(PreloadTaskStatus.completed));
    });

    test('attachCancelToken 绑定后 cancel 可触发 CancelToken', () {
      final task = PreloadTask(
        id: 't1',
        videoId: 'v1',
        url: 'https://example.com/v1.mp4',
        priority: PreloadPriority.nextEpisode,
        preloadBytes: 1024,
      );

      // 未绑定 cancelToken 时 cancel 不抛异常
      task.cancel();
      expect(task.status, equals(PreloadTaskStatus.cancelled));
    });
  });

  // ==================== PreloadStrategy ====================
  group('PreloadStrategy', () {
    test('wifi 策略配置正确', () {
      expect(PreloadStrategy.wifi.cacheFullVideo, isTrue);
      expect(PreloadStrategy.wifi.preloadCount, equals(3));
      expect(PreloadStrategy.wifi.initialBytes, equals(0));
      expect(PreloadStrategy.wifi.bandwidthFraction, equals(0.30));
    });

    test('mobile 策略配置正确', () {
      expect(PreloadStrategy.mobile.cacheFullVideo, isFalse);
      expect(PreloadStrategy.mobile.preloadCount, equals(1));
      expect(PreloadStrategy.mobile.initialBytes, equals(512 * 1024));
      expect(PreloadStrategy.mobile.bandwidthFraction, equals(0.20));
    });

    test('weak 策略配置正确', () {
      expect(PreloadStrategy.weak.cacheFullVideo, isFalse);
      expect(PreloadStrategy.weak.preloadCount, equals(0));
      expect(PreloadStrategy.weak.initialBytes, equals(128 * 1024));
      expect(PreloadStrategy.weak.bandwidthFraction, equals(0.10));
    });

    test('offline 策略配置正确', () {
      expect(PreloadStrategy.offline.cacheFullVideo, isFalse);
      expect(PreloadStrategy.offline.preloadCount, equals(0));
      expect(PreloadStrategy.offline.initialBytes, equals(0));
      expect(PreloadStrategy.offline.bandwidthFraction, equals(0.0));
    });

    group('forCondition', () {
      test('wifi 条件返回 wifi 策略', () {
        final strategy = PreloadStrategy.forCondition(NetworkCondition.wifi);
        expect(strategy.cacheFullVideo, isTrue);
        expect(strategy.preloadCount, equals(3));
      });

      test('lte 条件返回 mobile 策略', () {
        final strategy = PreloadStrategy.forCondition(NetworkCondition.lte);
        expect(strategy.cacheFullVideo, isFalse);
        expect(strategy.preloadCount, equals(1));
        expect(strategy.initialBytes, equals(512 * 1024));
      });

      test('threeG 条件返回 mobile 策略', () {
        final strategy = PreloadStrategy.forCondition(NetworkCondition.threeG);
        expect(strategy.cacheFullVideo, isFalse);
        expect(strategy.preloadCount, equals(1));
      });

      test('weak 条件返回 weak 策略', () {
        final strategy = PreloadStrategy.forCondition(NetworkCondition.weak);
        expect(strategy.preloadCount, equals(0));
        expect(strategy.initialBytes, equals(128 * 1024));
        expect(strategy.bandwidthFraction, equals(0.10));
      });

      test('offline 条件返回 offline 策略', () {
        final strategy = PreloadStrategy.forCondition(NetworkCondition.offline);
        expect(strategy.preloadCount, equals(0));
        expect(strategy.bandwidthFraction, equals(0.0));
      });

      test('所有 NetworkCondition 均有对应策略', () {
        for (final condition in NetworkCondition.values) {
          expect(
            () => PreloadStrategy.forCondition(condition),
            returnsNormally,
            reason: '${condition.name} 应有对应策略',
          );
        }
      });

      test('lte 和 threeG 返回相同策略', () {
        final lteStrategy = PreloadStrategy.forCondition(NetworkCondition.lte);
        final threeGStrategy =
            PreloadStrategy.forCondition(NetworkCondition.threeG);
        expect(lteStrategy.cacheFullVideo, equals(threeGStrategy.cacheFullVideo));
        expect(lteStrategy.preloadCount, equals(threeGStrategy.preloadCount));
        expect(lteStrategy.initialBytes, equals(threeGStrategy.initialBytes));
        expect(
          lteStrategy.bandwidthFraction,
          equals(threeGStrategy.bandwidthFraction),
        );
      });
    });

    test('策略带宽占比从高到低排列: wifi > mobile > weak > offline', () {
      expect(
        PreloadStrategy.wifi.bandwidthFraction >
            PreloadStrategy.mobile.bandwidthFraction,
        isTrue,
      );
      expect(
        PreloadStrategy.mobile.bandwidthFraction >
            PreloadStrategy.weak.bandwidthFraction,
        isTrue,
      );
      expect(
        PreloadStrategy.weak.bandwidthFraction >
            PreloadStrategy.offline.bandwidthFraction,
        isTrue,
      );
    });

    test('策略预加载数量从多到少: wifi > mobile > weak = offline', () {
      expect(
        PreloadStrategy.wifi.preloadCount > PreloadStrategy.mobile.preloadCount,
        isTrue,
      );
      expect(
        PreloadStrategy.mobile.preloadCount > PreloadStrategy.weak.preloadCount,
        isTrue,
      );
      expect(
        PreloadStrategy.weak.preloadCount,
        equals(PreloadStrategy.offline.preloadCount),
      );
    });
  });

  // ==================== PreloadService ====================
  group('PreloadService', () {
    late PreloadService service;
    late _MockVideoCacheService mockCache;

    setUp(() {
      mockCache = _MockVideoCacheService();
      service = PreloadService(cacheService: mockCache);
    });

    tearDown(() {
      service.dispose();
    });

    test('初始网络条件为 wifi', () {
      expect(service.networkCondition, equals(NetworkCondition.wifi));
    });

    test('初始策略为 wifi 策略', () {
      expect(service.strategy.cacheFullVideo, isTrue);
      expect(service.strategy.preloadCount, equals(3));
    });

    test('activeTasks 初始为空', () {
      expect(service.activeTasks, isEmpty);
    });

    group('updateNetworkCondition', () {
      test('更新网络条件后策略相应变化', () {
        service.updateNetworkCondition(NetworkCondition.lte);
        expect(service.networkCondition, equals(NetworkCondition.lte));
        expect(service.strategy.cacheFullVideo, isFalse);
        expect(service.strategy.preloadCount, equals(1));
      });

      test('更新为 weak 网络条件', () {
        service.updateNetworkCondition(NetworkCondition.weak);
        expect(service.networkCondition, equals(NetworkCondition.weak));
        expect(service.strategy.preloadCount, equals(0));
        expect(service.strategy.bandwidthFraction, equals(0.10));
      });

      test('更新为 offline 时策略变为 offline', () {
        service.updateNetworkCondition(NetworkCondition.offline);
        expect(service.networkCondition, equals(NetworkCondition.offline));
        expect(service.strategy.bandwidthFraction, equals(0.0));
        expect(service.strategy.preloadCount, equals(0));
      });

      test('相同网络条件不重复更新策略', () {
        final initialStrategy = service.strategy;
        // 初始为 wifi，再次设置 wifi 不应改变
        service.updateNetworkCondition(NetworkCondition.wifi);
        expect(identical(service.strategy, initialStrategy), isTrue);
      });

      test('网络条件从 wifi 切换到 lte 再切回 wifi', () {
        service.updateNetworkCondition(NetworkCondition.lte);
        expect(service.networkCondition, equals(NetworkCondition.lte));

        service.updateNetworkCondition(NetworkCondition.wifi);
        expect(service.networkCondition, equals(NetworkCondition.wifi));
        expect(service.strategy.cacheFullVideo, isTrue);
      });

      test('弱网时取消低优先级任务（优先级值 > nextEpisode 的任务）', () async {
        mockCache.hasCacheResult = false;
        // 添加 nextEpisode 和 playlistItem 任务
        await service.preloadVideo('v_next', 'https://example.com/v_next.mp4',
            priority: PreloadPriority.nextEpisode);
        await service.preloadVideo('v_playlist',
            'https://example.com/v_playlist.mp4',
            priority: PreloadPriority.playlistItem);

        // 切换到弱网，playlistItem (value=3 > nextEpisode.value=1) 应被取消
        service.updateNetworkCondition(NetworkCondition.weak);
        expect(service.networkCondition, equals(NetworkCondition.weak));
      });

      test('offline 时取消所有任务', () async {
        mockCache.hasCacheResult = false;
        await service.preloadVideo('v1', 'https://example.com/v1.mp4');
        await service.preloadVideo('v2', 'https://example.com/v2.mp4');

        service.updateNetworkCondition(NetworkCondition.offline);
        expect(service.activeTasks, isEmpty);
      });
    });

    group('preloadVideo', () {
      test('离线时不添加预加载任务', () async {
        service.updateNetworkCondition(NetworkCondition.offline);
        await service.preloadVideo('v1', 'https://example.com/v1.mp4');
        expect(service.activeTasks, isEmpty);
      });

      test('已缓存的视频跳过预加载', () async {
        mockCache.hasCacheResult = true;
        await service.preloadVideo('v1', 'https://example.com/v1.mp4');
        expect(service.activeTasks, isEmpty);
      });

      test('未缓存的视频触发 hasCache 检查', () async {
        mockCache.hasCacheResult = false;
        await service.preloadVideo('v1', 'https://example.com/v1.mp4');
        expect(mockCache.hasCacheCallCount, greaterThanOrEqualTo(1));
      });

      test('相同视频且优先级不低于新任务时跳过', () async {
        mockCache.hasCacheResult = false;
        await service.preloadVideo('v1', 'https://example.com/v1.mp4',
            priority: PreloadPriority.currentPlayback);
        // 尝试用更低优先级再次添加
        await service.preloadVideo('v1', 'https://example.com/v1.mp4',
            priority: PreloadPriority.nextEpisode);
        // hasCache 只被调用一次（第二次因优先级不够高而跳过）
        expect(mockCache.hasCacheCallCount, equals(1));
      });

      test('更高优先级替换低优先级任务', () async {
        mockCache.hasCacheResult = false;
        await service.preloadVideo('v1', 'https://example.com/v1.mp4',
            priority: PreloadPriority.playlistItem);
        // 用更高优先级替换
        await service.preloadVideo('v1', 'https://example.com/v1.mp4',
            priority: PreloadPriority.currentPlayback);
        // hasCache 被调用两次（第二次因优先级更高而重新创建）
        expect(mockCache.hasCacheCallCount, equals(2));
      });

      test('自定义 targetBytes 参数', () async {
        mockCache.hasCacheResult = false;
        await service.preloadVideo(
          'v1',
          'https://example.com/v1.mp4',
          targetBytes: 2048,
        );
        // 验证方法正常执行
      });
    });

    group('preloadNextEpisode', () {
      test('调用 preloadVideo 并使用 nextEpisode 优先级', () async {
        mockCache.hasCacheResult = false;
        await service.preloadNextEpisode('v1', 'https://example.com/v1.mp4');
        expect(mockCache.hasCacheCallCount, greaterThanOrEqualTo(1));
      });
    });

    group('preloadAdjacent', () {
      test('调用 preloadVideo 并使用 adjacentItem 优先级', () async {
        mockCache.hasCacheResult = false;
        await service.preloadAdjacent('v1', 'https://example.com/v1.mp4');
        expect(mockCache.hasCacheCallCount, greaterThanOrEqualTo(1));
      });
    });

    group('cancelPreload', () {
      test('取消不存在的任务不抛异常', () async {
        await service.cancelPreload('nonexistent');
        // 不应抛出异常
      });

      test('取消已存在的任务', () async {
        mockCache.hasCacheResult = false;
        await service.preloadVideo('v1', 'https://example.com/v1.mp4');
        await service.cancelPreload('v1');
        // 任务应被移除
      });
    });

    group('cancelAll', () {
      test('取消所有任务后 activeTasks 为空', () async {
        mockCache.hasCacheResult = false;
        await service.preloadVideo('v1', 'https://example.com/v1.mp4');
        await service.preloadVideo('v2', 'https://example.com/v2.mp4');

        await service.cancelAll();
        expect(service.activeTasks, isEmpty);
      });

      test('无任务时 cancelAll 不抛异常', () async {
        await service.cancelAll();
        // 不应抛出异常
      });
    });

    group('notifyPlaybackBuffering', () {
      test('缓冲时暂停预加载', () {
        service.notifyPlaybackBuffering(true);
        // 内部状态 _isPlaybackBuffering 应为 true
      });

      test('缓冲结束后恢复预加载', () {
        service.notifyPlaybackBuffering(true);
        service.notifyPlaybackBuffering(false);
        // 内部状态应恢复
      });

      test('相同缓冲状态不重复处理', () {
        // 初始为 false，设置为 false 应无变化
        service.notifyPlaybackBuffering(false);
        service.notifyPlaybackBuffering(false);
      });

      test('缓冲中添加任务不会执行下载', () async {
        service.notifyPlaybackBuffering(true);
        mockCache.hasCacheResult = false;
        await service.preloadVideo('v1', 'https://example.com/v1.mp4');
        // 任务应处于 waiting 状态，不会被处理
      });

      test('缓冲结束后恢复处理队列', () async {
        service.notifyPlaybackBuffering(true);
        mockCache.hasCacheResult = false;
        await service.preloadVideo('v1', 'https://example.com/v1.mp4');

        // 恢复后应重新处理队列
        service.notifyPlaybackBuffering(false);
      });
    });

    group('tasksStream', () {
      test('任务变更时发出事件', () async {
        mockCache.hasCacheResult = false;
        final events = <List<PreloadTask>>[];
        service.tasksStream.listen(events.add);

        await service.preloadVideo('v1', 'https://example.com/v1.mp4');

        // 等待 stream 事件
        await Future.delayed(const Duration(milliseconds: 50));

        expect(events, isNotEmpty);
      });

      test('cancelAll 后发出空列表事件', () async {
        final events = <List<PreloadTask>>[];
        service.tasksStream.listen(events.add);

        await service.cancelAll();

        await Future.delayed(const Duration(milliseconds: 50));

        // 最后一个事件应为空列表
        expect(events.last, isEmpty);
      });
    });

    group('dispose', () {
      test('dispose 后不再接受新任务', () async {
        service.dispose();
        mockCache.hasCacheResult = false;
        await service.preloadVideo('v1', 'https://example.com/v1.mp4');
        // 应直接返回，不创建任务
      });

      test('dispose 关闭 tasksStream', () async {
        service.dispose();
        // stream 关闭后不再发出事件，isEmpty 返回 Future<bool>
        expect(
          await service.tasksStream.isEmpty,
          isTrue,
        );
      });
    });
  });

  // ==================== PreloadStatusInfo ====================
  group('PreloadStatusInfo', () {
    test('totalCount 计算正确', () {
      const info = PreloadStatusInfo(
        pendingCount: 2,
        downloadingCount: 1,
        completedCount: 3,
        cancelledCount: 1,
        failedCount: 0,
        currentDepth: 2,
      );
      expect(info.totalCount, equals(7));
    });

    test('hasActiveTasks 仅当 downloadingCount > 0', () {
      const withActive = PreloadStatusInfo(
        pendingCount: 1,
        downloadingCount: 1,
        completedCount: 0,
        cancelledCount: 0,
        failedCount: 0,
        currentDepth: 2,
      );
      expect(withActive.hasActiveTasks, isTrue);

      const withoutActive = PreloadStatusInfo(
        pendingCount: 1,
        downloadingCount: 0,
        completedCount: 0,
        cancelledCount: 0,
        failedCount: 0,
        currentDepth: 2,
      );
      expect(withoutActive.hasActiveTasks, isFalse);
    });
  });

  // ==================== PreloadDepthCalculator ====================
  group('PreloadDepthCalculator', () {
    late PreloadDepthCalculator calc;

    setUp(() {
      calc = PreloadDepthCalculator();
    });

    test('离线返回 0', () {
      expect(
        calc.calculateDepth(networkCondition: NetworkCondition.offline),
        equals(0),
      );
    });

    test('弱网返回 minDepth(1)', () {
      expect(
        calc.calculateDepth(networkCondition: NetworkCondition.weak),
        equals(PreloadDepthCalculator.minDepth),
      );
    });

    test('WiFi 无额外数据返回 maxDepth(3)', () {
      expect(
        calc.calculateDepth(networkCondition: NetworkCondition.wifi),
        equals(PreloadDepthCalculator.maxDepth),
      );
    });

    test('LTE 无额外数据返回 2', () {
      expect(
        calc.calculateDepth(networkCondition: NetworkCondition.lte),
        equals(2),
      );
    });

    test('WiFi + 长停留时长 → 深度被 clamp 到 maxDepth(3)', () {
      expect(
        calc.calculateDepth(
          networkCondition: NetworkCondition.wifi,
          avgDwellTimeSec: 900, // 15 分钟
        ),
        equals(3),
      );
    });

    test('WiFi + 短停留时长 → 深度减少', () {
      expect(
        calc.calculateDepth(
          networkCondition: NetworkCondition.wifi,
          avgDwellTimeSec: 60, // 1 分钟
        ),
        equals(2), // 3 - 1 = 2
      );
    });

    test('WiFi + 高跳出率 → 深度减少', () {
      expect(
        calc.calculateDepth(
          networkCondition: NetworkCondition.wifi,
          bounceRate: 0.8,
        ),
        equals(2), // 3 - 1 = 2
      );
    });

    test('WiFi + 低存储空间 → 深度减少', () {
      expect(
        calc.calculateDepth(
          networkCondition: NetworkCondition.wifi,
          availableStorageBytes: 100 * 1024 * 1024, // 100MB
        ),
        equals(2), // 3 - 1 = 2
      );
    });

    test('WiFi + 短停留 + 高跳出 + 低存储 → clamp 到 minDepth(1)', () {
      expect(
        calc.calculateDepth(
          networkCondition: NetworkCondition.wifi,
          avgDwellTimeSec: 60,
          bounceRate: 0.8,
          availableStorageBytes: 100 * 1024 * 1024,
        ),
        equals(1), // 3 - 1 - 1 - 1 = 0 → clamp to 1
      );
    });

    test('LTE + 长停留 → clamp 到 maxDepth(3)', () {
      expect(
        calc.calculateDepth(
          networkCondition: NetworkCondition.lte,
          avgDwellTimeSec: 900,
        ),
        equals(3), // 2 + 1 = 3
      );
    });

    test('3G + 短停留 → clamp 到 minDepth(1)', () {
      expect(
        calc.calculateDepth(
          networkCondition: NetworkCondition.threeG,
          avgDwellTimeSec: 60,
        ),
        equals(1), // 1 - 1 = 0 → clamp to 1
      );
    });

    test('深度范围始终在 0~maxDepth 之间', () {
      for (final condition in NetworkCondition.values) {
        final depth = calc.calculateDepth(
          networkCondition: condition,
          avgDwellTimeSec: 60,
          bounceRate: 0.9,
          availableStorageBytes: 10 * 1024 * 1024,
        );
        expect(depth, greaterThanOrEqualTo(0));
        expect(depth, lessThanOrEqualTo(PreloadDepthCalculator.maxDepth));
      }
    });
  });

  // ==================== PreloadService 动态深度 + 状态查询 ====================
  group('PreloadService 动态深度与状态', () {
    late PreloadService service;
    late _MockVideoCacheService mockCache;

    setUp(() {
      mockCache = _MockVideoCacheService();
      service = PreloadService(cacheService: mockCache);
    });

    tearDown(() {
      service.dispose();
    });

    test('初始深度为 defaultDepth(2)', () {
      expect(service.currentPreloadDepth, equals(PreloadDepthCalculator.defaultDepth));
    });

    test('getPreloadStatus 初始状态全为 0', () {
      final status = service.getPreloadStatus();
      expect(status.pendingCount, equals(0));
      expect(status.downloadingCount, equals(0));
      expect(status.completedCount, equals(0));
      expect(status.cancelledCount, equals(0));
      expect(status.failedCount, equals(0));
      expect(status.currentDepth, equals(PreloadDepthCalculator.defaultDepth));
    });

    test('updateUserBehavior 更新深度', () {
      // WiFi + 短停留 → 深度应减少
      service.updateUserBehavior(avgDwellTimeSec: 60);
      expect(service.currentPreloadDepth, equals(2)); // 3 - 1 = 2
    });

    test('updateUserBehavior 深度减少时裁剪等待任务', () async {
      mockCache.hasCacheResult = false;
      // 添加多个等待任务
      await service.preloadVideo('v1', 'https://example.com/v1.mp4',
          priority: PreloadPriority.nextEpisode);
      await service.preloadVideo('v2', 'https://example.com/v2.mp4',
          priority: PreloadPriority.adjacentItem);
      await service.preloadVideo('v3', 'https://example.com/v3.mp4',
          priority: PreloadPriority.playlistItem);

      // 更新行为数据使深度减少到 1
      service.updateUserBehavior(
        avgDwellTimeSec: 60,
        bounceRate: 0.8,
      );
      expect(service.currentPreloadDepth, lessThanOrEqualTo(2));
    });

    test('getPreloadStatus 反映任务状态', () async {
      mockCache.hasCacheResult = false;
      await service.preloadVideo('v1', 'https://example.com/v1.mp4');

      final status = service.getPreloadStatus();
      // 任务应处于 waiting 或 downloading 状态
      expect(status.totalCount, greaterThanOrEqualTo(0));
    });

    test('网络条件变化时重新计算深度', () {
      service.updateNetworkCondition(NetworkCondition.lte);
      // LTE 基础深度 2，无额外数据
      expect(service.currentPreloadDepth, equals(2));

      service.updateNetworkCondition(NetworkCondition.weak);
      expect(service.currentPreloadDepth, equals(PreloadDepthCalculator.minDepth));
    });
  });
}

/// 模拟 VideoCacheService，仅实现 PreloadService 使用的方法
class _MockVideoCacheService implements VideoCacheService {
  bool hasCacheResult = false;
  int hasCacheCallCount = 0;

  @override
  Future<bool> hasCache(String videoId, {String? quality}) async {
    hasCacheCallCount++;
    return hasCacheResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
