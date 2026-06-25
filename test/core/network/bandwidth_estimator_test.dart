import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
        // 自适应 EWMA 应该接近 800
        expect(estimator.estimateBandwidth(), closeTo(800, 5));
      });

      test('突变采样时 EWMA 逐渐收敛', () {
        // 稳定在低带宽
        estimator.addSample(50000, 1000); // 400 kbps
        estimator.addSample(50000, 1000);
        estimator.addSample(50000, 1000);
        estimator.addSample(50000, 1000);
        expect(estimator.estimateBandwidth(), closeTo(400, 20));

        // 突然跳到高带宽，EWMA 不会立刻完全跳到新值
        estimator.addSample(1000000, 1000); // 8000 kbps
        // 自适应 alpha 会根据方差调整，估计值应介于旧值和新值之间
        final est = estimator.estimateBandwidth();
        expect(est, greaterThan(400));
        expect(est, lessThan(8000));
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
        estimator.addSample(100000, 1000); // 800 kbps
        expect(estimator.peak, closeTo(800, 1));
        estimator.addSample(200000, 1000); // 1600 kbps
        expect(estimator.peak, greaterThanOrEqualTo(800));
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
        for (int i = 0; i < 4; i++) {
          estimator.recordSample(
            connectionKey: 'cdn1',
            bytes: 500000,
            duration: const Duration(milliseconds: 1000),
          );
        }
        final cdn1Estimate = estimator.estimateBandwidth();

        estimator.recordSample(
          connectionKey: 'cdn2',
          bytes: 10,
          duration: const Duration(milliseconds: 1000),
        );
        expect(estimator.estimateBandwidth(), equals(cdn1Estimate));
      });

      test('LRU 淘汰旧连接键', () {
        for (int i = 0; i < 210; i++) {
          for (int j = 0; j < 4; j++) {
            estimator.recordSample(
              connectionKey: 'cdn_$i',
              bytes: 500000,
              duration: const Duration(milliseconds: 1000),
            );
          }
        }
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
        expect(estimator.currentTrend, equals(0));
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

    // =========================================================================
    // 新增：吞吐量预测模型测试
    // =========================================================================

    group('Holt\'s 线性趋势', () {
      test('稳定带宽时趋势接近 0', () {
        for (int i = 0; i < 10; i++) {
          estimator.addSample(100000, 1000); // 800 kbps
        }
        // 稳定带宽，趋势应接近 0
        expect(estimator.currentTrend.abs(), lessThan(100));
      });

      test('持续增长带宽时趋势为正', () {
        // 递增带宽
        for (int i = 1; i <= 10; i++) {
          estimator.addSample(i * 50000, 1000); // 400, 800, 1200, ...
        }
        expect(estimator.currentTrend, greaterThan(0));
      });
    });

    group('置信度计算', () {
      test('无样本时置信度为 0', () {
        expect(estimator.computeConfidence(), equals(0));
      });

      test('单样本时置信度为 0', () {
        estimator.addSample(100000, 1000);
        expect(estimator.computeConfidence(), equals(0));
      });

      test('完全一致的样本置信度为 1', () {
        for (int i = 0; i < 5; i++) {
          estimator.addSample(100000, 1000); // 每次都 800 kbps
        }
        expect(estimator.computeConfidence(), closeTo(1.0, 0.01));
      });

      test('差异很大的样本置信度低', () {
        estimator.addSample(10000, 1000);   // 80 kbps
        estimator.addSample(1000000, 1000); // 8000 kbps
        estimator.addSample(50000, 1000);   // 400 kbps
        estimator.addSample(500000, 1000);  // 4000 kbps
        final confidence = estimator.computeConfidence();
        expect(confidence, lessThan(0.5));
      });
    });

    group('稳定性计算', () {
      test('无样本时稳定性为 0', () {
        expect(estimator.computeStability(), equals(0));
      });

      test('稳定带宽时稳定性高', () {
        for (int i = 0; i < 10; i++) {
          estimator.addSample(100000, 1000);
        }
        expect(estimator.computeStability(), closeTo(1.0, 0.01));
      });
    });

    group('吞吐量预测', () {
      test('无样本时返回空预测', () {
        final pred = estimator.getPrediction();
        expect(pred.predictedKbps, equals(0));
        expect(pred.confidence, equals(0));
        expect(pred.trendKbps, equals(0));
        expect(pred.stability, equals(0));
      });

      test('有样本时预测值合理', () {
        for (int i = 0; i < 10; i++) {
          estimator.addSample(100000, 1000); // 800 kbps
        }
        final pred = estimator.getPrediction();
        expect(pred.predictedKbps, closeTo(800, 100));
        expect(pred.confidence, greaterThan(0.5));
        expect(pred.longTermAverageKbps, closeTo(800, 10));
        expect(pred.stability, greaterThan(0.5));
      });

      test('预测值不为负', () {
        estimator.addSample(10000, 1000);
        estimator.addSample(100, 1000);
        final pred = estimator.getPrediction();
        expect(pred.predictedKbps, greaterThanOrEqualTo(0));
      });
    });

    group('历史带宽持久化', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
      });

      test('保存和加载历史带宽', () async {
        estimator.addSample(500000, 1000); // 4000 kbps
        await estimator.saveHistoryBandwidth();

        final newEstimator = BandwidthEstimator();
        await newEstimator.loadHistoryBandwidth();
        expect(newEstimator.estimateBandwidth(), closeTo(4000, 50));
        newEstimator.dispose();
      });

      test('无历史数据时不初始化', () async {
        await estimator.loadHistoryBandwidth();
        expect(estimator.estimateBandwidth(), equals(0));
      });

      test('估计值为 0 时不保存', () async {
        await estimator.saveHistoryBandwidth();
        // 不应崩溃，静默忽略
      });
    });
  });
}
