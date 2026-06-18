import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

/// 代理类型
enum ProxyType {
  none,
  http,
  socks5,
}

/// 代理配置
class ProxyConfig {
  final ProxyType type;
  final String host;
  final int port;
  final String? username;
  final String? password;

  const ProxyConfig({
    this.type = ProxyType.none,
    this.host = '',
    this.port = 1080,
    this.username,
    this.password,
  });

  bool get isEnabled => type != ProxyType.none && host.isNotEmpty;

  ProxyConfig copyWith({
    ProxyType? type,
    String? host,
    int? port,
    String? username,
    String? password,
  }) {
    return ProxyConfig(
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'host': host,
        'port': port,
        'username': username ?? '',
        'password': password ?? '',
      };

  factory ProxyConfig.fromJson(Map<String, dynamic> json) => ProxyConfig(
        type: ProxyType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => ProxyType.none,
        ),
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 1080,
        username: (json['username'] as String?)?.isNotEmpty == true
            ? json['username']
            : null,
        password: (json['password'] as String?)?.isNotEmpty == true
            ? json['password']
            : null,
      );
}

/// 代理配置服务
///
/// 管理全局代理设置，持久化到 SharedPreferences，
/// 自动应用到所有 Dio 实例的 HttpClient。
class ProxyConfigService {
  static final ProxyConfigService instance = ProxyConfigService._();
  ProxyConfigService._();

  final Logger _logger = Logger(printer: SimplePrinter());
  static const String _prefKey = 'proxy_config';

  ProxyConfig _config = const ProxyConfig();

  /// 当前代理配置
  ProxyConfig get config => _config;

  /// 是否启用代理
  bool get isEnabled => _config.isEnabled;

  /// 获取代理 URL 字符串（用于 Dio 的 proxy 选项）
  String? get proxyUrl {
    if (!isEnabled) return null;
    final auth = _config.username != null && _config.password != null
        ? '${_config.username}:${_config.password}@'
        : '';
    final scheme = _config.type == ProxyType.socks5 ? 'socks5' : 'http';
    return '$scheme://$auth${_config.host}:${_config.port}';
  }

  /// 初始化：从 SharedPreferences 加载配置
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null) {
        _config = ProxyConfig.fromJson(
          Map<String, dynamic>.from(
            Uri.splitQueryString(json).map((k, v) => MapEntry(k, v)),
          ),
        );
        // 用更可靠的反序列化方式
        _loadFromPrefs(prefs);
      }
      _logger.d('代理配置已加载: ${_config.isEnabled ? "${_config.type.name}://${_config.host}:${_config.port}" : "未启用"}');
    } catch (e) {
      _logger.w('加载代理配置失败: $e');
    }
  }

  Future<void> _loadFromPrefs(SharedPreferences prefs) async {
    final type = prefs.getString('proxy_type') ?? 'none';
    final host = prefs.getString('proxy_host') ?? '';
    final port = prefs.getInt('proxy_port') ?? 1080;
    final username = prefs.getString('proxy_username');
    final password = prefs.getString('proxy_password');

    _config = ProxyConfig(
      type: ProxyType.values.firstWhere(
        (e) => e.name == type,
        orElse: () => ProxyType.none,
      ),
      host: host,
      port: port,
      username: username?.isNotEmpty == true ? username : null,
      password: password?.isNotEmpty == true ? password : null,
    );
  }

  /// 更新代理配置
  Future<void> updateConfig(ProxyConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('proxy_type', config.type.name);
    await prefs.setString('proxy_host', config.host);
    await prefs.setInt('proxy_port', config.port);
    if (config.username != null) {
      await prefs.setString('proxy_username', config.username!);
    } else {
      await prefs.remove('proxy_username');
    }
    if (config.password != null) {
      await prefs.setString('proxy_password', config.password!);
    } else {
      await prefs.remove('proxy_password');
    }
    _logger.i('代理配置已更新: ${config.isEnabled ? "${config.type.name}://${config.host}:${config.port}" : "已禁用"}');
  }

  /// 禁用代理
  Future<void> disable() async {
    await updateConfig(const ProxyConfig(type: ProxyType.none));
  }

  /// 为 HttpClient 设置代理（用于 Dio 的 createHttpClient 回调）
  void configureHttpClient(HttpClient client) {
    if (!isEnabled) return;

    client.findProxy = (uri) {
      // 本地地址不走代理
      if (uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host == '::1') {
        return 'DIRECT';
      }
      switch (_config.type) {
        case ProxyType.http:
          return 'PROXY ${_config.host}:${_config.port}';
        case ProxyType.socks5:
          return 'SOCKS5 ${_config.host}:${_config.port}';
        default:
          return 'DIRECT';
      }
    };

    // 代理认证
    if (_config.username != null && _config.password != null) {
      client.addProxyCredentials(
        _config.host,
        _config.port,
        'basic',
        HttpClientBasicCredentials(_config.username!, _config.password!),
      );
    }

    client.badCertificateCallback = (cert, host, port) => true;
  }
}
