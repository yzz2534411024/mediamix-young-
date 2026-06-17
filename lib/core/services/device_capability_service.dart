import 'dart:io';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 解码器能力记录
class CodecCapability {
  final String codec;
  final int maxWidth;
  final int maxHeight;
  final bool hardwareDecodingSupported;

  const CodecCapability({
    required this.codec,
    required this.maxWidth,
    required this.maxHeight,
    required this.hardwareDecodingSupported,
  });

  Map<String, dynamic> toJson() => {
        'codec': codec,
        'maxWidth': maxWidth,
        'maxHeight': maxHeight,
        'hardwareDecodingSupported': hardwareDecodingSupported,
      };

  factory CodecCapability.fromJson(Map<String, dynamic> json) => CodecCapability(
        codec: json['codec'] as String,
        maxWidth: json['maxWidth'] as int,
        maxHeight: json['maxHeight'] as int,
        hardwareDecodingSupported: json['hardwareDecodingSupported'] as bool,
      );
}

/// 设备能力报告
class DeviceCapabilityReport {
  final String platform;
  final String cpuArch;
  final int totalRamMB;
  final int cpuCores;
  final List<CodecCapability> codecCapabilities;
  final bool isLowEndDevice;

  const DeviceCapabilityReport({
    required this.platform,
    required this.cpuArch,
    required this.totalRamMB,
    required this.cpuCores,
    required this.codecCapabilities,
    required this.isLowEndDevice,
  });

  /// 最大推荐分辨率
  String get recommendedMaxResolution {
    if (isLowEndDevice) return '720p';
    if (totalRamMB < 4000) return '1080p';
    return '4K';
  }

  /// 最大推荐帧率
  int get recommendedMaxFps {
    if (isLowEndDevice) return 24;
    if (totalRamMB < 4000) return 30;
    return 60;
  }

  /// 是否推荐硬解码
  bool get recommendHardwareDecoding => !isLowEndDevice;
}

/// 设备能力检测服务
///
/// 在首次启动时探测设备的编解码能力和硬件资源，
/// 结果持久化到 SharedPreferences，供播放器决策使用。
class DeviceCapabilityService {
  static final DeviceCapabilityService instance = DeviceCapabilityService._();
  DeviceCapabilityService._();

  final Logger _logger = Logger(printer: SimplePrinter());

  DeviceCapabilityReport? _cachedReport;
  static const String _prefKey = 'device_capability_report';
  static const String _detectedKey = 'device_capability_detected';

  /// 获取设备能力报告（优先使用缓存）
  Future<DeviceCapabilityReport> getCapabilityReport() async {
    if (_cachedReport != null) return _cachedReport!;

    // 尝试从 SharedPreferences 加载缓存
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefKey);
    if (cached != null) {
      try {
        _cachedReport = _parseReportFromJson(cached);
        return _cachedReport!;
      } catch (e) {
        _logger.w('缓存的能力报告解析失败: $e');
      }
    }

