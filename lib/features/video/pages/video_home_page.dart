import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/video_providers.dart';
import '../models/video_models.dart';

class VideoHomePage extends ConsumerStatefulWidget {
  const VideoHomePage({super.key});

  @override
  ConsumerState<VideoHomePage> createState() => _VideoHomePageState();
}

class _VideoHomePageState extends ConsumerState<VideoHomePage> {
  final ScrollController _scrollController = ScrollController();

  // Banner 轮播相关
  final PageController _bannerController = PageController();
  int _bannerIndex = 0;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _bannerController.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    final listState = ref.read(videoListProvider).valueOrNull;
    if (listState == null) return;
    final remainingItems = listState.items.length - (_scrollController.position.pixels / 200).floor();
    const threshold = 20;
    if (remainingItems < threshold && listState.hasMore && !listState.isLoadingMore) {
      ref.read(videoListProvider.notifier).loadMore();
    }
  }

  void _switchSite(CmsApiSite site) {
    ref.read(currentSiteProvider.notifier).state = site;
    ref.read(selectedCategoryProvider.notifier).state = null;
  }

  void _selectCategory(VideoCategory? category) {
    ref.read(selectedCategoryProvider.notifier).state = category;
    ref.read(videoListProvider.notifier).refresh();
  }

  /// 启动 Banner 自动轮播
  void _startBannerTimer(int itemCount) {
    _bannerTimer?.cancel();
    if (itemCount <= 1) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final nextIndex = (_bannerIndex + 1) % itemCount;
      _bannerController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(cmsSiteListProvider);
    final currentSite = ref.watch(currentSiteProvider);
    final categoriesAsync = ref.watch(categoryListProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final listAsync = ref.watch(videoListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Young'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => ref.read(videoListProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 站点切换
          if (sites.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: sites.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final site = sites[index];
                  final isSelected = currentSite?.key == site.key;
                  return FilterChip(
                    label: Text(site.name, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => _switchSite(site),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
          // 分类导航栏
          SizedBox(
            height: 40,
            child: categoriesAsync.when(
              data: (categories) {
                final topCategories = categories.where((c) => c.typePid == 0).toList();
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: topCategories.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ChoiceChip(
                        label: const Text('全部', style: TextStyle(fontSize: 12)),
                        selected: selectedCategory == null,
                        onSelected: (_) => _selectCategory(null),
                        visualDensity: VisualDensity.compact,
                      );
                    }
                    final cat = topCategories[index - 1];
                    return ChoiceChip(
                      label: Text(cat.typeName, style: const TextStyle(fontSize: 12)),
                      selected: selectedCategory?.typeId == cat.typeId,
                      onSelected: (_) => _selectCategory(cat),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
          const Divider(height: 1),
          // 影片内容（Banner + 列表）
          Expanded(
            child: listAsync.when(
              loading: () => _buildSkeletonContent(),
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
                        onPressed: () => ref.read(videoListProvider.notifier).refresh(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (listState) {
                if (listState.items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.movie_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('暂无影片数据', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => ref.read(videoListProvider.notifier).refresh(),
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      // Banner 轮播（取前5条数据）
                      if (listState.items.length >= 2 && selectedCategory == null)
                        SliverToBoxAdapter(
                          child: _BannerSection(
                            items: listState.items.take(5).toList(),
                            sourceKey: currentSite?.key ?? '',
                            pageController: _bannerController,
                            onPageChanged: (index) {
                              setState(() => _bannerIndex = index);
                            },
                            onInit: (itemCount) => _startBannerTimer(itemCount),
                          ),
                        ),
                      // 影片网格
                      SliverPadding(
                        padding: const EdgeInsets.all(8),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.58,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index < listState.items.length) {
                                final item = listState.items[index];
                                return _VideoCard(item: item, sourceKey: currentSite?.key ?? '');
                              }
                              // 加载更多指示器
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            },
                            childCount: listState.items.length + (listState.isLoadingMore ? 1 : 0),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.movie), label: '视频'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.favorite), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
        onDestinationSelected: (index) {
          if (index == 1) context.go('/history');
          if (index == 2) context.go('/favorite');
          if (index == 3) context.go('/settings');
        },
      ),
    );
  }

  /// 骨架屏（含 Banner 占位）
  Widget _buildSkeletonContent() {
    return CustomScrollView(
      slivers: [
        // Banner 骨架
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        // 网格骨架
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.58,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, __) => const _SkeletonCard(),
              childCount: 9,
            ),
          ),
        ),
      ],
    );
  }
}

/// Banner 轮播区域
class _BannerSection extends StatefulWidget {
  final List<VideoItem> items;
  final String sourceKey;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onInit;

  const _BannerSection({
    required this.items,
    required this.sourceKey,
    required this.pageController,
    required this.onPageChanged,
    required this.onInit,
  });

  @override
  State<_BannerSection> createState() => _BannerSectionState();
}

class _BannerSectionState extends State<_BannerSection> {
  @override
  void initState() {
    super.initState();
    widget.onInit(widget.items.length);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          // 轮播图
          SizedBox(
            height: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: PageView.builder(
                controller: widget.pageController,
                onPageChanged: widget.onPageChanged,
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return GestureDetector(
                    onTap: () {
                      context.push('/detail?vodId=${Uri.encodeComponent(item.vodId)}&sourceKey=${Uri.encodeComponent(widget.sourceKey)}');
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 背景图
                        CachedNetworkImage(
                          imageUrl: item.vodPic ?? '',
                          fit: BoxFit.cover,
                          memCacheWidth: 800,
                          placeholder: (_, __) => Container(color: Colors.grey[300]),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.movie, color: Colors.grey, size: 48),
                          ),
                        ),
                        // 渐变遮罩
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withAlpha(180),
                              ],
                              stops: const [0.5, 1.0],
                            ),
                          ),
                        ),
                        // 底部文字
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.vodName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (item.typeName != null && item.typeName!.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary.withAlpha(180),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        item.typeName!,
                                        style: const TextStyle(color: Colors.white, fontSize: 11),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  if (item.vodRemarks != null && item.vodRemarks!.isNotEmpty)
                                    Text(
                                      item.vodRemarks!,
                                      style: TextStyle(
                                        color: Colors.orange[300],
                                        fontSize: 12,
                                        shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 指示器（小圆点）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.items.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: index == 0 ? 16 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: index == 0
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[400],
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// 骨架屏卡片
class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = (_controller.value * 2).clamp(0.0, 1.0);
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  color: Colors.grey[200]!.withAlpha((100 + 80 * value).round()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey[300]!.withAlpha((100 + 80 * value).round()),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 10,
                      width: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey[300]!.withAlpha((100 + 80 * value).round()),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 影片卡片（带 Hero 动画）
class _VideoCard extends StatelessWidget {
  final VideoItem item;
  final String sourceKey;

  const _VideoCard({required this.item, required this.sourceKey});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          context.push('/detail?vodId=${Uri.encodeComponent(item.vodId)}&sourceKey=${Uri.encodeComponent(sourceKey)}');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面图（Hero 动画）
            Expanded(
              child: Hero(
                tag: 'video_${item.vodId}',
                child: item.vodPic != null && item.vodPic!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.vodPic!,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        placeholder: (_, __) => Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.movie, color: Colors.grey, size: 32)),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 32)),
                        ),
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.movie, color: Colors.grey, size: 32)),
                      ),
              ),
            ),
            // 剧名 + 备注
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.vodName,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.vodRemarks != null && item.vodRemarks!.isNotEmpty)
                    Text(
                      item.vodRemarks!,
                      style: TextStyle(fontSize: 10, color: Colors.orange[700]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
