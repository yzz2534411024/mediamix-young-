import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'java_bridge_client.dart';

/// Java Spider Bridge 生命周期管理器
///
/// 负责：
/// 1. 下载 TVBox 蜘蛛 JAR 到本地缓存
/// 2. 启动/停止 Java Bridge 进程
/// 3. 提供共享的 [JavaBridgeClient] 实例
///
/// 使用方式：
/// ```dart
/// final manager = JavaBridgeManager.instance;
/// await manager.initialize(spiderJarUrl: 'https://...');
/// final client = manager.client; // 用于创建 JavaBridgeSpider
/// ```
class JavaBridgeManager {
  static JavaBridgeManager? _instance;
  static JavaBridgeManager get instance => _instance ??= JavaBridgeManager._();

  JavaBridgeManager._();

  final Logger _logger = Logger(printer: SimplePrinter());

  /// 默认桥接端口
  static const int defaultPort = 6868;

  /// Java Bridge 进程
  Process? _process;

  /// 共享的 HTTP 客户端
  JavaBridgeClient? _client;

  /// 桥接是否已启动
  bool _running = false;

  /// 当前端口
  int _port = defaultPort;

  /// Java 可执行文件路径（自动检测）
  String? _javaPath;

  /// 桥接是否已启动
  bool get isRunning => _running;

  /// 共享的 HTTP 客户端（启动后可用）
  JavaBridgeClient? get client => _client;

  /// 当前端口
  int get port => _port;

  /// 初始化并启动桥接
  ///
  /// [spiderJarUrl] 蜘蛛 JAR 下载地址（可选，如已缓存则跳过下载）
  /// [port] 桥接端口，默认 6868
  Future<bool> initialize({String? spiderJarUrl, int port = defaultPort}) async {
    if (_running) return true;

    _port = port;

    // 1. 检测 Java 环境
    _javaPath = await _findJava();
    if (_javaPath == null) {
      _logger.w('未检测到 Java 运行时，Java Bridge 不可用');
      return false;
    }
    _logger.d('Java 路径: $_javaPath');

    // 2. 获取/下载蜘蛛 JAR
    String? jarPath;
    if (spiderJarUrl != null && spiderJarUrl.isNotEmpty) {
      jarPath = await _ensureSpiderJar(spiderJarUrl);
      if (jarPath == null) {
        _logger.w('蜘蛛 JAR 获取失败: $spiderJarUrl');
        return false;
      }
    }

    // 3. 查找 bridge JAR
    final bridgeJarPath = await _findBridgeJar();
    if (bridgeJarPath == null) {
      _logger.w('Bridge JAR 未找到，请先构建: bridge/java-spider-bridge/build.bat');
      return false;
    }

    // 4. 启动 Java Bridge 进程
    try {
      final args = <String>[_port.toString()];
      if (jarPath != null) args.add(jarPath);

      _logger.d('启动 Java Bridge: $_javaPath -jar $bridgeJarPath ${args.join(' ')}');

      _process = await Process.start(
        _javaPath!,
        ['-jar', bridgeJarPath, ...args],
        workingDirectory: p.dirname(bridgeJarPath),
      );

      // 监听进程输出
      _process!.stdout.listen((data) {
        final output = String.fromCharCodes(data).trim();
        if (output.isNotEmpty) {
          _logger.d('[JavaBridge] $output');
        }
      });

      _process!.stderr.listen((data) {
        final output = String.fromCharCodes(data).trim();
        if (output.isNotEmpty) {
          _logger.d('[JavaBridge] $output');
        }
      });

      // 等待桥接就绪
      _client = JavaBridgeClient(baseUrl: 'http://127.0.0.1:$_port');
      final ready = await _waitForReady(maxAttempts: 10);

      if (ready) {
        _running = true;
        _logger.d('Java Bridge 已启动, 端口: $_port');
        return true;
      } else {
        _logger.w('Java Bridge 启动超时');
        _process?.kill();
        _process = null;
        _client?.dispose();
        _client = null;
        return false;
      }
    } catch (e) {
      _logger.e('启动 Java Bridge 失败: $e');
      _process?.kill();
      _process = null;
      _client?.dispose();
      _client = null;
      return false;
    }
  }