    // 首次探测
    _cachedReport = await _detectCapabilities();
    await prefs.setString(_prefKey, _serializeReport(_cachedReport!));
    await prefs.setBool(_detectedKey, true);
    return _cachedReport!;
  }

  /// 是否已完成首次探测
  Future<bool> hasDetected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_detectedKey) ?? false;
  }

  /// 探测设备能力（所有子方法都有独立 try-catch，确保不会整体崩溃）
  Future<DeviceCapabilityReport> _detectCapabilities() async {
    String platform = 'unknown';
    String cpuArch = 'unknown';
    int totalRamMB = 2048;
    int cpuCores = 2;

    try { platform = Platform.operatingSystem; } catch (_) {}
    try { cpuArch = _detectCpuArch(); } catch (_) {}
    try { totalRamMB = _estimateRamMB(); } catch (_) {}
    try { cpuCores = Platform.numberOfProcessors; } catch (_) {}

    final isLowEndDevice = totalRamMB < 2000 || cpuCores <= 2;

    List<CodecCapability> codecCapabilities;
    try {
      codecCapabilities = _buildDefaultCodecCapabilities(
        platform: platform,
        isLowEnd: isLowEndDevice,
      );
    } catch (_) {
      codecCapabilities = _buildDefaultCodecCapabilities(
        platform: 'android',
        isLowEnd: true,
      );
    }

    _logger.i('设备能力探测完成: $platform, $cpuArch, ${totalRamMB}MB RAM, '
        '$cpuCores核, 低端设备=$isLowEndDevice');

    return DeviceCapabilityReport(
      platform: platform,
      cpuArch: cpuArch,
      totalRamMB: totalRamMB,
      cpuCores: cpuCores,
      codecCapabilities: codecCapabilities,
      isLowEndDevice: isLowEndDevice,
    );
  }

  /// 检测 CPU 架构
  String _detectCpuArch() {
    // dart:io 不直接暴露 CPU 架构，但可以从环境或其他方式推断
    try {
      if (Platform.isAndroid) {
        // Android 上可通过 /proc/cpuinfo 检测
        // 简化处理：arm64 vs arm vs x86_64
        final result = Process.runSync('uname', ['-m']);
        if (result.exitCode == 0) {
          return result.stdout.toString().trim();
        }
      }
    } catch (_) {}
    return 'unknown';
  }

  /// 估算 RAM 大小（MB）
  int _estimateRamMB() {
    try {
      if (Platform.isAndroid) {
        final result = Process.runSync('cat', ['/proc/meminfo']);
        if (result.exitCode == 0) {
          final content = result.stdout.toString();
          // 解析 MemTotal 行: "MemTotal:       12345678 kB"
          final match = RegExp(r'MemTotal:\s+(\d+)').firstMatch(content);
          if (match != null) {
            final kb = int.tryParse(match.group(1)!) ?? 0;
            return kb ~/ 1024;
          }
        }
      }
      if (Platform.isIOS) {
        // iOS 设备内存范围估算
        // 通过 NSProcessInfo 获取，此处用物理页面×页面大小
        final result = Process.runSync('sysctl', ['hw.memsize']);
        if (result.exitCode == 0) {
          final bytes = int.tryParse(result.stdout.toString().trim()) ?? 0;
          return bytes ~/ (1024 * 1024);
        }
      }
    } catch (_) {}
    return 2048; // 默认假设 2GB
  }

  /// 根据平台和能力构建默认编解码能力表
  List<CodecCapability> _buildDefaultCodecCapabilities({
    required String platform,
    required bool isLowEnd,
  }) {
    // 基于广泛测试的保守默认值
    if (platform == 'android') {
      return [
        const CodecCapability(
          codec: 'H.264',
          maxWidth: 1920,
          maxHeight: 1080,
          hardwareDecodingSupported: true,
        ),
        CodecCapability(
          codec: 'H.264',
          maxWidth: 3840,
          maxHeight: 2160,
          hardwareDecodingSupported: !isLowEnd,
        ),
        CodecCapability(
          codec: 'H.265',
          maxWidth: 1920,
          maxHeight: 1080,
          hardwareDecodingSupported: !isLowEnd,
        ),
        const CodecCapability(
          codec: 'H.265',
          maxWidth: 3840,
          maxHeight: 2160,
          hardwareDecodingSupported: false, // 多数设备不支持 4K H.265 硬解
        ),
        const CodecCapability(
          codec: 'VP9',
          maxWidth: 1920,
          maxHeight: 1080,
          hardwareDecodingSupported: true, // Android 4.3+ 普遍支持
        ),
        const CodecCapability(
          codec: 'AV1',
          maxWidth: 1920,
          maxHeight: 1080,
          hardwareDecodingSupported: false, // 仅少数高端 SoC 支持
        ),
      ];
    }

    // iOS / 其他
    return [
      const CodecCapability(
        codec: 'H.264',
        maxWidth: 3840,
        maxHeight: 2160,
        hardwareDecodingSupported: true,
      ),
      const CodecCapability(
        codec: 'H.265',
        maxWidth: 3840,
        maxHeight: 2160,
        hardwareDecodingSupported: true,
      ),
      const CodecCapability(
        codec: 'VP9',
        maxWidth: 1920,
        maxHeight: 1080,
        hardwareDecodingSupported: true,
      ),
    ];
  }

  /// 查询指定编码格式+分辨率的硬件解码能力
  ///
  /// 返回最近的匹配项（分辨率≥请求值的最小分辨率），无匹配则返回 null。
  Future<CodecCapability?> getCodecCapability({
    required String codec,
    required int width,
    required int height,
  }) async {
    final report = await getCapabilityReport();
    CodecCapability? bestMatch;
    for (final cap in report.codecCapabilities) {
      if (cap.codec.toUpperCase() != codec.toUpperCase()) continue;
      if (cap.maxWidth < width || cap.maxHeight < height) continue;
      // 选择满足要求的最小分辨率（最接近的匹配）
      if (bestMatch == null ||
          (cap.maxWidth * cap.maxHeight < bestMatch.maxWidth * bestMatch.maxHeight)) {
        bestMatch = cap;
      }
    }
    return bestMatch;
  }

  /// 查询指定编码格式是否推荐硬解
  Future<bool> canHardwareDecode({
    required String codec,
    required int width,
    required int height,
  }) async {
    final cap = await getCodecCapability(codec: codec, width: width, height: height);
    return cap?.hardwareDecodingSupported ?? false;
  }

  /// 记录硬解码失败（运行时学习）
  Future<void> recordHardwareDecodeFailure({
    required String codec,
    required int width,
    required int height,
  }) async {
    _logger.w('硬解码失败记录: $codec ${width}x$height');
    final prefs = await SharedPreferences.getInstance();
    final key = 'hwdec_failure_${codec}_${width}x$height';
    final count = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, count);

    // 失败超过 3 次则标记为该组合不支持硬解
    if (count >= 3) {
      _logger.w('$codec ${width}x$height 已标记为不支持硬解码');
    }
  }

  /// 检查某个编解码组合是否已知不支持硬解码
  Future<bool> isHardwareDecodeKnownUnsupported({
    required String codec,
    required int width,
    required int height,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'hwdec_failure_${codec}_${width}x$height';
    final count = prefs.getInt(key) ?? 0;
    return count >= 3;
  }

  // ---- 序列化 ----

  String _serializeReport(DeviceCapabilityReport report) {
    return '${report.platform}|${report.cpuArch}|${report.totalRamMB}|${report.cpuCores}|${report.isLowEndDevice}';
  }

  DeviceCapabilityReport _parseReportFromJson(String json) {
    final parts = json.split('|');
    final platform = parts[0];
    final cpuArch = parts[1];
    final totalRamMB = int.parse(parts[2]);
    final cpuCores = int.parse(parts[3]);
    final isLowEnd = parts[4] == 'true';

    return DeviceCapabilityReport(
      platform: platform,
      cpuArch: cpuArch,
      totalRamMB: totalRamMB,
      cpuCores: cpuCores,
      codecCapabilities: _buildDefaultCodecCapabilities(
        platform: platform,
        isLowEnd: isLowEnd,
      ),
      isLowEndDevice: isLowEnd,
    );
  }
}
