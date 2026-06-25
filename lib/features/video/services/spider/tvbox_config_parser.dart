/// TVBox 配置站点模型
class TvBoxSite {
  final String key;
  final String name;
  final int type;
  final String api;
  final String? ext;
  final String? jar;
  final int? playerType;
  final bool searchable;
  final bool quickSearch;
  final bool changeable;

  const TvBoxSite({
    required this.key,
    required this.name,
    required this.type,
    required this.api,
    this.ext,
    this.jar,
    this.playerType,
    this.searchable = true,
    this.quickSearch = false,
    this.changeable = false,
  });

  /// 是否为 Java 蜘蛛（csp_* 格式）
  bool get isJavaSpider => api.startsWith('csp_');
}

/// TVBox 直播配置模型
class TvBoxLive {
  final String name;
  final String type;
  final String url;
  final int? playerType;

  const TvBoxLive({
    required this.name,
    required this.type,
    required this.url,
    this.playerType,
  });
}

/// TVBox 完整配置模型
class TvBoxConfig {
  final String? spiderUrl;
  final List<TvBoxSite> sites;
  final List<TvBoxLive> lives;
  final List<String> flags;

  const TvBoxConfig({
    this.spiderUrl,
    this.sites = const [],
    this.lives = const [],
    this.flags = const [],
  });
}

/// TVBox 配置解析器
class TvBoxConfigParser {
  const TvBoxConfigParser();

  /// 解析 TVBox 配置 JSON
  TvBoxConfig parse(Map<String, dynamic> json) {
    final rawSpider = json['spider'];
    final spiderUrl = _parseSpiderUrl(rawSpider);

    final sites = _parseSites(json['sites']);
    final lives = _parseLives(json['lives']);
    final flags = _parseFlags(json['flags']);

    return TvBoxConfig(
      spiderUrl: spiderUrl,
      sites: sites,
      lives: lives,
      flags: flags,
    );
  }

  /// spider 字段支持 "jar_url;md5" 格式，只取 jar_url
  String? _parseSpiderUrl(dynamic raw) {
    if (raw == null || raw is! String) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final semicolonIndex = trimmed.indexOf(';');
    if (semicolonIndex == -1) return trimmed;
    return trimmed.substring(0, semicolonIndex).trim();
  }

  /// 解析 sites 数组
  List<TvBoxSite> _parseSites(dynamic raw) {
    if (raw is! List) return const [];

    final result = <TvBoxSite>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final key = _stringValue(item['key']);
      final name = _stringValue(item['name']);
      final api = _stringValue(item['api']);
      if (key == null || name == null || api == null) continue;

      result.add(
        TvBoxSite(
          key: key,
          name: name,
          type: _intValue(item['type']) ?? 0,
          api: api,
          ext: _stringValue(item['ext']),
          jar: _stringValue(item['jar']),
          playerType: _intValue(item['playerType']),
          searchable: (_intValue(item['searchable']) ?? 1) != 0,
          quickSearch: (_intValue(item['quickSearch']) ?? 0) != 0,
          changeable: (_intValue(item['changeable']) ?? 0) != 0,
        ),
      );
    }
    return result;
  }

  /// 解析 lives 数组
  List<TvBoxLive> _parseLives(dynamic raw) {
    if (raw is! List) return const [];

    final result = <TvBoxLive>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final name = _stringValue(item['name']);
      final type = _stringValue(item['type']);
      final url = _stringValue(item['url']);
      if (name == null || type == null || url == null) continue;

      result.add(
        TvBoxLive(
          name: name,
          type: type,
          url: url,
          playerType: _intValue(item['playerType']),
        ),
      );
    }
    return result;
  }

  /// 解析 flags 数组
  List<String> _parseFlags(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList();
  }

  /// 安全提取字符串
  String? _stringValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  /// 安全提取 int，支持 int 或 string
  int? _intValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return int.tryParse(trimmed);
    }
    return null;
  }
}
