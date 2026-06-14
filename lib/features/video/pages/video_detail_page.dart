import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/video_providers.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/services/download_service.dart';
import '../models/video_models.dart';

class VideoDetailPage extends ConsumerWidget {
  final String vodId;
  final String sourceKey;

  const VideoDetailPage({super.key, required this.vodId, required this.sourceKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(videoDetailProvider((vodId: vodId, sourceKey: sourceKey)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('影片详情'),
        actions: [
          _FavoriteButton(vodId: vodId, sourceKey: sourceKey),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('加载失败', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                const SizedBox(height: 8),
                Text('$e', style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(videoDetailProvider((vodId: vodId, sourceKey: sourceKey))),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (detail) => _DetailContent(detail: detail),
      ),
    );
  }
}

/// 收藏按钮
class _FavoriteButton extends ConsumerWidget {
  final String vodId;
  final String sourceKey;

  const _FavoriteButton({required this.vodId, required this.sourceKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavAsync = ref.watch(isFavoriteProvider(vodId));
    final isFav = isFavAsync.valueOrNull ?? false;
    return IconButton(
      icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.red : null),
      onPressed: () async {
        // 从详情 Provider 获取影片信息
        final detailAsync = ref.read(videoDetailProvider((vodId: vodId, sourceKey: sourceKey)));
        final detail = detailAsync.valueOrNull;
        await ref.read(favoriteActionsProvider).toggleFavorite(
          vodId: vodId,
          vodName: detail?.vodName ?? '',
          vodPic: detail?.vodPic,
          sourceKey: sourceKey,
          typeName: detail?.typeName,
          episodeCount: detail?.playSources.fold<int>(0, (sum, s) => sum + s.episodes.length) ?? 0,
        );
      },
    );
  }
}

class _DetailContent extends ConsumerStatefulWidget {
  final VideoDetail detail;

  const _DetailContent({required this.detail});

  @override
  ConsumerState<_DetailContent> createState() => _DetailContentState();
}

class _DetailContentState extends ConsumerState<_DetailContent> {
  int _selectedSourceIndex = 0;
  bool _isContentExpanded = false;

  @override
  void initState() {
    super.initState();
    // 写入观看历史 + 追番检测
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(watchHistoryActionsProvider).addOrUpdateHistory(
        vodId: widget.detail.vodId,
        vodName: widget.detail.vodName,
        vodPic: widget.detail.vodPic,
        sourceKey: widget.detail.sourceKey,
      );
      _checkFavoriteUpdate();
    });
  }

  /// 追番更新检测
  void _checkFavoriteUpdate() async {
    final detail = widget.detail;
    final totalEpisodes = detail.playSources.fold<int>(0, (sum, s) => sum + s.episodes.length);
    final hasUpdate = await ref.read(favoriteActionsProvider).hasUpdate(detail.vodId, totalEpisodes);
    if (hasUpdate && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('有新集数更新！'), duration: Duration(seconds: 2)),
      );
      // 标记已读
      ref.read(favoriteActionsProvider).markAsRead(detail.vodId, totalEpisodes);
    }
    // 如果已收藏，更新集数
    final isFav = await ref.read(databaseProvider).getFavorite(detail.vodId);
    if (isFav != null) {
      ref.read(favoriteActionsProvider).markAsRead(detail.vodId, totalEpisodes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final sources = detail.playSources;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 顶部：封面 + 基本信息
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图（Hero 动画）
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 170,
                child: Hero(
                  tag: 'video_${detail.vodId}',
                  child: detail.vodPic != null && detail.vodPic!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: detail.vodPic!,
                        fit: BoxFit.cover,
                        memCacheWidth: 600,
                        placeholder: (_, __) => Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.movie, color: Colors.grey, size: 36)),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 36)),
                        ),
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.movie, color: Colors.grey, size: 36)),
                      ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // 名称 + 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.vodName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  if (detail.typeName != null && detail.typeName!.isNotEmpty)
                    _InfoChip(icon: Icons.category, text: detail.typeName!),
                  if (detail.vodYear != null && detail.vodYear!.isNotEmpty)
                    _InfoChip(icon: Icons.calendar_today, text: detail.vodYear!),
                  if (detail.vodArea != null && detail.vodArea!.isNotEmpty)
                    _InfoChip(icon: Icons.public, text: detail.vodArea!),
                  if (detail.vodRemarks != null && detail.vodRemarks!.isNotEmpty)
                    _InfoChip(icon: Icons.info_outline, text: detail.vodRemarks!, color: Colors.orange),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 简介（可展开）
        if (detail.vodContent != null && detail.vodContent!.isNotEmpty) ...[
          Row(
            children: [
              const Text('简介', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _isContentExpanded = !_isContentExpanded),
                icon: Icon(_isContentExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
                label: Text(_isContentExpanded ? '收起' : '展开'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedCrossFade(
            firstChild: Text(
              detail.vodContent!.replaceAll(RegExp(r'<[^>]*>'), ''), // 去除 HTML 标签
              style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            secondChild: Text(
              detail.vodContent!.replaceAll(RegExp(r'<[^>]*>'), ''),
              style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
            ),
            crossFadeState: _isContentExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
          const SizedBox(height: 16),
        ],

        // 演员
        if (detail.vodActor != null && detail.vodActor!.isNotEmpty) ...[
          Text('演员', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(detail.vodActor!, style: TextStyle(fontSize: 13, color: Colors.grey[800]), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
        ],

        // 导演
        if (detail.vodDirector != null && detail.vodDirector!.isNotEmpty) ...[
          Text('导演', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(detail.vodDirector!, style: TextStyle(fontSize: 13, color: Colors.grey[800]), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
        ],

        // 播放源切换 + 剧集列表
        if (sources.isNotEmpty) ...[
          const Divider(),
          const SizedBox(height: 8),
          // 播放源切换 Chips
          if (sources.length > 1)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sources.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final source = sources[index];
                  final isSelected = _selectedSourceIndex == index;
                  return ChoiceChip(
                    label: Text(source.name, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedSourceIndex = index),
                  );
                },
              ),
            ),
          if (sources.length > 1) const SizedBox(height: 12),

          // 当前源的剧集列表
          _EpisodeGrid(
            episodes: sources[_selectedSourceIndex].episodes,
            sourceName: sources[_selectedSourceIndex].name,
            allSources: sources,
            selectedIndex: _selectedSourceIndex,
            vodId: widget.detail.vodId,
            vodName: widget.detail.vodName,
          ),
        ],

        // 无播放源提示
        if (sources.isEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Icon(Icons.play_circle_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('暂无播放源', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 信息标签
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _InfoChip({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? Colors.grey[600]),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color ?? Colors.grey[700]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 剧集网格
class _EpisodeGrid extends StatelessWidget {
  final List<VideoEpisode> episodes;
  final String sourceName;
  final List<PlaySource> allSources;
  final int selectedIndex;
  final String vodId;
  final String vodName;

  const _EpisodeGrid({
    required this.episodes,
    required this.sourceName,
    required this.allSources,
    required this.selectedIndex,
    required this.vodId,
    required this.vodName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选集 (${episodes.length})',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(episodes.length, (index) {
            final ep = episodes[index];
            return ActionChip(
              label: Text(ep.name, style: const TextStyle(fontSize: 12)),
              onPressed: () {
                // 构建播放参数
                final epNames = episodes.map((e) => e.name).join(',');
                final epUrls = episodes.map((e) => e.url).join(',');
                context.push(
                  '/player?url=${Uri.encodeComponent(ep.url)}'
                  '&title=${Uri.encodeComponent(ep.name)}'
                  '&index=$index'
                  '&epNames=${Uri.encodeComponent(epNames)}'
                  '&epUrls=${Uri.encodeComponent(epUrls)}',
                );
              },
              avatar: IconButton(
                icon: const Icon(Icons.download, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                onPressed: () {
                  final container = ProviderScope.containerOf(context);
                  container.read(downloadServiceProvider).startDownload(
                    vodId: vodId,
                    vodName: vodName,
                    episodeName: ep.name,
                    videoUrl: ep.url,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已添加下载：${ep.name}'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}
