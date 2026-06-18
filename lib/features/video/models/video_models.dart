/// CMS API 站点
class CmsApiSite {
  final String key;
  final String name;
  final String apiUrl;
  final bool enabled;
  final bool isBuiltIn;

  const CmsApiSite({
    required this.key,
    required this.name,
    required this.apiUrl,
    this.enabled = true,
    this.isBuiltIn = false,
  });

  CmsApiSite copyWith({
    String? key,
    String? name,
    String? apiUrl,
    bool? enabled,
    bool? isBuiltIn,
  }) {
    return CmsApiSite(
      key: key ?? this.key,
      name: name ?? this.name,
      apiUrl: apiUrl ?? this.apiUrl,
      enabled: enabled ?? this.enabled,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  /// 内置站点列表（2026-06 实测可用）
  static const defaultSites = [
    CmsApiSite(
      key: 'fantaiying',
      name: '饭太硬',
      apiUrl: 'http://www.xn--sss604efuw.net/tv',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'bfzy',
      name: '暴风资源',
      apiUrl: 'https://bfzyapi.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'lzzy',
      name: '量子资源',
      apiUrl: 'https://cj.lziapi.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'ffzy',
      name: '非凡资源',
      apiUrl: 'http://ffzy5.tv/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'hnzy',
      name: '红牛资源',
      apiUrl: 'https://hongniuzy2.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'tyyszy',
      name: '天涯资源',
      apiUrl: 'https://tyyszy.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'jszyapi',
      name: '极速资源',
      apiUrl: 'https://jszyapi.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'zuidapi',
      name: '最大资源',
      apiUrl: 'https://api.zuidapi.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'apibdzy',
      name: '百度资源',
      apiUrl: 'https://api.apibdzy.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'apiwujin',
      name: '无尽资源',
      apiUrl: 'https://api.wujinapi.me/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'rycjapi',
      name: '如意资源',
      apiUrl: 'https://cj.rycjapi.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'apiYhzy',
      name: '樱花资源',
      apiUrl: 'https://m3u8.apiyhzy.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'dbzy',
      name: '豆瓣资源',
      apiUrl: 'https://dbzy.tv/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'mdzyapi',
      name: '魔都资源',
      apiUrl: 'https://www.mdzyapi.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'xiaomaomi',
      name: '小猫咪资源',
      apiUrl: 'https://zy.xiaomaomi.cc/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'dyttzyapi',
      name: '电影天堂',
      apiUrl: 'http://caiji.dyttzyapi.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
  ];
}

/// 视频源类型
enum SourceType { cms, spider }

/// 视频源（CMS 或 Spider）
class VideoSource {
  final String key;
  final String name;
  final String apiUrl;
  final bool enabled;
  final bool isBuiltIn;
  final SourceType sourceType;
  final String? spiderKey;
  final String? playerType;

  const VideoSource({
    required this.key,
    required this.name,
    required this.apiUrl,
    this.enabled = true,
    this.isBuiltIn = false,
    this.sourceType = SourceType.cms,
    this.spiderKey,
    this.playerType,
  });

  VideoSource copyWith({
    String? key,
    String? name,
    String? apiUrl,
    bool? enabled,
    bool? isBuiltIn,
    SourceType? sourceType,
    String? spiderKey,
    String? playerType,
  }) {
    return VideoSource(
      key: key ?? this.key,
      name: name ?? this.name,
      apiUrl: apiUrl ?? this.apiUrl,
      enabled: enabled ?? this.enabled,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      sourceType: sourceType ?? this.sourceType,
      spiderKey: spiderKey ?? this.spiderKey,
      playerType: playerType ?? this.playerType,
    );
  }

  factory VideoSource.fromCmsSite(CmsApiSite site) {
    return VideoSource(
      key: site.key,
      name: site.name,
      apiUrl: site.apiUrl,
      enabled: site.enabled,
      isBuiltIn: site.isBuiltIn,
      sourceType: SourceType.cms,
    );
  }
}

/// 源状态检测结果
class SourceStatus {
  final String key;
  final bool isAvailable;
  final int latencyMs; // 延迟毫秒数，-1 表示不可用
  final String? error;

  const SourceStatus({
    required this.key,
    required this.isAvailable,
    this.latencyMs = -1,
    this.error,
  });
}

/// 影片条目（列表/搜索结果）
class VideoItem {
  final String vodId;
  final String vodName;
  final String? vodPic;
  final String? vodRemarks;
  final String? vodYear;
  final String? vodArea;
  final String? typeName;
  final String? sourceKey; // 来源站点 key

  const VideoItem({
    required this.vodId,
    required this.vodName,
    this.vodPic,
    this.vodRemarks,
    this.vodYear,
    this.vodArea,
    this.typeName,
    this.sourceKey,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json, {String? sourceKey}) {
    return VideoItem(
      vodId: json['vod_id']?.toString() ?? '',
      vodName: json['vod_name']?.toString() ?? '未知',
      vodPic: json['vod_pic']?.toString(),
      vodRemarks: json['vod_remarks']?.toString(),
      vodYear: json['vod_year']?.toString(),
      vodArea: json['vod_area']?.toString(),
      typeName: json['type_name']?.toString(),
      sourceKey: sourceKey,
    );
  }
}

/// 影片列表响应
class VideoListResponse {
  final List<VideoItem> list;
  final int page;
  final int pageCount;
  final int total;

  const VideoListResponse({
    required this.list,
    required this.page,
    required this.pageCount,
    required this.total,
  });

  factory VideoListResponse.fromJson(Map<String, dynamic> json) {
    final List<VideoItem> items = [];
    if (json['list'] != null) {
      for (final item in (json['list'] as List)) {
        if (item is Map<String, dynamic>) {
          items.add(VideoItem.fromJson(item));
        }
      }
    }
    return VideoListResponse(
      list: items,
      page: int.tryParse(json['page']?.toString() ?? '1') ?? 1,
      pageCount: int.tryParse(json['pagecount']?.toString() ?? '1') ?? 1,
      total: int.tryParse(json['total']?.toString() ?? '0') ?? 0,
    );
  }
}

/// 播放源（一个源包含多个剧集）
class PlaySource {
  final String name;
  final List<VideoEpisode> episodes;

  const PlaySource({
    required this.name,
    required this.episodes,
  });
}

/// 影片选集
class VideoEpisode {
  final String name;
  final String url;

  const VideoEpisode({required this.name, required this.url});
}

/// 影片详情
class VideoDetail {
  final String vodId;
  final String vodName;
  final String? vodPic;
  final String? vodContent;
  final String? vodActor;
  final String? vodDirector;
  final String? vodYear;
  final String? vodArea;
  final String? vodRemarks;
  final String? typeName;
  final int? typeId;
  final String sourceKey;
  final List<PlaySource> playSources;

  const VideoDetail({
    required this.vodId,
    required this.vodName,
    this.vodPic,
    this.vodContent,
    this.vodActor,
    this.vodDirector,
    this.vodYear,
    this.vodArea,
    this.vodRemarks,
    this.typeName,
    this.typeId,
    required this.sourceKey,
    this.playSources = const [],
  });

  factory VideoDetail.fromJson(Map<String, dynamic> json, {String sourceKey = ''}) {
    // 解析播放源
    final List<PlaySource> sources = [];
    final vodPlayFrom = json['vod_play_from']?.toString() ?? '';
    final vodPlayUrl = json['vod_play_url']?.toString() ?? '';

    if (vodPlayFrom.isNotEmpty && vodPlayUrl.isNotEmpty) {
      final fromNames = vodPlayFrom.split('\$\$\$');
      final fromUrls = vodPlayUrl.split('\$\$\$');

      for (int i = 0; i < fromNames.length && i < fromUrls.length; i++) {
        final sourceName = fromNames[i].trim();
        final episodesStr = fromUrls[i].trim();
        final List<VideoEpisode> episodes = [];

        if (episodesStr.isNotEmpty) {
          final lines = episodesStr.split('#');
          for (final line in lines) {
            final parts = line.split('\$');
            if (parts.length >= 2) {
              episodes.add(VideoEpisode(
                name: parts[0].trim(),
                url: parts[1].trim(),
              ));
            }
          }
        }

        if (episodes.isNotEmpty) {
          sources.add(PlaySource(name: sourceName, episodes: episodes));
        }
      }
    }

    return VideoDetail(
      vodId: json['vod_id']?.toString() ?? '',
      vodName: json['vod_name']?.toString() ?? '未知',
      vodPic: json['vod_pic']?.toString(),
      vodContent: json['vod_content']?.toString(),
      vodActor: json['vod_actor']?.toString(),
      vodDirector: json['vod_director']?.toString(),
      vodYear: json['vod_year']?.toString(),
      vodArea: json['vod_area']?.toString(),
      vodRemarks: json['vod_remarks']?.toString(),
      typeName: json['type_name']?.toString(),
      typeId: int.tryParse(json['type_id']?.toString() ?? ''),
      sourceKey: sourceKey,
      playSources: sources,
    );
  }
}

/// 影片分类
class VideoCategory {
  final int typeId;
  final int typePid;    // 父分类ID，0表示一级分类
  final String typeName;

  const VideoCategory({
    required this.typeId,
    required this.typePid,
    required this.typeName,
  });

  factory VideoCategory.fromJson(Map<String, dynamic> json) {
    return VideoCategory(
      typeId: int.tryParse(json['type_id']?.toString() ?? '0') ?? 0,
      typePid: int.tryParse(json['type_pid']?.toString() ?? '0') ?? 0,
      typeName: json['type_name']?.toString() ?? '',
    );
  }
}

/// 视频解析接口
class VideoParser {
  final String key;
  final String name;
  final String urlTemplate; // {url} 占位符会被替换为视频URL
  final bool enabled;

  const VideoParser({
    required this.key,
    required this.name,
    required this.urlTemplate,
    this.enabled = true,
  });

  /// 构建解析后的完整URL
  String buildUrl(String videoUrl) {
    return urlTemplate.replaceAll('{url}', Uri.encodeComponent(videoUrl));
  }

  VideoParser copyWith({
    String? key,
    String? name,
    String? urlTemplate,
    bool? enabled,
  }) {
    return VideoParser(
      key: key ?? this.key,
      name: name ?? this.name,
      urlTemplate: urlTemplate ?? this.urlTemplate,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'urlTemplate': urlTemplate,
        'enabled': enabled,
      };

  factory VideoParser.fromJson(Map<String, dynamic> json) => VideoParser(
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        urlTemplate: json['urlTemplate'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
      );

  static const defaultParsers = [
    VideoParser(
      key: 'yparse',
      name: 'YParse',
      urlTemplate: 'https://yparse.ik9.cc/index.php?url={url}',
    ),
    VideoParser(
      key: 'm3u8tv',
      name: 'M3U8.TV',
      urlTemplate: 'https://jx.m3u8.tv/jiexi/?url={url}',
    ),
    VideoParser(
      key: 'ik9',
      name: 'IK9 自建',
      urlTemplate: 'http://82.156.40.118:1234/jx/?url={url}',
    ),
    VideoParser(
      key: 'oftens',
      name: 'Oftens',
      urlTemplate: 'https://jx.oftens.top/player/?url={url}',
    ),
    VideoParser(
      key: 'jlk',
      name: 'JLK解析',
      urlTemplate: 'https://jlk.jianghu.vip/?url={url}',
    ),
  ];
}
