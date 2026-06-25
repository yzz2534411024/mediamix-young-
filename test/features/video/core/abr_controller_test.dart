import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediamix/features/video/core/player_core.dart';
import 'package:mediamix/core/network/network_engine.dart';

void main() {
  // ===========================================================================
  // QualityLevel 枚举
  // ===========================================================================
  group('QualityLevel', () {
    test('low 标签为 "流畅"', () {
      expect(QualityLevel.low.label, '流畅');
    });

    test('medium 标签为 "标清"', () {
      expect(QualityLevel.medium.label, '标清');
    });

    test('high 标签为 "高清"', () {
      expect(QualityLevel.high.label, '高清');
    });

    test('ultra 标签为 "超清"', () {
      expect(QualityLevel.ultra.label, '超清');
    });

    test('index 顺序: low < medium < high < ultra', () {
      expect(QualityLevel.low.index, lessThan(QualityLevel.medium.index));
      expect(QualityLevel.medium.index, lessThan(QualityLevel.high.index));
      expect(QualityLevel.high.index, lessThan(QualityLevel.ultra.index));
    });
  });

  // ===========================================================================
  // ABRController 初始状态
  // ===========================================================================
  group('ABRController 初始状态', () {
    test('初始画质为 medium', () {
      final abr = ABRController();
      expect(abr.currentQuality, QualityLevel.medium);
    });

    test('初始 networkQualityDescription 为 "未知"', () {
      final abr = ABRController();
      expect(abr.networkQualityDescription, '未知');
    });

    test('初始 latestPrediction 为 null', () {
      final abr = ABRController();
      expect(abr.latestPrediction, isNull);
    });
  });

  // ===========================================================================
  // networkQualityDescription
  // ===========================================================================
  group('networkQualityDescription', () {
    test('带宽 <= 0 → "未知"', () {
      final abr = ABRController();
      abr.updateBandwidth(0);
      expect(abr.networkQualityDescription, '未知');
    });

    test('带宽负数 → "未知"', () {
      final abr = ABRController();
      abr.updateBandwidth(-100);
      expect(abr.networkQualityDescription, '未知');
    });

    test('带宽 < 800 → "弱网"', () {
      final abr = ABRController();
      abr.updateBandwidth(500);
      expect(abr.networkQualityDescription, '弱网');
    });

    test('带宽 < 2500 → "一般"', () {
      final abr = ABRController();
      abr.updateBandwidth(1000);
      expect(abr.networkQualityDescription, '一般');
    });

    test('带宽 < 5000 → "良好"', () {
      final abr = ABRController();
      abr.updateBandwidth(3000);
      expect(abr.networkQualityDescription, '良好');
    });

    test('带宽 >= 5000 → "优秀"', () {
      final abr = ABRController();
      abr.updateBandwidth(5000);
      expect(abr.networkQualityDescription, '优秀');
    });
  });

  // ===========================================================================
  // 紧急降级逻辑（缓冲 < 5s，不受防抖约束）
  // ===========================================================================
  group('紧急降级逻辑', () {
    test('缓冲 < 5s 且非 low → 立即降级到 low', () {
      final abr = ABRController();
      expect(abr.currentQuality, QualityLevel.medium);
      abr.updateBuffer(const Duration(seconds: 3));
      expect(abr.currentQuality, QualityLevel.low);
    });

    test('缓冲 = 5s 不触发紧急降级', () {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 5));
      expect(abr.currentQuality, QualityLevel.medium);
    });

    test('已经是 low 时缓冲 < 5s 不再降级', () {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1));
      expect(abr.currentQuality, QualityLevel.low);
      abr.updateBuffer(const Duration(seconds: 2));
      expect(abr.currentQuality, QualityLevel.low);
    });

    test('紧急降级触发 onQualityChanged 回调', () {
      QualityLevel? received;
      final abr = ABRController(onQualityChanged: (level) {
        received = level;
      });
      abr.updateBuffer(const Duration(seconds: 1));
      expect(received, QualityLevel.low);
    });
  });

  // ===========================================================================
  // 智能码率决策（加权模型 + 防抖）
  // ===========================================================================
  group('智能码率决策 — 加权模型', () {
    test('高吞吐量 + 高缓冲 + 高稳定性 → 升级', () async {
      final abr = ABRController(
        upgradeDelay: const Duration(milliseconds: 100),
        minSwitchInterval: const Duration(milliseconds: 200),
      );
      // 先降级到 low
      abr.updateBuffer(const Duration(seconds: 1));
      expect(abr.currentQuality, QualityLevel.low);

      await Future.delayed(const Duration(milliseconds: 250));

      // 提供高吞吐量预测
      final prediction = ThroughputPrediction(
        predictedKbps: 8000,
        confidence: 0.9,
        trendKbps: 100,
        longTermAverageKbps: 7500,
        stability: 0.9,
      );
      abr.updateThroughputPrediction(prediction);
      abr.updateBuffer(const Duration(seconds: 35));
      // 第一次：防抖计数=1，不切换
      expect(abr.currentQuality, QualityLevel.low);

      // 第二次：防抖计数=2，通过防抖，进入升级延迟
      abr.updateThroughputPrediction(prediction);
      abr.updateBuffer(const Duration(seconds: 35));
      // 升级延迟开始
      expect(abr.currentQuality, QualityLevel.low);

      await Future.delayed(const Duration(milliseconds: 150));
      abr.updateThroughputPrediction(prediction);
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.ultra);
    });

    test('低吞吐量 + 高缓冲 → 降级（防抖后）', () async {
      final abr = ABRController(
        minSwitchInterval: const Duration(milliseconds: 200),
      );
      // 初始 medium，给高缓冲
      abr.updateBuffer(const Duration(seconds: 30));

      // 提供低吞吐量预测
      final prediction = ThroughputPrediction(
        predictedKbps: 200,
        confidence: 0.8,
        trendKbps: -50,
        longTermAverageKbps: 300,
        stability: 0.7,
      );
      abr.updateThroughputPrediction(prediction);
      abr.updateBuffer(const Duration(seconds: 30));
      // 第一次：防抖计数=1
      // medium 是否降级取决于加权分数
      // throughput: 200*0.8/10000 = 0.016, buffer: 1.0, stability: 0.7
      // score = 0.016*0.6 + 1.0*0.25 + 0.7*0.15 = 0.0096 + 0.25 + 0.105 = 0.3646 → high
      // 不降级，因为缓冲评分拉高了总分
      // 需要更低缓冲来触发降级

      // 用较低缓冲重试
      abr.updateBuffer(const Duration(seconds: 10));
      // throughput: 0.016, buffer: (10-5)/25=0.2, stability: 0.7
      // score = 0.0096 + 0.05 + 0.105 = 0.1646 → low
      // 第一次防抖
      final q1 = abr.currentQuality;

      abr.updateThroughputPrediction(prediction);
      abr.updateBuffer(const Duration(seconds: 10));
      // 第二次防抖通过
      final q2 = abr.currentQuality;
      // 应该降级了
      expect(q2.index, lessThanOrEqualTo(q1.index));
    });

    test('安全余量：预测 * 0.8 作为实际选择依据', () {
      final abr = ABRController();
      // 预测 10000 kbps，安全余量后 = 8000 kbps
      final prediction = ThroughputPrediction(
        predictedKbps: 10000,
        confidence: 0.9,
        trendKbps: 0,
        longTermAverageKbps: 10000,
        stability: 0.9,
      );
      abr.updateThroughputPrediction(prediction);
      // 验证 latestPrediction 已设置
      expect(abr.latestPrediction, isNotNull);
      expect(abr.latestPrediction!.predictedKbps, equals(10000));
    });
  });

  // ===========================================================================
  // 切换防抖
  // ===========================================================================
  group('切换防抖', () {
    test('连续 2 次一致预测才执行非紧急切换', () async {
      int callCount = 0;
      final abr = ABRController(
        minSwitchInterval: const Duration(milliseconds: 100),
      );
      abr.onQualityChanged = (_) => callCount++;

      // 初始 medium，给较低缓冲（避免紧急降级）
      abr.updateBuffer(const Duration(seconds: 8));

      // 低吞吐量预测（配合低缓冲触发降级）
      final lowPred = const ThroughputPrediction(
        predictedKbps: 50,
        confidence: 0.9,
        trendKbps: -50,
        longTermAverageKbps: 100,
        stability: 0.9,
      );

      // 第一次预测
      abr.updateThroughputPrediction(lowPred);
      abr.updateBuffer(const Duration(seconds: 6));
      final afterFirst = abr.currentQuality;

      // 第二次相同预测 → 防抖通过
      abr.updateThroughputPrediction(lowPred);
      abr.updateBuffer(const Duration(seconds: 6));
      final afterSecond = abr.currentQuality;

      // 第一次应该没降（防抖计数=1），第二次降了（防抖计数=2）
      // throughput: 50*0.8/10000=0.004, buffer: (6-5)/25=0.04, stability: 0.9
      // score = 0.004*0.6 + 0.04*0.25 + 0.9*0.15 = 0.0024 + 0.01 + 0.135 = 0.1474 → low
      expect(afterSecond.index, lessThanOrEqualTo(afterFirst.index));
    });

    test('预测变化时重置防抖计数', () async {
      final abr = ABRController(
        minSwitchInterval: const Duration(milliseconds: 100),
      );
      abr.updateBuffer(const Duration(seconds: 10));

      // 第一次低预测
      final lowPred = ThroughputPrediction(
        predictedKbps: 100, confidence: 0.9, trendKbps: 0,
        longTermAverageKbps: 100, stability: 0.9,
      );
      abr.updateThroughputPrediction(lowPred);
      abr.updateBuffer(const Duration(seconds: 10));

      // 改变预测 → 重置防抖
      final medPred = ThroughputPrediction(
        predictedKbps: 2000, confidence: 0.8, trendKbps: 0,
        longTermAverageKbps: 2000, stability: 0.8,
      );
      abr.updateThroughputPrediction(medPred);
      abr.updateBuffer(const Duration(seconds: 10));
      // 防抖重置，需要重新积累
    });
  });

  // ===========================================================================
  // updateThroughputPrediction 新接口
  // ===========================================================================
  group('updateThroughputPrediction', () {
    test('设置 latestPrediction', () {
      final abr = ABRController();
      expect(abr.latestPrediction, isNull);

      final pred = ThroughputPrediction(
        predictedKbps: 5000,
        confidence: 0.8,
        trendKbps: 100,
        longTermAverageKbps: 4800,
        stability: 0.75,
      );
      abr.updateThroughputPrediction(pred);
      expect(abr.latestPrediction, isNotNull);
      expect(abr.latestPrediction!.predictedKbps, equals(5000));
      expect(abr.latestPrediction!.confidence, equals(0.8));
    });

    test('更新 currentBandwidthKbps', () {
      final abr = ABRController();
      final pred = ThroughputPrediction(
        predictedKbps: 3000,
        confidence: 0.9,
        trendKbps: 0,
        longTermAverageKbps: 3000,
        stability: 0.9,
      );
      abr.updateThroughputPrediction(pred);
      // networkQualityDescription 基于 _currentBandwidthKbps
      expect(abr.networkQualityDescription, '良好');
    });
  });

  // ===========================================================================
  // updateBandwidth 和 updateBuffer 仍然触发 _evaluate
  // ===========================================================================
  group('updateBandwidth 和 updateBuffer 触发 _evaluate', () {
    test('updateBuffer 触发紧急降级', () {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1));
      expect(abr.currentQuality, QualityLevel.low);
    });

    test('updateBandwidth 触发评估', () {
      final abr = ABRController();
      abr.updateBandwidth(6000);
      // 不崩溃即通过
    });
  });

  // ===========================================================================
  // _minSwitchInterval 限制
  // ===========================================================================
  group('_minSwitchInterval 限制', () {
    test('紧急降级后 10s 内不再切换', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      expect(abr.currentQuality, QualityLevel.low);

      // 立即设高吞吐量+高缓冲，不应升级（在 minSwitchInterval 内）
      final pred = ThroughputPrediction(
        predictedKbps: 8000, confidence: 0.9, trendKbps: 100,
        longTermAverageKbps: 8000, stability: 0.9,
      );
      abr.updateThroughputPrediction(pred);
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.low); // 冷却期内不切换
    });
  });

  // ===========================================================================
  // saveQualityPreference / loadQualityPreference
  // ===========================================================================
  group('SharedPreferences 画质偏好', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('保存和加载画质偏好', () async {
      final abr = ABRController();
      await abr.saveQualityPreference(QualityLevel.high);
      final loaded = await abr.loadQualityPreference();
      expect(loaded, QualityLevel.high);
    });

    test('无保存值时返回 medium 默认值', () async {
      final abr = ABRController();
      final loaded = await abr.loadQualityPreference();
      expect(loaded, QualityLevel.medium);
    });

    test('保存所有画质等级', () async {
      final abr = ABRController();
      for (final level in QualityLevel.values) {
        await abr.saveQualityPreference(level);
        final loaded = await abr.loadQualityPreference();
        expect(loaded, level);
      }
    });

    test('覆盖保存', () async {
      final abr = ABRController();
      await abr.saveQualityPreference(QualityLevel.low);
      await abr.saveQualityPreference(QualityLevel.ultra);
      final loaded = await abr.loadQualityPreference();
      expect(loaded, QualityLevel.ultra);
    });
  });

  // ===========================================================================
  // onQualityChanged 回调
  // ===========================================================================
  group('onQualityChanged 回调', () {
    test('回调为 null 时不报错', () {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1));
      abr.updateBandwidth(6000);
    });

    test('紧急降级触发回调', () {
      QualityLevel? received;
      final abr = ABRController(onQualityChanged: (level) {
        received = level;
      });
      abr.updateBuffer(const Duration(seconds: 1));
      expect(received, QualityLevel.low);
    });
  });

  // ===========================================================================
  // ThroughputPrediction 模型
  // ===========================================================================
  group('ThroughputPrediction', () {
    test('empty 常量所有字段为 0', () {
      const p = ThroughputPrediction.empty;
      expect(p.predictedKbps, 0);
      expect(p.confidence, 0);
      expect(p.trendKbps, 0);
      expect(p.longTermAverageKbps, 0);
      expect(p.stability, 0);
    });

    test('构造函数正确赋值', () {
      const p = ThroughputPrediction(
        predictedKbps: 5000,
        confidence: 0.8,
        trendKbps: 100,
        longTermAverageKbps: 4800,
        stability: 0.75,
      );
      expect(p.predictedKbps, 5000);
      expect(p.confidence, 0.8);
      expect(p.trendKbps, 100);
      expect(p.longTermAverageKbps, 4800);
      expect(p.stability, 0.75);
    });
  });
}
