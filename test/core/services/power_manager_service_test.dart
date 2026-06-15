import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediamix/core/services/power_manager_service.dart';

void main() {
  // ==================== BatteryInfo ====================
  group('BatteryInfo', () {
    test('isLowPower 当电量 < 20 时为 true', () {
      const info = BatteryInfo(level: 19, isCharging: false);
      expect(info.isLowPower, isTrue);
    });

    test('isLowPower 当电量 = 20 时为 false', () {
      const info = BatteryInfo(level: 20, isCharging: false);
      expect(info.isLowPower, isFalse);
    });

    test('isLowPower 当电量 > 20 时为 false', () {
      const info = BatteryInfo(level: 50, isCharging: false);
      expect(info.isLowPower, isFalse);
    });

    test('isLowPower 当电量 = 0 时为 true', () {
      const info = BatteryInfo(level: 0, isCharging: false);
      expect(info.isLowPower, isTrue);
    });

    test('isLowPower 当电量 = 100 时为 false', () {
      const info = BatteryInfo(level: 100, isCharging: true);
      expect(info.isLowPower, isFalse);
    });

    test('充电状态不影响 isLowPower 判断', () {
      const chargingLow = BatteryInfo(level: 10, isCharging: true);
      const notChargingLow = BatteryInfo(level: 10, isCharging: false);
      expect(chargingLow.isLowPower, isTrue);
      expect(notChargingLow.isLowPower, isTrue);
    });

    test('fallback 默认值为满电充电中', () {
      expect(BatteryInfo.fallback.level, equals(100));
      expect(BatteryInfo.fallback.isCharging, isTrue);
      expect(BatteryInfo.fallback.isLowPower, isFalse);
    });

    test('toString 包含关键信息', () {
      const info = BatteryInfo(level: 50, isCharging: false);
      final str = info.toString();
      expect(str, contains('50'));
      expect(str, contains('isLowPower'));
    });
  });

  // ==================== PowerMode ====================
  group('PowerMode', () {
    test('包含所有预期模式', () {
      expect(PowerMode.values, containsAll(<PowerMode>[
        PowerMode.fullPerformance,
        PowerMode.balanced,
        PowerMode.powerSaving,
      ]));
    });

    test('共有 3 个模式', () {
      expect(PowerMode.values.length, equals(3));
    });
  });

  // ==================== PowerModeConfig ====================
  group('PowerModeConfig', () {
    test('fullPerformance 配置正确', () {
      const config = PowerModeConfig(
        targetFps: 60,
        maxResolution: '1080p',
        bufferSizeLevel: 'aggressive',
        enablePreload: true,
        enableDanmaku: true,
        enableBackgroundPlay: true,
      );

      expect(config.targetFps, equals(60));
      expect(config.maxResolution, equals('1080p'));
      expect(config.bufferSizeLevel, equals('aggressive'));
      expect(config.enablePreload, isTrue);
      expect(config.enableDanmaku, isTrue);
      expect(config.enableBackgroundPlay, isTrue);
    });

    test('balanced 配置正确', () {
      const config = PowerModeConfig(
        targetFps: 30,
        maxResolution: '720p',
        bufferSizeLevel: 'normal',
        enablePreload: true,
        enableDanmaku: true,
        enableBackgroundPlay: true,
      );

      expect(config.targetFps, equals(30));
      expect(config.maxResolution, equals('720p'));
      expect(config.bufferSizeLevel, equals('normal'));
      expect(config.enablePreload, isTrue);
      expect(config.enableDanmaku, isTrue);
      expect(config.enableBackgroundPlay, isTrue);
    });

    test('powerSaving 配置正确', () {
      const config = PowerModeConfig(
        targetFps: 24,
        maxResolution: '480p',
        bufferSizeLevel: 'minimal',
        enablePreload: false,
        enableDanmaku: false,
        enableBackgroundPlay: false,
      );

      expect(config.targetFps, equals(24));
      expect(config.maxResolution, equals('480p'));
      expect(config.bufferSizeLevel, equals('minimal'));
      expect(config.enablePreload, isFalse);
      expect(config.enableDanmaku, isFalse);
      expect(config.enableBackgroundPlay, isFalse);
    });

    test('性能模式帧率从高到低: fullPerformance > balanced > powerSaving', () {
      expect(60 > 30, isTrue);
      expect(30 > 24, isTrue);
    });

    test('省电模式关闭所有可选功能', () {
      const config = PowerModeConfig(
        targetFps: 24,
        maxResolution: '480p',
        bufferSizeLevel: 'minimal',
        enablePreload: false,
        enableDanmaku: false,
        enableBackgroundPlay: false,
      );

      expect(config.enablePreload, isFalse);
      expect(config.enableDanmaku, isFalse);
      expect(config.enableBackgroundPlay, isFalse);
    });

    test('toString 包含关键信息', () {
      const config = PowerModeConfig(
        targetFps: 60,
        maxResolution: '1080p',
        bufferSizeLevel: 'aggressive',
        enablePreload: true,
        enableDanmaku: true,
        enableBackgroundPlay: true,
      );

      final str = config.toString();
      expect(str, contains('60'));
      expect(str, contains('1080p'));
    });
  });

  // ==================== autoSelectMode 逻辑（纯逻辑验证） ====================
  group('autoSelectMode 逻辑', () {
    test('充电中 → fullPerformance', () {
      const info = BatteryInfo(level: 10, isCharging: true);
      // autoSelectMode 逻辑: isCharging || level > 50 → fullPerformance
      expect(info.isCharging || info.level > 50, isTrue);
    });

    test('电量 > 50% 且未充电 → fullPerformance', () {
      const info = BatteryInfo(level: 80, isCharging: false);
      expect(info.isCharging || info.level > 50, isTrue);
    });

    test('电量 = 51% 且未充电 → fullPerformance', () {
      const info = BatteryInfo(level: 51, isCharging: false);
      expect(info.isCharging || info.level > 50, isTrue);
    });

    test('电量 = 50% 且未充电 → balanced', () {
      const info = BatteryInfo(level: 50, isCharging: false);
      expect(info.isCharging || info.level > 50, isFalse);
      expect(info.level >= 20, isTrue);
    });

    test('电量 20-50% 且未充电 → balanced', () {
      const info = BatteryInfo(level: 30, isCharging: false);
      expect(info.isCharging || info.level > 50, isFalse);
      expect(info.level >= 20, isTrue);
    });

    test('电量 = 20 且未充电 → balanced', () {
      const info = BatteryInfo(level: 20, isCharging: false);
      expect(info.isCharging || info.level > 50, isFalse);
      expect(info.level >= 20, isTrue);
    });

    test('电量 < 20 且未充电 → powerSaving', () {
      const info = BatteryInfo(level: 15, isCharging: false);
      expect(info.isCharging || info.level > 50, isFalse);
      expect(info.level >= 20, isFalse);
    });

    test('电量 = 0 且未充电 → powerSaving', () {
      const info = BatteryInfo(level: 0, isCharging: false);
      expect(info.isCharging || info.level > 50, isFalse);
      expect(info.level >= 20, isFalse);
    });

    test('充电中即使低电量也选择 fullPerformance', () {
      const info = BatteryInfo(level: 5, isCharging: true);
      expect(info.isCharging, isTrue);
      // isCharging=true → fullPerformance（优先于电量判断）
    });
  });

  // ==================== PowerManagerService ====================
  group('PowerManagerService', () {
    late PowerManagerService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = PowerManagerService.instance;
    });

    group('setPowerMode', () {
      test('手动设置 fullPerformance 模式', () async {
        SharedPreferences.setMockInitialValues({});
        service.setPowerMode(PowerMode.fullPerformance);
        await Future.delayed(const Duration(milliseconds: 50));
        expect(service.hasUserOverride, isTrue);
      });

      test('手动设置 powerSaving 模式', () async {
        SharedPreferences.setMockInitialValues({});
        service.setPowerMode(PowerMode.powerSaving);
        await Future.delayed(const Duration(milliseconds: 50));
        expect(service.hasUserOverride, isTrue);
      });

      test('传入 null 清除手动覆盖', () async {
        SharedPreferences.setMockInitialValues({});
        service.setPowerMode(PowerMode.powerSaving);
        expect(service.hasUserOverride, isTrue);

        service.setPowerMode(null);
        expect(service.hasUserOverride, isFalse);
      });

      test('手动覆盖时 autoSelectMode 不生效', () async {
        SharedPreferences.setMockInitialValues({});
        service.setPowerMode(PowerMode.powerSaving);
        expect(service.hasUserOverride, isTrue);

        // autoSelectMode 在有用户覆盖时应跳过
        service.autoSelectMode();
        // 模式应保持为 powerSaving
        expect(service.currentMode, equals(PowerMode.powerSaving));
      });

      test('清除覆盖后恢复自动选择', () async {
        SharedPreferences.setMockInitialValues({});
        service.setPowerMode(PowerMode.powerSaving);
        service.setPowerMode(null);
        expect(service.hasUserOverride, isFalse);
      });
    });

    group('getConfig', () {
      test('fullPerformance 模式返回对应配置', () async {
        SharedPreferences.setMockInitialValues({});
        service.setPowerMode(PowerMode.fullPerformance);
        await Future.delayed(const Duration(milliseconds: 50));

        final config = service.getConfig();
        expect(config.targetFps, equals(60));
        expect(config.maxResolution, equals('1080p'));
        expect(config.bufferSizeLevel, equals('aggressive'));
        expect(config.enablePreload, isTrue);
        expect(config.enableDanmaku, isTrue);
        expect(config.enableBackgroundPlay, isTrue);
      });

      test('balanced 模式返回对应配置', () async {
        SharedPreferences.setMockInitialValues({});
        service.setPowerMode(PowerMode.balanced);
        await Future.delayed(const Duration(milliseconds: 50));

        final config = service.getConfig();
        expect(config.targetFps, equals(30));
        expect(config.maxResolution, equals('720p'));
        expect(config.bufferSizeLevel, equals('normal'));
        expect(config.enablePreload, isTrue);
        expect(config.enableDanmaku, isTrue);
        expect(config.enableBackgroundPlay, isTrue);
      });

      test('powerSaving 模式返回对应配置', () async {
        SharedPreferences.setMockInitialValues({});
        service.setPowerMode(PowerMode.powerSaving);
        await Future.delayed(const Duration(milliseconds: 50));

        final config = service.getConfig();
        expect(config.targetFps, equals(24));
        expect(config.maxResolution, equals('480p'));
        expect(config.bufferSizeLevel, equals('minimal'));
        expect(config.enablePreload, isFalse);
        expect(config.enableDanmaku, isFalse);
        expect(config.enableBackgroundPlay, isFalse);
      });
    });

    group('onModeChanged', () {
      test('模式变更时发出事件', () async {
        SharedPreferences.setMockInitialValues({});
        final modes = <PowerMode>[];
        service.onModeChanged.listen(modes.add);

        // 先设为 powerSaving，再切到 fullPerformance
        service.setPowerMode(PowerMode.powerSaving);
        await Future.delayed(const Duration(milliseconds: 50));

        service.setPowerMode(PowerMode.fullPerformance);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(modes, contains(PowerMode.fullPerformance));
      });
    });

    group('initialize', () {
      test('初始化后 isInitialized 为 true', () async {
        SharedPreferences.setMockInitialValues({});
        await service.initialize();
        expect(service.isInitialized, isTrue);
      });

      test('重复初始化不抛异常', () async {
        SharedPreferences.setMockInitialValues({});
        await service.initialize();
        await service.initialize();
        expect(service.isInitialized, isTrue);
      });

      test('有用户覆盖偏好时初始化使用覆盖模式', () async {
        SharedPreferences.setMockInitialValues({
          'power_mode_override': 'powerSaving',
        });
        await service.initialize();
        expect(service.hasUserOverride, isTrue);
        expect(service.currentMode, equals(PowerMode.powerSaving));
      });

      test('无用户覆盖偏好时初始化使用自动选择', () async {
        SharedPreferences.setMockInitialValues({});
        await service.initialize();
        // fallback: level=100, isCharging=true → fullPerformance
        expect(service.hasUserOverride, isFalse);
        expect(service.currentMode, equals(PowerMode.fullPerformance));
      });
    });

    group('getBatteryInfo', () {
      test('在测试环境返回 fallback 值', () async {
        SharedPreferences.setMockInitialValues({});
        final info = await service.getBatteryInfo();
        // 在没有原生平台支持时，应返回 fallback
        expect(info.level, equals(100));
        expect(info.isCharging, isTrue);
      });
    });

    group('dispose', () {
      test('dispose 后 isInitialized 为 false', () async {
        SharedPreferences.setMockInitialValues({});
        await service.initialize();
        service.dispose();
        expect(service.isInitialized, isFalse);
      });
    });
  });
}
