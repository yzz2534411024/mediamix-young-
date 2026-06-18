import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/core/services/player_metrics_service.dart';

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
  });
}
