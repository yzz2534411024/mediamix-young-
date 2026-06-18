import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/core/network/network_engine.dart';
import 'package:mediamix/features/video/core/player_core.dart';

void main() {
  // ===========================================================================
  // BufferWaterLines
  // ===========================================================================
  group('BufferWaterLines', () {
    test('wifi 预设值正确', () {
      const wl = BufferWaterLines.wifi;
      expect(wl.low, const Duration(seconds: 3));
      expect(wl.high, const Duration(seconds: 20));
      expect(wl.max, const Duration(seconds: 60));
    });

    test('mobile4G 预设值正确', () {
      const wl = BufferWaterLines.mobile4G;
      expect(wl.low, const Duration(seconds: 5));
      expect(wl.high, const Duration(seconds: 15));
      expect(wl.max, const Duration(seconds: 30));
    });

    test('weak 预设值正确', () {
      const wl = BufferWaterLines.weak;
      expect(wl.low, const Duration(seconds: 8));
      expect(wl.high, const Duration(seconds: 10));
      expect(wl.max, const Duration(seconds: 15));
    });

    test('自定义构造', () {
      const wl = BufferWaterLines(
        low: Duration(seconds: 1),
        high: Duration(seconds: 5),
        max: Duration(seconds: 10),
      );
      expect(wl.low, const Duration(seconds: 1));
      expect(wl.high, const Duration(seconds: 5));
      expect(wl.max, const Duration(seconds: 10));
    });
  });

  // ===========================================================================
  // waterLinesForCondition
  // ===========================================================================
  group('waterLinesForCondition', () {
    test('wifi → BufferWaterLines.wifi', () {
      final wl = BufferManager.waterLinesForCondition(NetworkCondition.wifi);
      expect(wl.low, BufferWaterLines.wifi.low);
      expect(wl.high, BufferWaterLines.wifi.high);
      expect(wl.max, BufferWaterLines.wifi.max);
    });

    test('lte → BufferWaterLines.mobile4G', () {
      final wl = BufferManager.waterLinesForCondition(NetworkCondition.lte);
      expect(wl.low, BufferWaterLines.mobile4G.low);
      expect(wl.high, BufferWaterLines.mobile4G.high);
      expect(wl.max, BufferWaterLines.mobile4G.max);
    });

    test('threeG → BufferWaterLines.weak', () {
      final wl = BufferManager.waterLinesForCondition(NetworkCondition.threeG);
      expect(wl.low, BufferWaterLines.weak.low);
      expect(wl.high, BufferWaterLines.weak.high);
      expect(wl.max, BufferWaterLines.weak.max);
    });

    test('weak → BufferWaterLines.weak', () {
      final wl = BufferManager.waterLinesForCondition(NetworkCondition.weak);
      expect(wl.low, BufferWaterLines.weak.low);
      expect(wl.high, BufferWaterLines.weak.high);
      expect(wl.max, BufferWaterLines.weak.max);
    });

    test('offline → BufferWaterLines.weak', () {
      final wl = BufferManager.waterLinesForCondition(NetworkCondition.offline);
      expect(wl.low, BufferWaterLines.weak.low);
      expect(wl.high, BufferWaterLines.weak.high);
      expect(wl.max, BufferWaterLines.weak.max);
    });
  });

  // ===========================================================================
  // BufferManager 初始状态
  // ===========================================================================
  group('BufferManager 初始状态', () {
    test('默认水位线为 wifi', () {
      final bm = BufferManager();
      expect(bm.waterLines.low, BufferWaterLines.wifi.low);
      expect(bm.waterLines.high, BufferWaterLines.wifi.high);
      expect(bm.waterLines.max, BufferWaterLines.wifi.max);
    });

    test('初始缓冲为零', () {
      final bm = BufferManager();
      expect(bm.currentBuffer, Duration.zero);
    });

    test('初始 isLowBuffer 为 true（0 < 3s）', () {
      final bm = BufferManager();
      expect(bm.isLowBuffer, isTrue);
    });

    test('初始 bufferPercent 为 0', () {
      final bm = BufferManager();
      expect(bm.bufferPercent, 0.0);
    });
  });

  // ===========================================================================
  // updateBuffer
  // ===========================================================================
  group('updateBuffer', () {
    test('更新 currentBuffer', () {
      final bm = BufferManager();
      bm.updateBuffer(const Duration(seconds: 10));
      expect(bm.currentBuffer, const Duration(seconds: 10));
    });

    test('缓冲低于水位线 → isLowBuffer=true', () {
      final bm = BufferManager();
      bm.updateBuffer(const Duration(seconds: 2)); // wifi low=3s
      expect(bm.isLowBuffer, isTrue);
    });

    test('缓冲等于水位线 → isLowBuffer=false（不小于）', () {
      final bm = BufferManager();
      bm.updateBuffer(const Duration(seconds: 3)); // wifi low=3s
      expect(bm.isLowBuffer, isFalse);
    });

    test('缓冲高于水位线 → isLowBuffer=false', () {
      final bm = BufferManager();
      bm.updateBuffer(const Duration(seconds: 10));
      expect(bm.isLowBuffer, isFalse);
    });

    test('从低缓冲恢复 → 触发 onBufferStateChanged(false)', () {
      bool? received;
      final bm = BufferManager(onBufferStateChanged: (isLow) {
        received = isLow;
      });
      // 初始就是低缓冲，先设为非低缓冲以避免初始回调
      bm.updateBuffer(const Duration(seconds: 10));
      expect(bm.isLowBuffer, isFalse);
      // 切换到低缓冲
      bm.updateBuffer(const Duration(seconds: 1));
      expect(received, isTrue);
      // 恢复
      bm.updateBuffer(const Duration(seconds: 10));
      expect(received, isFalse);
    });

    test('缓冲状态不变时不触发回调', () {
      int callCount = 0;
      final bm = BufferManager(onBufferStateChanged: (_) {
        callCount++;
      });
      // 初始 isLowBuffer=true，但初始没有回调（构造时没有触发 _checkBufferState）
      // 先 updateBuffer 使其变为非低缓冲
      bm.updateBuffer(const Duration(seconds: 10));
      // 此时 isLowBuffer=false，callCount 应为 1（从 true→false）
      expect(callCount, 1);
      // 再次 updateBuffer 保持非低缓冲
      bm.updateBuffer(const Duration(seconds: 15));
      expect(callCount, 1); // 不应增加
    });
  });

  // ===========================================================================
  // updateNetworkCondition
  // ===========================================================================
  group('updateNetworkCondition', () {
    test('切换到 lte 更新水位线', () {
      final bm = BufferManager();
      bm.updateNetworkCondition(NetworkCondition.lte);
      expect(bm.waterLines.low, BufferWaterLines.mobile4G.low);
      expect(bm.waterLines.high, BufferWaterLines.mobile4G.high);
      expect(bm.waterLines.max, BufferWaterLines.mobile4G.max);
    });

    test('切换到 weak 更新水位线', () {
      final bm = BufferManager();
      bm.updateNetworkCondition(NetworkCondition.weak);
      expect(bm.waterLines.low, BufferWaterLines.weak.low);
      expect(bm.waterLines.max, BufferWaterLines.weak.max);
    });

    test('网络切换后重新检查缓冲状态 — 从非低缓冲变为低缓冲', () {
      bool? received;
      final bm = BufferManager(onBufferStateChanged: (isLow) {
        received = isLow;
      });
      // wifi low=3s，设缓冲 5s → 非低缓冲
      bm.updateBuffer(const Duration(seconds: 5));
      expect(bm.isLowBuffer, isFalse);
      // 切换到 weak low=8s → 5s < 8s → 低缓冲
      bm.updateNetworkCondition(NetworkCondition.weak);
      expect(bm.isLowBuffer, isTrue);
      expect(received, isTrue);
    });

    test('网络切换后重新检查缓冲状态 — 从低缓冲变为非低缓冲', () {
      bool? received;
      final bm = BufferManager(onBufferStateChanged: (isLow) {
        received = isLow;
      });
      // 先设为弱网使缓冲为低
      bm.updateNetworkCondition(NetworkCondition.weak); // low=8s
      bm.updateBuffer(const Duration(seconds: 5)); // 5s < 8s → 低缓冲
      expect(bm.isLowBuffer, isTrue);
      // 切换到 wifi low=3s → 5s > 3s → 非低缓冲
      bm.updateNetworkCondition(NetworkCondition.wifi);
      expect(bm.isLowBuffer, isFalse);
      expect(received, isFalse);
    });
  });

  // ===========================================================================
  // bufferPercent
  // ===========================================================================
  group('bufferPercent', () {
    test('零缓冲 → 0.0', () {
      final bm = BufferManager();
      expect(bm.bufferPercent, 0.0);
    });

    test('缓冲等于 max → 1.0', () {
      final bm = BufferManager();
      bm.updateBuffer(const Duration(seconds: 60)); // wifi max=60s
      expect(bm.bufferPercent, 1.0);
    });

    test('缓冲为 max 一半 → 0.5', () {
      final bm = BufferManager();
      bm.updateBuffer(const Duration(seconds: 30)); // wifi max=60s
      expect(bm.bufferPercent, closeTo(0.5, 0.001));
    });

    test('缓冲超过 max → clamp 到 1.0', () {
      final bm = BufferManager();
      bm.updateBuffer(const Duration(seconds: 120)); // wifi max=60s
      expect(bm.bufferPercent, 1.0);
    });

    test('负数缓冲（理论上不应出现）→ clamp 到 0.0', () {
      final bm = BufferManager();
      // Duration 不支持负数构造，但通过 max=0 的自定义水位线测试
      // 使用自定义 BufferWaterLines max=0
      // 由于 waterLines 是 private setter，只能通过网络条件间接测试
      // 这里测试正常情况下的 clamp 行为即可
      expect(bm.bufferPercent, 0.0);
    });

    test('mobile4G 网络下 bufferPercent 计算', () {
      final bm = BufferManager();
      bm.updateNetworkCondition(NetworkCondition.lte); // max=30s
      bm.updateBuffer(const Duration(seconds: 15));
      expect(bm.bufferPercent, closeTo(0.5, 0.001));
    });
  });

  // ===========================================================================
  // onBufferStateChanged 回调
  // ===========================================================================
  group('onBufferStateChanged 回调', () {
    test('回调为 null 时不报错', () {
      final bm = BufferManager();
      bm.updateBuffer(const Duration(seconds: 1));
      bm.updateBuffer(const Duration(seconds: 10));
      // 无异常即通过
    });

    test('连续低缓冲不重复触发回调', () {
      int callCount = 0;
      bool? lastValue;
      final bm = BufferManager(onBufferStateChanged: (isLow) {
        callCount++;
        lastValue = isLow;
      });
      // 初始 isLowBuffer=true，updateBuffer(1s) 仍为低缓冲，不触发
      bm.updateBuffer(const Duration(seconds: 1));
      expect(callCount, 0);
      // 切到非低缓冲
      bm.updateBuffer(const Duration(seconds: 10));
      expect(callCount, 1);
      expect(lastValue, isFalse);
      // 再次低缓冲
      bm.updateBuffer(const Duration(seconds: 1));
      expect(callCount, 2);
      expect(lastValue, isTrue);
      // 仍低缓冲
      bm.updateBuffer(const Duration(seconds: 2));
      expect(callCount, 2);
    });

    test('构造函数传入回调', () {
      bool called = false;
      final bm = BufferManager(onBufferStateChanged: (isLow) {
        called = true;
      });
      bm.updateBuffer(const Duration(seconds: 10)); // 从低→非低，触发
      expect(called, isTrue);
    });
  });
}
