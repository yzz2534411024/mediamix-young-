import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/core/engines/metrics_engine_impl.dart';
import 'package:mediamix/core/services/player_metrics_service.dart';

void main() {
  group('MetricsEngineImpl', () {
    late MetricsEngineImpl engine;

    setUp(() {
      engine = MetricsEngineImpl();
    });

    tearDown(() {
      engine.dispose();
    });

    // ========================================================================
    // hasRecordedFirstFrame
    // ========================================================================
    group('hasRecordedFirstFrame', () {
      test('初始为 false', () {
        expect(engine.hasRecordedFirstFrame, isFalse);
      });

      test('markFirstFrameRecorded 后为 true', () {
        engine.markFirstFrameRecorded();
        expect(engine.hasRecordedFirstFrame, isTrue);
      });
    });

    // ========================================================================
    // markFirstFrameRecorded
    // ========================================================================
    group('markFirstFrameRecorded', () {
      test('多次调用不会出错', () {
        engine.markFirstFrameRecorded();
        engine.markFirstFrameRecorded();
        expect(engine.hasRecordedFirstFrame, isTrue);
      });
    });

    // ========================================================================
    // isBuffering
    // ========================================================================
    group('isBuffering', () {
      test('初始为 false', () {
        expect(engine.isBuffering, isFalse);
      });

      test('setBuffering(true) 后为 true', () {
        engine.setBuffering(true);
        expect(engine.isBuffering, isTrue);
      });

      test('setBuffering(false) 后为 false', () {
        engine.setBuffering(true);
        expect(engine.isBuffering, isTrue);
        engine.setBuffering(false);
        expect(engine.isBuffering, isFalse);
      });
    });

    // ========================================================================
    // setBuffering
    // ========================================================================
    group('setBuffering', () {
      test('可以反复切换状态', () {
        engine.setBuffering(true);
        expect(engine.isBuffering, isTrue);
        engine.setBuffering(false);
        expect(engine.isBuffering, isFalse);
        engine.setBuffering(true);
        expect(engine.isBuffering, isTrue);
      });
    });

    // ========================================================================
    // startSession
    // ========================================================================
    group('startSession', () {
      test('调用后重置 hasRecordedFirstFrame', () {
        engine.markFirstFrameRecorded();
        expect(engine.hasRecordedFirstFrame, isTrue);

        // startSession 委托给 PlayerMetricsService.instance，可能抛异常
        try {
          engine.startSession('test-video-id');
        } catch (_) {
          // 在测试环境中 PlayerMetricsService 可能未完全初始化，忽略异常
        }

        // 无论服务是否成功，本地状态应已重置
        expect(engine.hasRecordedFirstFrame, isFalse);
      });

      test('调用不抛出异常（包装 try-catch）', () {
        expect(
          () => engine.startSession('test-video-id'),
          returnsNormally,
        );
      });
    });

    // ========================================================================
    // recordEvent
    // ========================================================================
    group('recordEvent', () {
      test('调用不抛出异常', () {
        expect(
          () => engine.recordEvent(MetricsEvent.playStart),
          returnsNormally,
        );
      });

      test('带可选参数调用不抛出异常', () {
        expect(
          () => engine.recordEvent(
            MetricsEvent.playError,
            errorMessage: 'test error',
            avSyncOffsetMs: 50,
          ),
          returnsNormally,
        );
      });
    });

    // ========================================================================
    // getCurrentMetrics
    // ========================================================================
    group('getCurrentMetrics', () {
      test('无活跃会话时返回 null', () {
        // 没有先调用 startSession，PlayerMetricsService 无活跃会话
        final result = engine.getCurrentMetrics();
        expect(result, isNull);
      });

      test('调用不抛出异常', () {
        expect(
          () => engine.getCurrentMetrics(),
          returnsNormally,
        );
      });
    });

    // ========================================================================
    // endSession
    // ========================================================================
    group('endSession', () {
      test('无活跃会话时返回 null', () {
        final result = engine.endSession();
        expect(result, isNull);
      });

      test('调用不抛出异常', () {
        expect(
          () => engine.endSession(),
          returnsNormally,
        );
      });
    });

    // ========================================================================
    // dispose
    // ========================================================================
    group('dispose', () {
      test('调用不抛出异常', () {
        expect(() => engine.dispose(), returnsNormally);
      });

      test('dispose 后重置 hasRecordedFirstFrame', () {
        engine.markFirstFrameRecorded();
        expect(engine.hasRecordedFirstFrame, isTrue);
        engine.dispose();
        expect(engine.hasRecordedFirstFrame, isFalse);
      });

      test('dispose 后重置 isBuffering', () {
        engine.setBuffering(true);
        expect(engine.isBuffering, isTrue);
        engine.dispose();
        expect(engine.isBuffering, isFalse);
      });

      test('多次调用 dispose 不抛出异常', () {
        engine.dispose();
        expect(() => engine.dispose(), returnsNormally);
      });
    });

    // ========================================================================
    // 状态管理集成
    // ========================================================================
    group('状态管理集成', () {
      test('完整生命周期：startSession → markFirstFrame → setBuffering → dispose', () {
        // startSession
        try {
          engine.startSession('video-123');
        } catch (_) {}

        expect(engine.hasRecordedFirstFrame, isFalse);
        expect(engine.isBuffering, isFalse);

        // 标记首帧
        engine.markFirstFrameRecorded();
        expect(engine.hasRecordedFirstFrame, isTrue);

        // 缓冲状态
        engine.setBuffering(true);
        expect(engine.isBuffering, isTrue);
        engine.setBuffering(false);
        expect(engine.isBuffering, isFalse);

        // dispose 重置所有状态
        engine.dispose();
        expect(engine.hasRecordedFirstFrame, isFalse);
        expect(engine.isBuffering, isFalse);
      });

      test('startSession 重置首帧标记后可重新标记', () {
        engine.markFirstFrameRecorded();
        expect(engine.hasRecordedFirstFrame, isTrue);

        try {
          engine.startSession('video-456');
        } catch (_) {}

        expect(engine.hasRecordedFirstFrame, isFalse);

        engine.markFirstFrameRecorded();
        expect(engine.hasRecordedFirstFrame, isTrue);
      });
    });
  });
}
