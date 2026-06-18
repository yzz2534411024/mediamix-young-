import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediamix/features/video/core/player_core.dart';

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

    test('带宽 = 799 → "弱网"', () {
      final abr = ABRController();
      abr.updateBandwidth(799);
      expect(abr.networkQualityDescription, '弱网');
    });

    test('带宽 < 2500 → "一般"', () {
      final abr = ABRController();
      abr.updateBandwidth(1000);
      expect(abr.networkQualityDescription, '一般');
    });

    test('带宽 = 2499 → "一般"', () {
      final abr = ABRController();
      abr.updateBandwidth(2499);
      expect(abr.networkQualityDescription, '一般');
    });

    test('带宽 < 5000 → "良好"', () {
      final abr = ABRController();
      abr.updateBandwidth(3000);
      expect(abr.networkQualityDescription, '良好');
    });

    test('带宽 = 4999 → "良好"', () {
      final abr = ABRController();
      abr.updateBandwidth(4999);
      expect(abr.networkQualityDescription, '良好');
    });

    test('带宽 >= 5000 → "优秀"', () {
      final abr = ABRController();
      abr.updateBandwidth(5000);
      expect(abr.networkQualityDescription, '优秀');
    });

    test('带宽 10000 → "优秀"', () {
      final abr = ABRController();
      abr.updateBandwidth(10000);
      expect(abr.networkQualityDescription, '优秀');
    });
  });

  // ===========================================================================
  // _qualityForBandwidth（通过 updateBandwidth 间接测试）
  // ===========================================================================
  group('_qualityForBandwidth', () {
    test('带宽 <= 0 → low', () {
      final abr = ABRController();
      abr.updateBandwidth(0);
      // 需要缓冲 > 30s 才会升级，初始 medium 不会因 low bandwidth 降级
      // 降级只在 buffer < 5s 时触发
      // 间接验证：设低缓冲触发降级后，高缓冲+低带宽不会升级
      abr.updateBuffer(const Duration(seconds: 1)); // 触发降级到 low
      expect(abr.currentQuality, QualityLevel.low);
    });

    test('带宽 < 800 → low', () async {
      final abr = ABRController();
      // 先降级到 low
      abr.updateBuffer(const Duration(seconds: 1));
      expect(abr.currentQuality, QualityLevel.low);
      // 然后设高缓冲 + 低带宽，不应升级
      await Future.delayed(const Duration(seconds: 11)); // 等待 minSwitchInterval
      abr.updateBandwidth(500);
      abr.updateBuffer(const Duration(seconds: 35));
      // 即使等 5s 延迟，带宽只支持 low，不会升级
      expect(abr.currentQuality, QualityLevel.low);
    });

    test('带宽 800-2499 → medium', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      expect(abr.currentQuality, QualityLevel.low);

      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(1500);
      abr.updateBuffer(const Duration(seconds: 35));
      // 需要等 _upgradeDelay (5s)，但 _highBandwidthStart 刚设
      expect(abr.currentQuality, QualityLevel.low); // 还没过 5s

      await Future.delayed(const Duration(seconds: 6));
      abr.updateBuffer(const Duration(seconds: 35)); // 再次触发 evaluate
      expect(abr.currentQuality, QualityLevel.medium);
    });

    test('带宽 2500-4999 → high', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      expect(abr.currentQuality, QualityLevel.low);

      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(3000);
      abr.updateBuffer(const Duration(seconds: 35));

      await Future.delayed(const Duration(seconds: 6));
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.high);
    });

    test('带宽 >= 5000 → ultra', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      expect(abr.currentQuality, QualityLevel.low);

      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(6000);
      abr.updateBuffer(const Duration(seconds: 35));

      await Future.delayed(const Duration(seconds: 6));
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.ultra);
    });
  });

  // ===========================================================================
  // 降级逻辑
  // ===========================================================================
  group('降级逻辑', () {
    test('缓冲 < 5s 且非 low → 降级到 low', () {
      final abr = ABRController();
      expect(abr.currentQuality, QualityLevel.medium); // 初始 medium
      abr.updateBuffer(const Duration(seconds: 3)); // < 5s
      expect(abr.currentQuality, QualityLevel.low);
    });

    test('缓冲 = 5s 不触发降级（不小于 5s）', () {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 5));
      expect(abr.currentQuality, QualityLevel.medium); // 不变
    });

    test('缓冲 > 5s 不触发降级', () {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 10));
      expect(abr.currentQuality, QualityLevel.medium);
    });

    test('已经是 low 时缓冲 < 5s 不再降级', () {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1));
      expect(abr.currentQuality, QualityLevel.low);
      // 再次触发
      abr.updateBuffer(const Duration(seconds: 2));
      expect(abr.currentQuality, QualityLevel.low);
    });

    test('降级触发 onQualityChanged 回调', () {
      QualityLevel? received;
      final abr = ABRController(onQualityChanged: (level) {
        received = level;
      });
      abr.updateBuffer(const Duration(seconds: 1));
      expect(received, QualityLevel.low);
    });
  });

  // ===========================================================================
  // 升级逻辑
  // ===========================================================================
  group('升级逻辑', () {
    test('缓冲 <= 30s 不触发升级', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(6000);
      abr.updateBuffer(const Duration(seconds: 30)); // 不大于 30s
      expect(abr.currentQuality, QualityLevel.low);
    });

    test('缓冲 > 30s 但带宽不支持更高不升级', () async {
      final abr = ABRController();
      // 初始 medium，带宽 500 只支持 low，不会升级
      abr.updateBandwidth(500);
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.medium); // target=low, index < medium
    });

    test('缓冲 > 30s 且带宽支持 → 需等待 _upgradeDelay(5s) 才升级', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(6000);
      abr.updateBuffer(const Duration(seconds: 35));
      // _highBandwidthStart 刚设置，还没过 5s
      expect(abr.currentQuality, QualityLevel.low);

      await Future.delayed(const Duration(seconds: 6));
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.ultra);
    });

    test('升级触发 onQualityChanged 回调', () async {
      QualityLevel? received;
      final abr = ABRController(onQualityChanged: (level) {
        received = level;
      });
      abr.updateBuffer(const Duration(seconds: 1)); // 降级
      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(6000);
      abr.updateBuffer(const Duration(seconds: 35));
      await Future.delayed(const Duration(seconds: 6));
      abr.updateBuffer(const Duration(seconds: 35));
      expect(received, QualityLevel.ultra);
    });

    test('缓冲降回 <= 30s 时重置 _highBandwidthStart', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(6000);
      abr.updateBuffer(const Duration(seconds: 35)); // 开始计时
      // 缓冲降回
      abr.updateBuffer(const Duration(seconds: 20)); // _highBandwidthStart = null
      // 再升回 > 30s
      abr.updateBuffer(const Duration(seconds: 35)); // 重新开始计时
      expect(abr.currentQuality, QualityLevel.low); // 还没过 5s
    });

    test('target 等级不高于当前时不升级且重置 _highBandwidthStart', () async {
      final abr = ABRController();
      // 初始 medium，带宽 1500 → target=medium，不高于当前
      abr.updateBandwidth(1500);
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.medium); // 不变
    });
  });

  // ===========================================================================
  // _minSwitchInterval 限制
  // ===========================================================================
  group('_minSwitchInterval 限制', () {
    test('切换后 10s 内不再切换', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      expect(abr.currentQuality, QualityLevel.low);

      // 立即设高缓冲+高带宽，不应升级（在 minSwitchInterval 内）
      abr.updateBandwidth(6000);
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.low);
    });

    test('10s 后可以再次切换', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(6000);
      abr.updateBuffer(const Duration(seconds: 35));
      // _highBandwidthStart 刚设
      await Future.delayed(const Duration(seconds: 6));
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.ultra);
    });
  });

  // ===========================================================================
  // 逐步升级
  // ===========================================================================
  group('逐步升级', () {
    test('从 low 逐步升级到 medium → high → ultra', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      expect(abr.currentQuality, QualityLevel.low);

      // 升级到 medium
      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(1500);
      abr.updateBuffer(const Duration(seconds: 35));
      await Future.delayed(const Duration(seconds: 6));
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.medium);

      // 升级到 high
      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(3000);
      abr.updateBuffer(const Duration(seconds: 35));
      await Future.delayed(const Duration(seconds: 6));
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.high);

      // 升级到 ultra
      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(6000);
      abr.updateBuffer(const Duration(seconds: 35));
      await Future.delayed(const Duration(seconds: 6));
      abr.updateBuffer(const Duration(seconds: 35));
      expect(abr.currentQuality, QualityLevel.ultra);
    });
  });

  // ===========================================================================
  // 降级打断升级等待
  // ===========================================================================
  group('降级打断升级等待', () {
    test('升级等待期间缓冲降低 → 降级到 low', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(6000);
      abr.updateBuffer(const Duration(seconds: 35)); // 开始升级等待
      // 缓冲降低
      await Future.delayed(const Duration(seconds: 2));
      abr.updateBuffer(const Duration(seconds: 3)); // < 5s → 降级
      expect(abr.currentQuality, QualityLevel.low);
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
      // 无异常即通过
    });

    test('相同画质不触发回调（_switchQuality 内部判断）', () async {
      int callCount = 0;
      final abr = ABRController(onQualityChanged: (_) {
        callCount++;
      });
      // 初始 medium，缓冲 > 30s + 带宽支持 medium → target=medium，不升级
      abr.updateBandwidth(1500);
      abr.updateBuffer(const Duration(seconds: 35));
      expect(callCount, 0);
    });
  });

  // ===========================================================================
  // updateBandwidth 和 updateBuffer 都触发 _evaluate
  // ===========================================================================
  group('updateBandwidth 和 updateBuffer 触发 _evaluate', () {
    test('updateBandwidth 触发评估', () async {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 降级到 low
      await Future.delayed(const Duration(seconds: 11));
      abr.updateBandwidth(6000); // 触发 _evaluate，但 buffer 仍 < 5s
      expect(abr.currentQuality, QualityLevel.low); // 不升级
    });

    test('updateBuffer 触发评估', () {
      final abr = ABRController();
      abr.updateBuffer(const Duration(seconds: 1)); // 触发降级
      expect(abr.currentQuality, QualityLevel.low);
    });
  });
}
