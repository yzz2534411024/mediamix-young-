import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/features/video/core/engines/engine_interfaces.dart';
import 'package:mediamix/features/video/core/engines/playback_error_handler_impl.dart';

void main() {
  group('PlaybackErrorHandlerImpl', () {
    late PlaybackErrorHandlerImpl handler;

    setUp(() {
      handler = PlaybackErrorHandlerImpl();
    });

    tearDown(() {
      handler.dispose();
    });

    // ========================================================================
    // 初始状态
    // ========================================================================
    group('初始状态', () {
      test('retryCount 初始为 0', () {
        expect(handler.retryCount, equals(0));
      });

      test('isWaitingForNetwork 初始为 false', () {
        expect(handler.isWaitingForNetwork, isFalse);
      });

      test('findNextUntriedQuality 初始返回 -1（qualityCount 为 0）', () {
        expect(handler.findNextUntriedQuality(), equals(-1));
      });
    });

    // ========================================================================
    // handleError — 编解码错误
    // ========================================================================
    group('handleError — 编解码错误', () {
      test('codec 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'codec error',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('codec 错误 + 硬解码关闭 → 不降级（走重试流程）', () {
        final result = handler.handleError(
          'codec error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        // 不应降级软解，应走后续逻辑（重试同 URL）
        expect(result.action, isNot(equals(ErrorAction.downgradeToSoftwareDecode)));
      });

      test('decoder 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'decoder failed',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('mediacodec 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'mediacodec error',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('unsupported 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'unsupported format',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('format 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'format not supported',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('avc 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'avc decode error',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('hevc 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'hevc decode error',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('vp9 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'vp9 decode error',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('av1 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'av1 decode error',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('hwdec 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'hwdec error',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('hardware 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'hardware decode failed',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('software 错误 + 硬解码开启 → 降级软解', () {
        final result = handler.handleError(
          'software decode error',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });

      test('编解码错误大小写不敏感', () {
        final result = handler.handleError(
          'CODEC ERROR',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });
    });

    // ========================================================================
    // handleError — 网络错误
    // ========================================================================
    group('handleError — 网络错误', () {
      test('network 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'network error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
        expect(handler.isWaitingForNetwork, isTrue);
      });

      test('connection 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'connection lost',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('timeout 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'timeout error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('dns 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'dns resolution failed',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('unreachable 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'host unreachable',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('refused 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'connection refused',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('socket 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'socket closed',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('host 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'host not found',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('econnreset 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'econnreset',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('econnrefused 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'econnrefused',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('etimedout 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'etimedout',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('enotfound 错误 → 等待网络恢复', () {
        final result = handler.handleError(
          'enotfound',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });

      test('网络错误大小写不敏感', () {
        final result = handler.handleError(
          'NETWORK ERROR',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.waitForNetworkRecovery));
      });
    });

    // ========================================================================
    // handleError — 非网络错误重试
    // ========================================================================
    group('handleError — 非网络错误重试', () {
      test('非网络错误 + retryCount < maxAutoRetry → 重试同 URL', () {
        final result = handler.handleError(
          'some unknown error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.retrySameUrl));
        expect(handler.retryCount, equals(1));
      });

      test('重试次数达到上限后不再重试同 URL', () {
        // 第一次重试
        handler.handleError(
          'some error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(handler.retryCount, equals(1));

        // 第二次调用，retryCount 已达上限，不应再返回 retrySameUrl
        final result = handler.handleError(
          'some error again',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, isNot(equals(ErrorAction.retrySameUrl)));
      });
    });

    // ========================================================================
    // handleError — 清晰度降级
    // ========================================================================
    group('handleError — 清晰度降级', () {
      test('有未尝试清晰度 → 切换到下一个清晰度', () {
        handler.qualityCount = 3;
        // 先消耗掉重试次数
        handler.handleError(
          'some error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );

        // 现在重试次数已达上限，有清晰度选项
        final result = handler.handleError(
          'some error again',
          hardwareDecodingEnabled: false,
          hasQualityOptions: true,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.switchToNextQuality));
        expect(result.nextQualityIndex, isNotNull);
        expect(result.nextQualityIndex, greaterThanOrEqualTo(0));
      });

      test('所有清晰度都已尝试 → 显示错误对话框', () {
        handler.qualityCount = 2;
        // 标记所有清晰度已尝试
        handler.addTriedQualityIndex(0);
        handler.addTriedQualityIndex(1);

        // 消耗重试次数
        handler.handleError(
          'some error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );

        final result = handler.handleError(
          'some error again',
          hardwareDecodingEnabled: false,
          hasQualityOptions: true,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.showErrorDialog));
      });

      test('无清晰度选项 + 重试耗尽 → 显示错误对话框', () {
        handler.qualityCount = 0;
        // 消耗重试次数
        handler.handleError(
          'some error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );

        final result = handler.handleError(
          'some error again',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.showErrorDialog));
      });

      test('切换清晰度时重置重试计数', () {
        handler.qualityCount = 3;
        // 消耗重试次数
        handler.handleError(
          'some error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(handler.retryCount, equals(1));

        // 触发清晰度切换
        handler.handleError(
          'some error again',
          hardwareDecodingEnabled: false,
          hasQualityOptions: true,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(handler.retryCount, equals(0));
      });
    });

    // ========================================================================
    // findNextUntriedQuality
    // ========================================================================
    group('findNextUntriedQuality', () {
      test('qualityCount 为 0 时返回 -1', () {
        handler.qualityCount = 0;
        expect(handler.findNextUntriedQuality(), equals(-1));
      });

      test('没有任何已尝试索引时返回 0', () {
        handler.qualityCount = 3;
        expect(handler.findNextUntriedQuality(), equals(0));
      });

      test('索引 0 已尝试时返回 1', () {
        handler.qualityCount = 3;
        handler.addTriedQualityIndex(0);
        expect(handler.findNextUntriedQuality(), equals(1));
      });

      test('索引 0 和 1 已尝试时返回 2', () {
        handler.qualityCount = 3;
        handler.addTriedQualityIndex(0);
        handler.addTriedQualityIndex(1);
        expect(handler.findNextUntriedQuality(), equals(2));
      });

      test('所有索引都已尝试时返回 -1', () {
        handler.qualityCount = 3;
        handler.addTriedQualityIndex(0);
        handler.addTriedQualityIndex(1);
        handler.addTriedQualityIndex(2);
        expect(handler.findNextUntriedQuality(), equals(-1));
      });
    });

    // ========================================================================
    // addTriedQualityIndex / clearTriedQualityIndices
    // ========================================================================
    group('addTriedQualityIndex / clearTriedQualityIndices', () {
      test('添加已尝试索引后 findNextUntriedQuality 跳过该索引', () {
        handler.qualityCount = 3;
        handler.addTriedQualityIndex(0);
        expect(handler.findNextUntriedQuality(), equals(1));
      });

      test('重复添加同一索引不会影响结果', () {
        handler.qualityCount = 3;
        handler.addTriedQualityIndex(0);
        handler.addTriedQualityIndex(0);
        expect(handler.findNextUntriedQuality(), equals(1));
      });

      test('clearTriedQualityIndices 清除后所有索引可用', () {
        handler.qualityCount = 3;
        handler.addTriedQualityIndex(0);
        handler.addTriedQualityIndex(1);
        handler.addTriedQualityIndex(2);
        expect(handler.findNextUntriedQuality(), equals(-1));

        handler.clearTriedQualityIndices();
        expect(handler.findNextUntriedQuality(), equals(0));
      });
    });

    // ========================================================================
    // resetRetryCount
    // ========================================================================
    group('resetRetryCount', () {
      test('重置后 retryCount 为 0', () {
        handler.handleError(
          'some error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(handler.retryCount, equals(1));

        handler.resetRetryCount();
        expect(handler.retryCount, equals(0));
      });
    });

    // ========================================================================
    // isWaitingForNetwork
    // ========================================================================
    group('isWaitingForNetwork', () {
      test('网络错误后 isWaitingForNetwork 为 true', () {
        handler.handleError(
          'network error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(handler.isWaitingForNetwork, isTrue);
      });

      test('stopNetworkRecoveryMonitoring 后 isWaitingForNetwork 为 false', () {
        handler.handleError(
          'network error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(handler.isWaitingForNetwork, isTrue);

        handler.stopNetworkRecoveryMonitoring();
        expect(handler.isWaitingForNetwork, isFalse);
      });

      test('非网络错误不会设置 isWaitingForNetwork', () {
        handler.handleError(
          'some unknown error',
          hardwareDecodingEnabled: false,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(handler.isWaitingForNetwork, isFalse);
      });
    });

    // ========================================================================
    // dispose
    // ========================================================================
    group('dispose', () {
      test('dispose 不抛出异常', () {
        expect(() => handler.dispose(), returnsNormally);
      });

      test('dispose 后可安全再次调用', () {
        handler.dispose();
        expect(() => handler.dispose(), returnsNormally);
      });
    });

    // ========================================================================
    // handleError — 编解码错误优先级高于网络错误
    // ========================================================================
    group('handleError — 错误优先级', () {
      test('编解码错误优先于网络错误判断', () {
        // 错误信息同时包含 codec 和 network 关键词时，编解码优先
        final result = handler.handleError(
          'codec network error',
          hardwareDecodingEnabled: true,
          hasQualityOptions: false,
          currentQualityIndex: 0,
          lastPlaybackPosition: Duration.zero,
        );
        expect(result.action, equals(ErrorAction.downgradeToSoftwareDecode));
      });
    });
  });
}