  /// 停止桥接
  Future<void> shutdown() async {
    if (!_running) return;

    try {
      await _client?.shutdown();
    } catch (_) {}

    _process?.kill();
    _process = null;
    _client?.dispose();
    _client = null;
    _running = false;
    _logger.d('Java Bridge 已关闭');
  }

  /// 等待桥接就绪
  Future<bool> _waitForReady({int maxAttempts = 10}) async {
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_client != null && await _client!.checkStatus()) {
        return true;
      }
    }
    return false;
  }

  /// 查找 Java 可执行文件
  Future<String?> _findJava() async {
    // 1. 检查 JAVA_HOME
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.isNotEmpty) {
      final javaExe = p.join(javaHome, 'bin', 'java.exe');
      if (File(javaExe).existsSync()) return javaExe;
    }

    // 2. 检查 PATH 中的 java
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['java'],
      );
      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim().split('\n').first.trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}

    // 3. Windows 默认路径
    if (Platform.isWindows) {
      final commonPaths = [
        r'C:\Program Files\Java',
        r'C:\Program Files (x86)\Java',
      ];
      for (final base in commonPaths) {
        final dir = Directory(base);
        if (dir.existsSync()) {
          await for (final entity in dir.list()) {
            if (entity is Directory) {
              final javaExe = p.join(entity.path, 'bin', 'java.exe');
              if (File(javaExe).existsSync()) return javaExe;
            }
          }
        }
      }
    }

    return null;
  }

  /// 确保蜘蛛 JAR 已下载到缓存
  Future<String?> _ensureSpiderJar(String url) async {
    try {
      final cacheDir = await getApplicationSupportDirectory();
      final spiderDir = Directory(p.join(cacheDir.path, 'spider_jar'));
      if (!spiderDir.existsSync()) {
        spiderDir.createSync(recursive: true);
      }

      // 用 URL hash 作为文件名
      final fileName = 'spider_${url.hashCode.toRadixString(16)}.jar';
      final jarFile = File(p.join(spiderDir.path, fileName));

      if (jarFile.existsSync() && jarFile.lengthSync() > 0) {
        _logger.d('蜘蛛 JAR 已缓存: ${jarFile.path}');
        return jarFile.path;
      }

      // 下载 JAR
      _logger.d('下载蜘蛛 JAR: $url');
      final httpClient = HttpClient();

      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode == 200) {
        final sink = jarFile.openWrite();
        await response.pipe(sink);
        _logger.d('蜘蛛 JAR 下载完成: ${jarFile.path} (${jarFile.lengthSync()} bytes)');
        return jarFile.path;
      } else {
        _logger.w('蜘蛛 JAR 下载失败: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _logger.e('下载蜘蛛 JAR 异常: $e');
      return null;
    }
  }

  /// 查找 Bridge JAR 文件
  Future<String?> _findBridgeJar() async {
    // 1. 检查项目目录下的 bridge JAR
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      // 开发模式：项目目录
      p.join(Directory.current.path, 'bridge', 'java-spider-bridge', 'build', 'spider-bridge.jar'),
      // 打包后：可执行文件同级目录
      p.join(exeDir, 'bridge', 'spider-bridge.jar'),
      p.join(exeDir, 'spider-bridge.jar'),
      // 应用数据目录
      p.join((await getApplicationSupportDirectory()).path, 'spider-bridge.jar'),
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        _logger.d('Bridge JAR 找到: $path');
        return path;
      }
    }

    _logger.w('Bridge JAR 未找到，已搜索路径: ${candidates.join(', ')}');
    return null;
  }
}
