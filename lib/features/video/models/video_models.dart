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

  /// 内置站点列表
  static const defaultSites = [
    CmsApiSite(
      key: 'bfzy',
      name: '暴风资源',
      apiUrl: 'https://bfzyapi.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'lzzy',
      name: '量子资源',
      apiUrl: 'https://cjhd.lziapi.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'ffzy',
      name: '非凡资源',
      apiUrl: 'https://cjhd.ffzyapi.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'zyk1080',
      name: '1080资源库',
      apiUrl: 'http://api.1080zyku.com/inc/api.php/provide/vod/',
      isBuiltIn: true,
    ),
    CmsApiSite(
      key: 'hnzy',
      name: '红牛资源',
      apiUrl: 'http://hongniuzy2.com/api.php/provide/vod/',
      isBuiltIn: true,
    ),
  ];
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
