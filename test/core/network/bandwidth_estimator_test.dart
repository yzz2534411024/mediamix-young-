import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/core/network/network_engine.dart';

void main() {
  group('BandwidthEstimator', () {
    late BandwidthEstimator estimator;

    setUp(() {
      estimator = BandwidthEstimator();
    });

    tearDown(() {
      estimator.dispose();
    });

    group('addSample — 基本功能', () {
      test('初始状态 estimate 为 0', () {
        expect(estimator.estimateBandwidth(), equals(0));
        expect(estimator.currentBandwidthKbps, equals(0));
        expect(estimator.peak, equals(0));
      });

      test('首次采样作为估计值', () {
        // 100KB 在 1 秒内下载完 → 800 kbps
        estimator.addSample(100000, 1000);
        expect(estimator.estimateBandwidth(), closeTo(800, 1));
      });

      test('多次采样经过 EWMA 平滑', () {
        // 建立基线
        estimator.addSample(100000, 1000); // 800 kbps
        estimator.addSample(100000, 1000); // 800 kbps
        estimator.addSample(100000, 1000); // 800 kbps
        estimator.addSample(100000, 1000); // 800 kbps
        // EWMA 应该接近 800
        expect(estimator.estimateBandwidth(), closeTo(800, 5));
      });

      test('突变采样时 EWMA 逐渐收敛', () {
        // 稳定在低带宽
        estimator.addSample(50000, 1000); // 400 kbps
        estimator.addSample(50000, 1000);
        estimator.addSample(50000, 1000);
        estimator.addSample(50000, 1000);
        expect(estimator.estimateBandwidth(), closeTo(400, 10));

        // 突然跳到高带宽，EWMA 不会立刻完全跳到新值
        estimator.addSample(1000000, 1000); // 8000 kbps
        // 新值 = 0.7 * 8000 + 0.3 * 400 ≈ 5720
        expect(estimator.estimateBandwidth(), closeTo(5720, 50));
      });

      test('零或负值被忽略', () {
        estimator.addSample(0, 1000);
        estimator.addSample(100, 0);
        estimator.addSample(-1, 1000);
        estimator.addSample(100, -1);
        expect(estimator.estimateBandwidth(), equals(0));
        expect(estimator.sampleCount(), equals(0));
      });
    });

    group('peak', () {
      test('峰值随高带宽更新', () {
        estimator.addSample(100000, 1000); // 800 kbps → EWMA = 800, peak = 800
        expect(estimator.peak, closeTo(800, 1));
        // 第二次采样 kbps=1600，EWMA=0.7*1600+0.3*800=1360，peak=max(800,1360)=1360
        estimator.addSample(200000, 1000); // 1600 kbps
        expect(estimator.peak, closeTo(1360, 5));
      });

      test('峰值不会因低带宽下降', () {
        estimator.addSample(500000, 1000); // 4000
        estimator.addSample(500000, 1000);
        estimator.addSample(500000, 1000);
        estimator.addSample(500000, 1000);
        final peak = estimator.peak;
        estimator.addSample(10000, 1000); // 80
        expect(estimator.peak, equals(peak));
      });
    });

    group('滑动窗口', () {
      test('窗口内采样数正确', () {
        for (int i = 0; i < 5; i++) {
          estimator.addSample(100000, 1000);
        }
        expect(estimator.sampleCount(), equals(5));
      });

      test('窗口超过上限时滑动', () {
        for (int i = 0; i < 25; i++) {
          estimator.addSample(100000 + i * 1000, 1000);
        }
        expect(estimator.sampleCount(), lessThanOrEqualTo(21));
      });

      test('窗口平均值合理', () {
        for (int i = 0; i < 10; i++) {
          estimator.addSample(100000, 1000); // 每次 800 kbps
        }
        final avg = estimator.windowAverage();
        expect(avg, closeTo(800, 10));
      });

      test('空窗口返回 0', () {
        expect(estimator.windowAverage(), equals(0));
      });
    });

    group('recordSample — 带连接键', () {
      test('每连接前3个样本被过滤（慢启动）', () {
        // 慢启动阶段：前3个样本被丢弃，不参与 EWMA
        estimator.recordSample(
          connectionKey: 'cdn1',
          bytes: 100,
          duration: const Duration(milliseconds: 1000),
        );
        estimator.recordSample(
          connectionKey: 'cdn1',
          bytes: 200,
          duration: const Duration(milliseconds: 1000),
        );
        estimator.recordSample(
          connectionKey: 'cdn1',
          bytes: 300,
          duration: const Duration(milliseconds: 1000),
        );
        // 前 3 个样本被丢弃，estimate 仍为 0
        expect(estimator.estimateBandwidth(), equals(0));

        // 第4个样本开始应用：800KB/1s = 6400 kbps
        estimator.recordSample(
          connectionKey: 'cdn1',
          bytes: 800000,
          duration: const Duration(milliseconds: 1000),
        );
        expect(estimator.estimateBandwidth(), equals(6400));
      });

      test('不同连接独立计数慢启动', () {
        // cdn1 完成慢启动
        for (int i = 0; i < 4; i++) {
          estimator.recordSample(
            connectionKey: 'cdn1',
            bytes: 500000,
            duration: const Duration(milliseconds: 1000),
          );
        }
        final cdn1Estimate = estimator.estimateBandwidth();

        // cdn2 还是慢启动
        estimator.recordSample(
          connectionKey: 'cdn2',
          bytes: 10,
          duration: const Duration(milliseconds: 1000),
        );
        // cdn2 慢启动样本不影响 estimate
        expect(estimator.estimateBandwidth(), equals(cdn1Estimate));
      });

      test('LRU 淘汰旧连接键', () {
        // 填满超过 200 个连接（每个连接调用4次以通过慢启动）
        for (int i = 0; i < 210; i++) {
          for (int j = 0; j < 4; j++) {
            estimator.recordSample(
              connectionKey: 'cdn_$i',
              bytes: 500000,
              duration: const Duration(milliseconds: 1000),
            );
          }
        }
        // 不应崩溃，最早的连接键被淘汰，estimate 有值
        expect(estimator.estimateBandwidth(), greaterThan(0));
      });
    });

    group('reset', () {
      test('重置后状态归零', () {
        estimator.addSample(500000, 1000);
        expect(estimator.estimateBandwidth(), greaterThan(0));

        estimator.reset();

        expect(estimator.estimateBandwidth(), equals(0));
        expect(estimator.peak, equals(0));
        expect(estimator.sampleCount(), equals(0));
        expect(estimator.windowAverage(), equals(0));
      });
    });

    group('Stream 通知', () {
      test('带宽变化时发出通知', () async {
        final stream = estimator.onBandwidthChanged;
        final future = stream.first;

        estimator.addSample(500000, 1000);

        final value = await future.timeout(
          const Duration(seconds: 1),
        );
        expect(value, greaterThan(0));
      });
    });
  });
}
