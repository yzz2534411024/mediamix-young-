import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mediamix/core/services/device_capability_service.dart';

void main() {
  // ==================== CodecCapability ====================
  group('CodecCapability', () {
    test('属性赋值正确', () {
      const cap = CodecCapability(
        codec: 'H.264',
        maxWidth: 1920,
        maxHeight: 1080,
        hardwareDecodingSupported: true,
      );

      expect(cap.codec, equals('H.264'));
      expect(cap.maxWidth, equals(1920));
      expect(cap.maxHeight, equals(1080));
      expect(cap.hardwareDecodingSupported, isTrue);
    });

    group('toJson', () {
      test('序列化包含所有字段', () {
        const cap = CodecCapability(
          codec: 'H.265',
          maxWidth: 3840,
          maxHeight: 2160,
          hardwareDecodingSupported: false,
        );

        final json = cap.toJson();

        expect(json['codec'], equals('H.265'));
        expect(json['maxWidth'], equals(3840));
        expect(json['maxHeight'], equals(2160));
        expect(json['hardwareDecodingSupported'], isFalse);
      });

      test('hardwareDecodingSupported=true 序列化正确', () {
        const cap = CodecCapability(
          codec: 'VP9',
          maxWidth: 1920,
          maxHeight: 1080,
          hardwareDecodingSupported: true,
        );

        final json = cap.toJson();
        expect(json['hardwareDecodingSupported'], isTrue);
      });
    });

    group('fromJson', () {
      test('反序列化包含所有字段', () {
        final json = <String, dynamic>{
          'codec': 'AV1',
          'maxWidth': 1920,
          'maxHeight': 1080,
          'hardwareDecodingSupported': false,
        };

        final cap = CodecCapability.fromJson(json);

        expect(cap.codec, equals('AV1'));
        expect(cap.maxWidth, equals(1920));
        expect(cap.maxHeight, equals(1080));
        expect(cap.hardwareDecodingSupported, isFalse);
      });

      test('toJson → fromJson 往返一致', () {
        const original = CodecCapability(
          codec: 'H.264',
          maxWidth: 3840,
          maxHeight: 2160,
          hardwareDecodingSupported: true,
        );

        final json = original.toJson();
        final restored = CodecCapability.fromJson(json);

        expect(restored.codec, equals(original.codec));
        expect(restored.maxWidth, equals(original.maxWidth));
        expect(restored.maxHeight, equals(original.maxHeight));
        expect(
          restored.hardwareDecodingSupported,
          equals(original.hardwareDecodingSupported),
        );
      });

      test('多个编解码器 toJson/fromJson 往返一致', () {
        const codecs = [
          CodecCapability(
            codec: 'H.264',
            maxWidth: 1920,
            maxHeight: 1080,
            hardwareDecodingSupported: true,
          ),
          CodecCapability(
            codec: 'H.265',
            maxWidth: 3840,
            maxHeight: 2160,
            hardwareDecodingSupported: false,
          ),
          CodecCapability(
            codec: 'VP9',
            maxWidth: 1920,
            maxHeight: 1080,
            hardwareDecodingSupported: true,
          ),
          CodecCapability(
            codec: 'AV1',
            maxWidth: 1920,
            maxHeight: 1080,
            hardwareDecodingSupported: false,
          ),
        ];

        for (final original in codecs) {
          final json = original.toJson();
          final restored = CodecCapability.fromJson(json);

          expect(restored.codec, equals(original.codec));
          expect(restored.maxWidth, equals(original.maxWidth));
          expect(restored.maxHeight, equals(original.maxHeight));
          expect(
            restored.hardwareDecodingSupported,
            equals(original.hardwareDecodingSupported),
          );
        }
      });
    });
  });

  // ==================== DeviceCapabilityReport ====================
  group('DeviceCapabilityReport', () {
    test('属性赋值正确', () {
      const report = DeviceCapabilityReport(
        platform: 'android',
        cpuArch: 'arm64',
        totalRamMB: 4096,
        cpuCores: 8,
        codecCapabilities: [],
        isLowEndDevice: false,
      );

      expect(report.platform, equals('android'));
      expect(report.cpuArch, equals('arm64'));
      expect(report.totalRamMB, equals(4096));
      expect(report.cpuCores, equals(8));
      expect(report.codecCapabilities, isEmpty);
      expect(report.isLowEndDevice, isFalse);
    });

    group('recommendedMaxResolution', () {
      test('低端设备返回 720p', () {
        const report = DeviceCapabilityReport(
          platform: 'android',
          cpuArch: 'arm',
          totalRamMB: 8192,
          cpuCores: 8,
          codecCapabilities: [],
          isLowEndDevice: true,
        );

        expect(report.recommendedMaxResolution, equals('720p'));
      });

      test('非低端设备且 RAM < 4000MB 返回 1080p', () {
        const report = DeviceCapabilityReport(
          platform: 'android',
          cpuArch: 'arm64',
          totalRamMB: 3000,
          cpuCores: 4,
          codecCapabilities: [],
          isLowEndDevice: false,
        );

        expect(report.recommendedMaxResolution, equals('1080p'));
      });

      test('非低端设备且 RAM = 4000MB 返回 4K', () {
        const report = DeviceCapabilityReport(
          platform: 'android',
          cpuArch: 'arm64',
          totalRamMB: 4000,
          cpuCores: 8,
          codecCapabilities: [],
          isLowEndDevice: false,
        );

        expect(report.recommendedMaxResolution, equals('4K'));
      });

      test('非低端设备且 RAM > 4000MB 返回 4K', () {
        const report = DeviceCapabilityReport(
          platform: 'android',
          cpuArch: 'arm64',
          totalRamMB: 8192,
          cpuCores: 8,
          codecCapabilities: [],
          isLowEndDevice: false,
        );

        expect(report.recommendedMaxResolution, equals('4K'));
      });

      test('低端设备即使 RAM 充足也返回 720p', () {
        const report = DeviceCapabilityReport(
          platform: 'android',
          cpuArch: 'arm64',
          totalRamMB: 8192,
          cpuCores: 8,
          codecCapabilities: [],
          isLowEndDevice: true,
        );

        expect(report.recommendedMaxResolution, equals('720p'));
      });
    });

    group('recommendedMaxFps', () {
      test('低端设备返回 24', () {
        const report = DeviceCapabilityReport(
          platform: 'android',
          cpuArch: 'arm',
          totalRamMB: 1024,
          cpuCores: 2,
          codecCapabilities: [],
          isLowEndDevice: true,
        );

        expect(report.recommendedMaxFps, equals(24));
      });

      test('非低端设备且 RAM < 4000MB 返回 30', () {
        const report = DeviceCapabilityReport(
          platform: 'android',
          cpuArch: 'arm64',
          totalRamMB: 3000,
          cpuCores: 4,
          codecCapabilities: [],
          isLowEndDevice: false,
        );

        expect(report.recommendedMaxFps, equals(30));
      });

      test('非低端设备且 RAM >= 4000MB 返回 60', () {
        const report = DeviceCapabilityReport(
          platform: 'android',
          cpuArch: 'arm64',
          totalRamMB: 4096,
          cpuCores: 8,
          codecCapabilities: [],
          isLowEndDevice: false,
        );

        expect(report.recommendedMaxFps, equals(60));
      });
    });

    group('recommendHardwareDecoding', () {
      test('低端设备不推荐硬解码', () {
        const report = DeviceCapabilityReport(
          platform: 'android',
          cpuArch: 'arm',
          totalRamMB: 1024,
          cpuCores: 2,
          codecCapabilities: [],
          isLowEndDevice: true,
        );

        expect(report.recommendHardwareDecoding, isFalse);
      });

      test('非低端设备推荐硬解码', () {
        const report = DeviceCapabilityReport(
          platform: 'android',
          cpuArch: 'arm64',
          totalRamMB: 4096,
          cpuCores: 8,
          codecCapabilities: [],
          isLowEndDevice: false,
        );

        expect(report.recommendHardwareDecoding, isTrue);
      });
    });
  });

  // ==================== DeviceCapabilityService ====================
  group('DeviceCapabilityService', () {
    late DeviceCapabilityService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = DeviceCapabilityService.instance;
    });

    // hasDetected 测试放在最前面，避免 _cachedReport 缓存影响
    group('hasDetected', () {
      test('初始时返回 false', () async {
        SharedPreferences.setMockInitialValues({});
        final result = await service.hasDetected();
        expect(result, isFalse);
      });

      test('获取报告后返回 true', () async {
        SharedPreferences.setMockInitialValues({});
        await service.getCapabilityReport();
        final result = await service.hasDetected();
        expect(result, isTrue);
      });
    });

    group('getCapabilityReport', () {
      test('返回有效的设备能力报告', () async {
        SharedPreferences.setMockInitialValues({});
        final report = await service.getCapabilityReport();

        expect(report, isNotNull);
        expect(report.platform, isNotEmpty);
        expect(report.cpuArch, isNotEmpty);
        expect(report.totalRamMB, greaterThan(0));
        expect(report.cpuCores, greaterThan(0));
        expect(report.codecCapabilities, isNotEmpty);
      });

      test('报告包含基本编解码器', () async {
        SharedPreferences.setMockInitialValues({});
        final report = await service.getCapabilityReport();

        final codecs = report.codecCapabilities.map((c) => c.codec).toList();
        expect(codecs, contains('H.264'));
      });

      test('连续调用返回相同报告（缓存）', () async {
        SharedPreferences.setMockInitialValues({});
        final report1 = await service.getCapabilityReport();
        final report2 = await service.getCapabilityReport();

        expect(identical(report1, report2), isTrue);
      });
    });

    group('getCodecCapability', () {
      test('精确匹配编码格式和分辨率', () async {
        SharedPreferences.setMockInitialValues({});
        final cap = await service.getCodecCapability(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        expect(cap, isNotNull);
        expect(cap!.codec, equals('H.264'));
        expect(cap.maxWidth, greaterThanOrEqualTo(1920));
        expect(cap.maxHeight, greaterThanOrEqualTo(1080));
      });

      test('编码格式大小写不敏感', () async {
        SharedPreferences.setMockInitialValues({});
        final capLower = await service.getCodecCapability(
          codec: 'h.264',
          width: 1920,
          height: 1080,
        );
        final capUpper = await service.getCodecCapability(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        expect(capLower, isNotNull);
        expect(capUpper, isNotNull);
        expect(
          capLower!.codec.toUpperCase(),
          equals(capUpper!.codec.toUpperCase()),
        );
      });

      test('选择满足要求的最小分辨率匹配', () async {
        SharedPreferences.setMockInitialValues({});
        // 请求 1920x1080 的 H.264，应返回 1920x1080 而非 3840x2160
        final cap = await service.getCodecCapability(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        expect(cap, isNotNull);
        // 如果有 1920x1080 的条目，应优先返回它（最小面积匹配）
        expect(
          cap!.maxWidth * cap.maxHeight,
          lessThanOrEqualTo(1920 * 1080 + 1),
        );
      });

      test('超出最大分辨率返回 null', () async {
        SharedPreferences.setMockInitialValues({});
        // 请求 7680x4320 (8K) 的 H.264，超出默认能力表最大 3840x2160
        final cap = await service.getCodecCapability(
          codec: 'H.264',
          width: 7680,
          height: 4320,
        );

        expect(cap, isNull);
      });

      test('不存在的编码格式返回 null', () async {
        SharedPreferences.setMockInitialValues({});
        final cap = await service.getCodecCapability(
          codec: 'UNKNOWN_CODEC',
          width: 1920,
          height: 1080,
        );

        expect(cap, isNull);
      });

      test('宽度和高度都必须满足', () async {
        SharedPreferences.setMockInitialValues({});
        // 请求宽度满足但高度不满足
        final cap = await service.getCodecCapability(
          codec: 'H.264',
          width: 1920,
          height: 9999,
        );

        expect(cap, isNull);
      });
    });

    group('canHardwareDecode', () {
      test('支持硬解码的编解码组合返回 true', () async {
        SharedPreferences.setMockInitialValues({});
        final result = await service.canHardwareDecode(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        expect(result, isTrue);
      });

      test('不存在的编解码组合返回 false', () async {
        SharedPreferences.setMockInitialValues({});
        final result = await service.canHardwareDecode(
          codec: 'NONEXISTENT',
          width: 1920,
          height: 1080,
        );

        expect(result, isFalse);
      });
    });

    group('recordHardwareDecodeFailure & isHardwareDecodeKnownUnsupported', () {
      test('初始时不应标记为已知不支持', () async {
        SharedPreferences.setMockInitialValues({});
        final result = await service.isHardwareDecodeKnownUnsupported(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        expect(result, isFalse);
      });

      test('记录1次失败后不应标记为已知不支持', () async {
        SharedPreferences.setMockInitialValues({});
        await service.recordHardwareDecodeFailure(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        final result = await service.isHardwareDecodeKnownUnsupported(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        expect(result, isFalse);
      });

      test('记录2次失败后不应标记为已知不支持', () async {
        SharedPreferences.setMockInitialValues({});
        await service.recordHardwareDecodeFailure(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );
        await service.recordHardwareDecodeFailure(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        final result = await service.isHardwareDecodeKnownUnsupported(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        expect(result, isFalse);
      });

      test('记录3次失败后标记为已知不支持', () async {
        SharedPreferences.setMockInitialValues({});
        await service.recordHardwareDecodeFailure(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );
        await service.recordHardwareDecodeFailure(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );
        await service.recordHardwareDecodeFailure(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        final result = await service.isHardwareDecodeKnownUnsupported(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        expect(result, isTrue);
      });

      test('超过3次失败仍标记为已知不支持', () async {
        SharedPreferences.setMockInitialValues({});
        for (int i = 0; i < 5; i++) {
          await service.recordHardwareDecodeFailure(
            codec: 'H.265',
            width: 3840,
            height: 2160,
          );
        }

        final result = await service.isHardwareDecodeKnownUnsupported(
          codec: 'H.265',
          width: 3840,
          height: 2160,
        );

        expect(result, isTrue);
      });

      test('不同编解码组合的失败计数独立', () async {
        SharedPreferences.setMockInitialValues({});

        // H.264 1920x1080 记录3次失败
        for (int i = 0; i < 3; i++) {
          await service.recordHardwareDecodeFailure(
            codec: 'H.264',
            width: 1920,
            height: 1080,
          );
        }

        // H.265 1920x1080 未记录失败
        final h265Result = await service.isHardwareDecodeKnownUnsupported(
          codec: 'H.265',
          width: 1920,
          height: 1080,
        );

        expect(h265Result, isFalse);

        // H.264 1920x1080 应标记为不支持
        final h264Result = await service.isHardwareDecodeKnownUnsupported(
          codec: 'H.264',
          width: 1920,
          height: 1080,
        );

        expect(h264Result, isTrue);
      });

      test('不同分辨率的失败计数独立', () async {
        SharedPreferences.setMockInitialValues({});

        // H.264 1920x1080 记录3次失败
        for (int i = 0; i < 3; i++) {
          await service.recordHardwareDecodeFailure(
            codec: 'H.264',
            width: 1920,
            height: 1080,
          );
        }

        // H.264 3840x2160 未记录失败
        final result4k = await service.isHardwareDecodeKnownUnsupported(
          codec: 'H.264',
          width: 3840,
          height: 2160,
        );

        expect(result4k, isFalse);
      });
    });
  });
}
