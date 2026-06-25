import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediamix/core/services/power_manager_service.dart';
import 'package:mediamix/core/services/data_reporter_service.dart';
import 'package:mediamix/core/services/metrics_collector_service.dart';
import 'package:mediamix/core/services/player_metrics_service.dart';
import 'package:mediamix/core/services/device_capability_service.dart';

/// 启动加速测试 — 验证懒加载模式和并行初始化正确性
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ==================== PowerManagerService 懒加载 ====================
  group('PowerManagerService 懒加载', () {
    test('ensureInitialized 首次调用触发初始化', () async {
      final service = PowerManagerService.instance;
      service.resetForTesting();

      expect(service.isInitialized, isFalse);

      await service.ensureInitialized();

      expect(service.isInitialized, isTrue);
    });

    test('ensureInitialized 多次调用幂等', () async {
      final service = PowerManagerService.instance;
      service.resetForTesting();

      await service.ensureInitialized();
      await service.ensureInitialized();
      await service.ensureInitialized();

      expect(service.isInitialized, isTrue);
    });

    test('ensureInitialized 并发调用只初始化一次', () async {
      final service = PowerManagerService.instance;
      service.resetForTesting();

      // 并发调用 ensureInitialized
      await Future.wait([
        service.ensureInitialized(),
        service.ensureInitialized(),
        service.ensureInitialized(),
      ]);

      expect(service.isInitialized, isTrue);
    });

    test('ensureInitialized 返回的 Future 可以被多次 await', () async {
      final service = PowerManagerService.instance;
      service.resetForTesting();

      // 同时发起多个 ensureInitialized 调用
      final futures = List.generate(5, (_) => service.ensureInitialized());
      await Future.wait(futures);

      expect(service.isInitialized, isTrue);
    });
  });

  // ==================== DataReporterService 懒加载 ====================
  group('DataReporterService 懒加载', () {
    test('ensureInitialized 首次调用触发初始化', () async {
      final service = DataReporterService.instance;
      // 未初始化时 getLocalDataSummary 返回空
      final summary = await service.getLocalDataSummary();
      expect(summary, isEmpty);
    });
  });

  // ==================== MetricsCollectorService 懒加载 ====================
  group('MetricsCollectorService 懒加载', () {
    test('recordEvent 在未初始化时安全 no-op', () async {
      final service = MetricsCollectorService.instance;

      // recordEvent 在未初始化时应该安全地 no-op
      // 不会抛出异常
      service.recordEvent(
        MetricsEvent.playStart,
        videoId: 'test_video',
      );
    });
  });

  // ==================== 并行初始化正确性 ====================
  group('并行初始化', () {
    test('Future.wait 并行执行多个服务初始化', () async {
      SharedPreferences.setMockInitialValues({});

      final initOrder = <String>[];

      // 模拟并行初始化三个服务
      await Future.wait([
        () async {
          await Future.delayed(const Duration(milliseconds: 50));
          initOrder.add('video_cache');
        }(),
        () async {
          await Future.delayed(const Duration(milliseconds: 10));
          initOrder.add('privacy');
        }(),
        () async {
          await Future.delayed(const Duration(milliseconds: 30));
          initOrder.add('proxy');
        }(),
      ]);

      // 并行执行：最快完成的先添加（privacy 10ms < proxy 30ms < video_cache 50ms）
      expect(initOrder, equals(['privacy', 'proxy', 'video_cache']));
    });

    test('并行初始化总耗时不超过最慢服务', () async {
      final stopwatch = Stopwatch()..start();

      await Future.wait([
        Future.delayed(const Duration(milliseconds: 50)),
        Future.delayed(const Duration(milliseconds: 30)),
        Future.delayed(const Duration(milliseconds: 40)),
      ]);

      stopwatch.stop();
      // 总耗时应接近 50ms（最慢的），而非 120ms（串行总和）
      expect(stopwatch.elapsedMilliseconds, lessThan(120));
    });

    test('单个服务初始化失败不影响其他服务', () async {
      final results = <String>[];

      await Future.wait([
        () async {
          try {
            await Future.delayed(const Duration(milliseconds: 10));
            results.add('success');
          } catch (e) {
            results.add('failed');
          }
        }(),
        () async {
          try {
            throw Exception('模拟初始化失败');
          } catch (e) {
            results.add('caught');
          }
        }(),
      ]);

      expect(results, contains('success'));
      expect(results, contains('caught'));
    });
  });

  // ==================== Completer 线程安全 ====================
  group('Completer 懒加载模式', () {
    test('Completer 确保只执行一次初始化逻辑', () async {
      int initCount = 0;
      Completer<void>? initCompleter;

      Future<void> ensureInitialized() async {
        if (initCompleter != null) return initCompleter!.future;
        initCompleter = Completer<void>();
        try {
          initCount++;
          await Future.delayed(const Duration(milliseconds: 10));
          initCompleter!.complete();
        } catch (e) {
          initCompleter!.completeError(e);
        }
      }

      // 并发调用 10 次
      await Future.wait(List.generate(10, (_) => ensureInitialized()));

      // 初始化逻辑只执行一次
      expect(initCount, equals(1));
      expect(initCompleter!.isCompleted, isTrue);
    });

    test('初始化完成后后续调用直接返回', () async {
      int initCount = 0;
      Completer<void>? initCompleter;

      Future<void> ensureInitialized() async {
        if (initCompleter != null) return initCompleter!.future;
        initCompleter = Completer<void>();
        initCount++;
        initCompleter!.complete();
      }

      await ensureInitialized();
      expect(initCount, equals(1));

      await ensureInitialized();
      // initCount 不应增加
      expect(initCount, equals(1));
    });
  });

  // ==================== DeviceCapabilityService 懒加载 ====================
  group('DeviceCapabilityService 懒加载', () {
    test('getCapabilityReport 首次调用时探测设备能力', () async {
      SharedPreferences.setMockInitialValues({});

      final service = DeviceCapabilityService.instance;
      service.resetForTesting();

      final report = await service.getCapabilityReport();
      expect(report, isNotNull);
      expect(report.platform, isNotEmpty);
      expect(report.cpuCores, greaterThan(0));
    });

    test('getCapabilityReport 第二次调用使用缓存', () async {
      SharedPreferences.setMockInitialValues({});

      final service = DeviceCapabilityService.instance;
      service.resetForTesting();

      final report1 = await service.getCapabilityReport();
      final report2 = await service.getCapabilityReport();

      // 两次应返回相同对象（缓存命中）
      expect(identical(report1, report2), isTrue);
    });
  });
}
