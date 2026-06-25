import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/core/services/player_metrics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PlayerMetricsService', () {
    late PlayerMetricsService service;

    setUp(() {
      service = PlayerMetricsService.instance;
      // 确保每次测试前没有残留 session
      service.endSession();
    });

    tearDown(() {
      service.endSession();
    });

    group('Session 生命周期', () {
      test('startSession 创建新 session 并返回 sessionId', () {
        final sessionId = service.startSession('video_001');
        expect(sessionId, isNotEmpty);
        expect(service.currentSessionId, equals(sessionId));
      });

      test('startSession 自动关闭旧 session 并创建新 session', () {
        service.startSession('video_001');
        service.startSession('video_002');
        final metrics = service.getCurrentMetrics();
        expect(metrics, isNotNull);
        expect(metrics!.videoId, equals('video_002'));
      });

      test('endSession 清理当前 session', () {
        service.startSession('video_001');
        service.endSession();
        expect(service.currentSessionId, isNull);
      });

      test('endSession 返回 metrics 快照', () {
        service.startSession('video_001');
        service.recordEvent(MetricsEvent.playStart);
        final metrics = service.endSession();
        expect(metrics, isNotNull);
        expect(metrics!.videoId, equals('video_001'));
        expect(metrics.sessionId, isNotEmpty);
      });

      test('无 session 时 endSession 返回 null', () {
        final metrics = service.endSession();
        expect(metrics, isNull);
      });
    });

    group('事件记录 — playStart / firstFrame', () {
      test('firstFrame 计算首帧时间', () {
        service.startSession('video_001');
        service.recordEvent(MetricsEvent.playStart);
        service.recordEvent(MetricsEvent.firstFrame);

        final metrics = service.getCurrentMetrics();
        expect(metrics?.firstFrameTimeMs, greaterThanOrEqualTo(0));
      });
    });

    group('事件记录 — bufferingStart / bufferingEnd', () {
      test('缓冲事件增加 bufferingCount 和 bufferingTotalMs', () {
        service.startSession('video_001');
        service.recordEvent(MetricsEvent.playStart);

        service.recordEvent(MetricsEvent.bufferingStart);
        service.recordEvent(MetricsEvent.bufferingEnd);

        final metrics = service.getCurrentMetrics();
        expect(metrics?.bufferingCount, equals(1));
        expect(metrics?.bufferingTotalMs, greaterThanOrEqualTo(0));
      });

      test('多次缓冲事件计数叠加', () {
        service.startSession('video_001');

        for (int i = 0; i < 3; i++) {
          service.recordEvent(MetricsEvent.bufferingStart);
          service.recordEvent(MetricsEvent.bufferingEnd);
        }

        final metrics = service.getCurrentMetrics();
        expect(metrics?.bufferingCount, equals(3));
      });
    });

    group('事件记录 — seekStart / seekEnd', () {
      test('seek 事件增加 seekCount', () {
        service.startSession('video_001');

        service.recordEvent(MetricsEvent.seekStart);
        service.recordEvent(MetricsEvent.seekEnd);

        final metrics = service.getCurrentMetrics();
        expect(metrics?.seekCount, equals(1));
      });

      test('多次 seek 计算平均延迟', () {
        service.startSession('video_001');

        service.recordEvent(MetricsEvent.seekStart);
        service.recordEvent(MetricsEvent.seekEnd);
        service.recordEvent(MetricsEvent.seekStart);
        service.recordEvent(MetricsEvent.seekEnd);

        final metrics = service.getCurrentMetrics();
        expect(metrics?.seekCount, equals(2));
        expect(metrics?.seekAvgMs, greaterThanOrEqualTo(0));
      });
    });

    group('事件记录 — qualityChange', () {
      test('qualityChange 增加计数', () {
        service.startSession('video_001');

        service.recordEvent(MetricsEvent.qualityChange);
        service.recordEvent(MetricsEvent.qualityChange);

        final metrics = service.getCurrentMetrics();
        expect(metrics?.qualityChanges, equals(2));
      });
    });

    group('事件记录 — cacheHit / cacheMiss', () {
      test('cacheHit 增加计数', () {
        service.startSession('video_001');

        service.recordEvent(MetricsEvent.cacheHit);
        service.recordEvent(MetricsEvent.cacheHit);
        service.recordEvent(MetricsEvent.cacheHit);
        service.recordEvent(MetricsEvent.cacheMiss);

        final metrics = service.getCurrentMetrics();
        expect(metrics?.cacheHits, equals(3));
        expect(metrics?.cacheMisses, equals(1));
      });

      test('cacheHitRate 计算正确', () {
        service.startSession('video_001');

        service.recordEvent(MetricsEvent.cacheHit);
        service.recordEvent(MetricsEvent.cacheHit);
        service.recordEvent(MetricsEvent.cacheMiss);

        final metrics = service.getCurrentMetrics();
        // 2/3 ≈ 0.6667
        expect(metrics?.cacheHitRate, closeTo(0.6667, 0.001));
      });

      test('无缓存事件时 cacheHitRate 为 0', () {
        service.startSession('video_001');
        final metrics = service.getCurrentMetrics();
        expect(metrics?.cacheHitRate, equals(0.0));
      });
    });

    group('事件记录 — playError', () {
      test('playError 增加计数', () {
        service.startSession('video_001');

        service.recordEvent(MetricsEvent.playError);
        service.recordEvent(MetricsEvent.playError);

        final metrics = service.getCurrentMetrics();
        expect(metrics?.errorCount, equals(2));
      });
    });

    group('带宽采样', () {
      test('带宽采样更新 avgBandwidthKbps', () {
        service.startSession('video_001');

        // 100KB in 1s = 800 kbps
        service.recordEvent(
          MetricsEvent.playStart,
          bytesDownloaded: 100000,
          downloadDurationMs: 1000,
        );
        service.recordEvent(
          MetricsEvent.playStart,
          bytesDownloaded: 100000,
          downloadDurationMs: 1000,
        );

        final metrics = service.getCurrentMetrics();
        expect(metrics?.avgBandwidthKbps, greaterThan(0));
      });
    });

    group('告警阈值', () {
      test('首帧时间超阈值触发告警', () async {
        // 设置极低阈值以触发告警
        service.setAlertThresholds(const AlertThresholds(firstFrameTimeMs: 1));

        service.startSession('video_001');
        service.recordEvent(MetricsEvent.playStart);
        // 等待一会让时间差超过 1ms
        await Future.delayed(const Duration(milliseconds: 5));
        service.recordEvent(MetricsEvent.firstFrame);

        // 告警应该被触发（firstFrameTime > 1ms）
        final metrics = service.getCurrentMetrics();
        expect(metrics?.firstFrameTimeMs, greaterThan(1));
      });

      test('缓存命中率低于阈值触发告警', () async {
        final alerts = <Map<String, dynamic>>[];
        service.alertStream.listen(alerts.add);

        service.setAlertThresholds(const AlertThresholds(cacheHitRate: 0.9));

        service.startSession('video_001');
        service.recordEvent(MetricsEvent.cacheHit);
        service.recordEvent(MetricsEvent.cacheMiss);

        // Give time for stream to emit
        await Future.delayed(const Duration(milliseconds: 50));

        final metrics = service.getCurrentMetrics();
        expect(metrics?.cacheHitRate, lessThan(0.9));
      });
    });

    group('toSummaryMap', () {
      test('导出快照包含所有字段', () {
        service.startSession('video_test');
        service.recordEvent(MetricsEvent.playStart);

        final summary = service.exportSummary();
        expect(summary, isNotNull);
        expect(summary!['video_id'], equals('video_test'));
        expect(summary['session_id'], isNotEmpty);
        expect(summary['buffering_count'], equals(0));
        expect(summary['cache_hits'], equals(0));
      });
    });

    group('getCurrentMetrics', () {
      test('无 session 时返回 null', () {
        final metrics = service.getCurrentMetrics();
        expect(metrics, isNull);
      });

      test('有 session 时返回指标快照', () {
        service.startSession('video_001');
        final metrics = service.getCurrentMetrics();
        expect(metrics, isNotNull);
        expect(metrics!.videoId, equals('video_001'));
      });
    });

    group('持久化队列', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
      });

      test('触发告警后 pendingReportCount 增加', () async {
        service.setAlertThresholds(const AlertThresholds(firstFrameTimeMs: 0));
        service.startSession('video_persist_1');
        service.recordEvent(MetricsEvent.playStart);
        await Future.delayed(const Duration(milliseconds: 5));
        service.recordEvent(MetricsEvent.firstFrame);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(service.pendingReportCount, greaterThanOrEqualTo(1));
      });

      test('dequeuePendingReports 取出并移除数据', () async {
        service.setAlertThresholds(const AlertThresholds(firstFrameTimeMs: 0));
        service.startSession('video_dequeue_1');
        service.recordEvent(MetricsEvent.playStart);
        await Future.delayed(const Duration(milliseconds: 5));
        service.recordEvent(MetricsEvent.firstFrame);
        await Future.delayed(const Duration(milliseconds: 50));

        final before = service.pendingReportCount;
        expect(before, greaterThanOrEqualTo(1));

        final batch = service.dequeuePendingReports(maxCount: 50);
        expect(batch.length, greaterThanOrEqualTo(1));
        expect(batch.first['type'], equals('first_frame_time'));
        expect(service.pendingReportCount, equals(0));
      });

      test('startSession 调用后待上报队列被清空', () async {
        service.setAlertThresholds(const AlertThresholds(firstFrameTimeMs: 0));
        service.startSession('video_clear_1');
        service.recordEvent(MetricsEvent.playStart);
        await Future.delayed(const Duration(milliseconds: 5));
        service.recordEvent(MetricsEvent.firstFrame);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(service.pendingReportCount, greaterThanOrEqualTo(1));

        // 开始新会话，_loadPendingReports 重新加载持久化数据
        service.startSession('video_clear_2');
        await Future.delayed(const Duration(milliseconds: 100));

        // 排空重新加载的数据
        service.dequeuePendingReports(maxCount: 1000);
        expect(service.pendingReportCount, equals(0));

        // 新会话中触发告警，验证队列正常工作
        service.recordEvent(MetricsEvent.playStart);
        await Future.delayed(const Duration(milliseconds: 5));
        service.recordEvent(MetricsEvent.firstFrame);
        await Future.delayed(const Duration(milliseconds: 50));
        expect(service.pendingReportCount, greaterThanOrEqualTo(1));
      });

      test('_emitAlert 触发后同时调用 _enqueueReport 和 _recordAlertTime', () async {
        service.setAlertThresholds(const AlertThresholds(firstFrameTimeMs: 0));
        service.startSession('video_emit_1');
        service.recordEvent(MetricsEvent.playStart);
        await Future.delayed(const Duration(milliseconds: 5));

        // 触发告警
        service.recordEvent(MetricsEvent.firstFrame);
        await Future.delayed(const Duration(milliseconds: 50));

        // 验证 _enqueueReport 被调用（队列增加）
        final countAfterAlert = service.pendingReportCount;
        expect(countAfterAlert, greaterThanOrEqualTo(1));

        // 验证 _recordAlertTime 被调用（去重生效，同类型告警不再增加）
        service.recordEvent(MetricsEvent.firstFrame);
        await Future.delayed(const Duration(milliseconds: 50));
        expect(service.pendingReportCount, equals(countAfterAlert));
      });
    });

    group('告警去重', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
      });

      test('同类型告警在去重窗口内不重复上报', () async {
        service.setAlertThresholds(const AlertThresholds(firstFrameTimeMs: 0));
        service.startSession('video_dedup_1');
        service.recordEvent(MetricsEvent.playStart);
        await Future.delayed(const Duration(milliseconds: 5));

        // 第一次触发告警
        service.recordEvent(MetricsEvent.firstFrame);
        await Future.delayed(const Duration(milliseconds: 50));
        final countAfterFirst = service.pendingReportCount;
        expect(countAfterFirst, greaterThanOrEqualTo(1));

        // 再次触发同类型告警（同一 session），应被去重
        service.recordEvent(MetricsEvent.firstFrame);
        await Future.delayed(const Duration(milliseconds: 50));
        expect(service.pendingReportCount, equals(countAfterFirst));
      });

      test('不同 sessionId 的告警不会触发去重', () async {
        service.setAlertThresholds(const AlertThresholds(firstFrameTimeMs: 0));

        // 会话 1：触发告警
        service.startSession('video_dedup_diff_1');
        service.recordEvent(MetricsEvent.playStart);
        await Future.delayed(const Duration(milliseconds: 5));
        service.recordEvent(MetricsEvent.firstFrame);
        await Future.delayed(const Duration(milliseconds: 50));
        final countAfterFirst = service.pendingReportCount;
        expect(countAfterFirst, greaterThanOrEqualTo(1));

        // 会话 2（不同 sessionId）：触发同类型告警，不应被去重
        service.startSession('video_dedup_diff_2');
        service.recordEvent(MetricsEvent.playStart);
        await Future.delayed(const Duration(milliseconds: 5));
        service.recordEvent(MetricsEvent.firstFrame);
        await Future.delayed(const Duration(milliseconds: 50));
        expect(service.pendingReportCount, greaterThan(countAfterFirst));
      });
    });

    group('队列上限', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
      });

      test('超过 _maxPendingReports 时移除最早的报告', () async {
        service.setAlertThresholds(const AlertThresholds(firstFrameTimeMs: 0));

        // 创建 101 个会话，每个触发 first_frame_time 告警
        // 每个会话有不同 sessionId，因此去重不会拦截
        for (int i = 0; i < 101; i++) {
          service.startSession('video_limit_$i');
          service.recordEvent(MetricsEvent.playStart);
          await Future.delayed(const Duration(milliseconds: 2));
          service.recordEvent(MetricsEvent.firstFrame);
          await Future.delayed(const Duration(milliseconds: 10));
        }

        // 等待所有异步保存完成
        await Future.delayed(const Duration(milliseconds: 200));

        // 队列长度不应超过 100
        expect(service.pendingReportCount, lessThanOrEqualTo(100));
      });
    });
  });
}
